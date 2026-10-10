#!/usr/bin/env python3
"""hitchprof：找出卡頓（FPS drop）時多做了什麼。

以 Metal HUD 效能報告的逐幀時間找出卡頓的幀，把 machsample 的取樣分成「卡頓期間」與「平常」，
比較兩者的執行緒 CPU、其他程序 CPU、程序計數（page fault 等）、執行緒狀態與呼叫鏈；
卡頓期間明顯多出來的項目就是嫌疑最大的地方。

用法：hitchprof.py <machsample 輸出> <HUD 效能報告> --start-us N [--threshold-ms N] [--lead-ms N] [--top N]
  HUD 效能報告：libMTLHud 產生的 libMTLHud_<程序>_<時間>_<秒數>s.html（格式見 parse_report）；
  --start-us      要求產生報告的時間（epoch 微秒；stack.sh hitch 記在 report-start.txt），報告的第一幀由此起算
  沒有幀資料時只輸出整段擷取的統計。
  --threshold-ms  卡頓門檻（預設：中位數 ×3 與中位數 +25 ms 取大者）
  --lead-ms       卡頓幀往前多算的時間（預設 2 幀）：D3DMetal 會排隊數幀，造成卡頓的工作可能早於該幀開始
  --top N         各清單列出幾項（預設 12）
外部工具：atos（Xcode）、symx86（環境變數 SYMX86）；有 LLVM（pesym.py）時另解析 Wine PE DLL 的函式名。
"""

from __future__ import annotations

import argparse
import bisect
import collections
import json
import re
import statistics
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import pesym
import symbolize

X86_FRAMES = 12  # 每個堆疊用前幾個 x86 位址統計（越後面越可能是堆疊上殘留的舊值）
SIGNATURE_FRAMES = 4  # 顯示呼叫鏈時取前幾層
PE_SUFFIXES = (".dll", ".exe", ".drv", ".sys", ".ocx", ".acm", ".ax", ".cpl", ".aes")
SHARED_CACHE = (0x7FF800000000, 0x800000000000)  # x86 shared cache 與其 Rosetta 翻譯碼
COUNTERS = (
    ("faults", "page fault"),
    ("pageins", "page in"),
    ("cow", "COW fault"),
    ("csw", "context switch"),
    ("mach", "Mach 系統呼叫"),
    ("unix", "Unix 系統呼叫"),
)
# Mach trap（x16 為負值）；只列常見的，其餘顯示號碼
MACH_TRAPS = {
    -10: "vm_allocate",
    -12: "vm_deallocate",
    -14: "vm_protect",
    -15: "vm_map",
    -31: "mach_msg",
    -32: "mach_msg_overwrite",
    -33: "semaphore_signal",
    -36: "semaphore_wait",
    -37: "semaphore_wait_signal",
    -38: "semaphore_timedwait",
    -39: "semaphore_timedwait_signal",
    -47: "mach_msg2",
    -59: "swtch_pri",
    -60: "swtch",
    -61: "thread_switch",
    -62: "clock_sleep",
    -89: "mach_timebase_info",
    -90: "mach_wait_until",
    -93: "mk_timer_arm",
}
ATOS_IN = re.compile(r" \(in [^)]*\)")
SYMBOL_SUFFIX = re.compile(r"(\s*\+\s*(0x)?[0-9a-f]+)?( \([^()]*:\d+\))?$")  # +偏移、(檔案:行號)
REPORT_JSON = re.compile(r"<script[^>]*>\s*(\{.*?\})\s*</script>", re.DOTALL)
REPORT_ROW = re.compile(r"<tr>\s*<td[^>]*>([^<]+)</td>((?:\s*<td[^>]*>[^<]*</td>)+)\s*</tr>")
# 報告的第一幀比要求的時間早約 0.48 秒（x86 Metal 測試程式在固定時間點停頓，5 秒與 30 秒報告中
# 停頓幀與實際停頓的差距中位數 477–495 ms、MAD 4 ms，報告內不漂移）
REPORT_LEAD_US = 480_000
REPORT_METRICS = (
    "FPS",
    "Frame Interval",
    "Present Delay",
    "Command Buffer CPU",
    "Command Buffer GPU",
)


# ---------- 讀取 ----------


class Capture:
    """machsample 的輸出（格式見 machsample.c 開頭）。"""

    def __init__(self, path: Path) -> None:
        self.pid = 0
        self.interval_us = 0
        self.start = self.end = 0
        self.images: list[tuple[int, int, str]] = []
        self.regions: dict[int, tuple[int, int, str]] = {}
        self.proc_names: dict[int, str] = {}
        self.proc_cpu: dict[int, list[tuple[int, int]]] = collections.defaultdict(list)
        self.counters: list[tuple[int, dict[str, int]]] = []
        self.threads: dict[int, list[tuple[int, int, int, int]]] = collections.defaultdict(list)
        self.thread_names: dict[int, str] = {}
        self.stacks: list[tuple[int, int, str, int, list[int], list[int]]] = []
        self.stats = ""
        with path.open(errors="replace") as f:
            for line in f:
                self._parse(line.split())
        if not self.end:  # 沒有 E（machsample 被強制結束）：以最後一次取樣為結束
            self.end = max(
                [s[0] for s in self.stacks[-1:]] + [c[0] for c in self.counters[-1:]] + [0]
            )

    def _parse(self, p: list[str]) -> None:
        if not p:
            return
        kind = p[0]
        try:
            if kind == "S" and len(p) >= 6:
                native = [int(a, 16) for a in p[5].split(",")]
                x86 = [] if len(p) < 7 or p[6] == "-" else [int(a, 16) for a in p[6].split(",")]
                self.stacks.append((int(p[1]), int(p[2]), p[3], int(p[4]), native, x86))
            elif kind == "T" and len(p) >= 7:
                tid = int(p[2])
                self.threads[tid].append((int(p[1]), int(p[3]), int(p[4]), int(p[5])))
                if p[6] != "-":
                    self.thread_names[tid] = p[6]
            elif kind == "C" and len(p) >= 10:
                names = (
                    "faults",
                    "pageins",
                    "cow",
                    "csw",
                    "mach",
                    "unix",
                    "sent",
                    "recv",
                    "running",
                )
                values = (int(v) % 2**32 for v in p[2:11])  # pti_* 是 int32，取無號值
                self.counters.append((int(p[1]), dict(zip(names, values))))
            elif kind == "P" and len(p) >= 4:
                self.proc_cpu[int(p[2])].append((int(p[1]), int(p[3])))
            elif kind == "M" and len(p) >= 5:
                start = int(p[1], 16)
                self.regions[start] = (int(p[2], 16), int(p[3]), " ".join(p[4:]))
            elif kind == "D" and len(p) >= 4:
                self.images.append((int(p[1], 16), int(p[2], 16), " ".join(p[3:])))
            elif kind == "N" and len(p) >= 3:
                self.proc_names[int(p[1])] = " ".join(p[2:])
            elif kind == "H" and len(p) >= 4:
                self.pid, self.interval_us, self.start = int(p[1]), int(p[2]), int(p[3])
            elif kind == "E" and len(p) >= 6:
                self.end = int(p[1])
                self.stats = (
                    f"取樣 {p[2]} 次、落後 {p[3]} 次、每次平均 {int(p[4]) / 1000:.2f} ms"
                    f"（最長 {int(p[5]) / 1000:.1f} ms）"
                )
        except ValueError:
            pass  # 被截斷的行（例如中途結束）


class Frame:
    __slots__ = ("end", "interval", "start")

    def __init__(self, start: int, interval_ms: float) -> None:
        self.start = start
        self.end = start + int(interval_ms * 1000)
        self.interval = interval_ms


def parse_report(path: Path, start_us: int) -> tuple[list[Frame], list[str]]:
    """Metal HUD 效能報告（HUD 選單的 Generate Performance Report，或 Darwin notification
    `com.apple.metal.hud.notify.PerformanceReport-<秒數>s`）：HTML 內的 JSON `{"frameintervals": [ns, ...]}`
    依序列出報告期間每一幀的間隔，沒有時間戳；從要求產生報告的時間減 REPORT_LEAD_US 往後累加即得
    各幀時間（誤差約數 ms）。
    另回傳報告「Metrics」表中幾項整段統計（平均／最後／最小／最大）。"""
    text = path.read_text(errors="replace")
    m = REPORT_JSON.search(text)
    if not m:
        return [], []
    frames, t = [], start_us - REPORT_LEAD_US
    for ns in json.loads(m[1]).get("frameintervals", []):
        frame = Frame(t, ns / 1e6)
        frames.append(frame)
        t = frame.end
    metrics = []
    for row in REPORT_ROW.finditer(text):
        if row[1].strip() in REPORT_METRICS:
            cells = re.findall(r"<td[^>]*>([^<]*)</td>", row[2])
            metrics.append(f"{row[1].strip()}：" + " / ".join(c.strip() for c in cells))
    return frames, list(dict.fromkeys(metrics))


# ---------- 符號 ----------


def syscall_names() -> dict[int, str]:
    names = dict(MACH_TRAPS)
    try:
        sdk = subprocess.run(
            ["xcrun", "--show-sdk-path"], capture_output=True, text=True, check=True
        ).stdout.strip()
        header = Path(sdk, "usr/include/sys/syscall.h").read_text()
    except (OSError, subprocess.CalledProcessError):
        return names
    for name, number in re.findall(r"#define\s+SYS_(\w+)\s+(\d+)", header):
        names.setdefault(int(number), name)
    return names


def pe_size_of_image(path: str) -> int:
    """PE 標頭的 SizeOfImage（只讀檔案開頭）；不是 PE 時回傳 0。"""
    try:
        with Path(path).open("rb") as f:
            head = f.read(4096)
    except OSError:
        return 0
    if head[:2] != b"MZ" or len(head) < 0x40:
        return 0
    pe = int.from_bytes(head[0x3C:0x40], "little")
    if head[pe : pe + 4] != b"PE\0\0" or len(head) < pe + 24 + 60:
        return 0
    return int.from_bytes(head[pe + 24 + 56 : pe + 24 + 60], "little")


class Symbols:
    """位址 → 顯示名稱。x86 位址解析到函式（或模組+偏移），原生 arm64 位址歸類到 Rosetta 的狀態。"""

    def __init__(self, cap: Capture) -> None:
        self.regions = sorted((s, e, prot, path) for s, (e, prot, path) in cap.regions.items())
        self.region_starts = [r[0] for r in self.regions]
        self.images = sorted((load, load + size, path) for load, size, path in cap.images if size)
        self.image_starts = [i[0] for i in self.images]
        lowest: dict[str, int] = {}
        highest: dict[str, int] = {}
        for start, end, _prot, path in self.regions:
            if path.lower().endswith(PE_SUFFIXES):
                lowest[path] = min(start, lowest.get(path, start))
                highest[path] = max(end, highest.get(path, end))
        self.modules = []
        for path, start in lowest.items():
            base = start & pesym.IMAGE_ALIGNMENT_MASK
            self.modules.append(
                (base, base + (pe_size_of_image(path) or highest[path] - base), path)
            )
        self.modules.sort()
        self.module_starts = [m[0] for m in self.modules]
        self.cache: dict[int, str] = {}
        self.native_cache: dict[int, str] = {}

    @staticmethod
    def _find(starts: list[int], items: list, address: int):
        i = bisect.bisect_right(starts, address) - 1
        return items[i] if i >= 0 and address < items[i][1] else None

    def region(self, address: int):
        return self._find(self.region_starts, self.regions, address)

    def resolve(self, addresses: set[int]) -> None:
        """批次解析 x86 位址，結果存在 cache（label() 讀取）。"""
        shared, on_disk, pe = set(), collections.defaultdict(set), collections.defaultdict(set)
        for a in addresses:
            image = self._find(self.image_starts, self.images, a)
            module = self._find(self.module_starts, self.modules, a)
            if image:
                disk = self._image_file(image[2], a)
                if disk:
                    on_disk[(disk, image[0])].add(a)
                else:
                    shared.add(a)
                self.cache[a] = f"{Path(image[2]).name}+{a - image[0]:#x}"
            elif module:
                pe[module].add(a)
                self.cache[a] = f"{Path(module[2]).name}+{a - module[0]:#x}"
            else:
                region = self.region(a)
                if region and region[3] != "-":
                    self.cache[a] = f"{Path(region[3]).name}+{a - region[0]:#x}"
                else:
                    self.cache[a] = f"匿名程式碼@{region[0]:#x}" if region else f"{a:#x}"
        if shared:
            self.cache.update(_quiet(symbolize.symbolize_shared_cache, shared))
        for (image, load), group in on_disk.items():
            for a, name in _quiet(symbolize.symbolize_on_disk, image, load, group).items():
                self.cache[a] = ATOS_IN.sub("", name)  # atos：「函式 (in 檔名) + 偏移」
        if pe and (pesym.LLVM_BIN / "llvm-symbolizer").exists():
            for (base, _end, path), group in pe.items():
                self.cache.update(_quiet(self._symbolize_pe, path, base, sorted(group)))

    def _image_file(self, path: str, address: int) -> str | None:
        """映像在磁碟上的檔案；shared cache 內的映像沒有檔案。dyld 記錄的路徑可能是相對路徑，改用區段的路徑。"""
        if path.startswith("/") and Path(path).exists():
            return path
        region = self.region(address)
        if region and Path(region[3]).name == Path(path).name and Path(region[3]).exists():
            return region[3]
        return None

    @staticmethod
    def _symbolize_pe(path: str, base: int, addresses: list[int]) -> dict[int, str]:
        image_base = pesym.image_base(path)
        names = pesym.symbolize(path, [a - base + image_base for a in addresses])
        name = Path(path).name
        return {a: f"{name}!{n}" for a, n in zip(addresses, names) if n != "?"}

    def label(self, address: int) -> str:
        return self.cache.get(address, f"{address:#x}")

    def function(self, address: int) -> str:
        """統計用：有符號時去掉 +偏移（同一函式合併），沒有符號時保留模組+偏移（同一呼叫點）。"""
        text = self.label(address)
        if "`" in text or "!" in text:
            return SYMBOL_SUFFIX.sub("", text)
        return text

    def native(self, address: int) -> str:
        """原生 arm64 位址的歸類（Rosetta 程序裡只有 Rosetta 本身是原生碼）。"""
        if address in self.native_cache:
            return self.native_cache[address]
        image = self._find(self.image_starts, self.images, address)
        region = self.region(address)
        if image and ("rosetta" in image[2].lower() or "/oah/" in image[2]):
            kind = "Rosetta 執行環境"
        elif region and region[3].endswith(".aot"):
            kind = "AOT 翻譯碼"
        elif region and region[3] == "-":
            kind = "JIT 翻譯碼"
        elif SHARED_CACHE[0] <= address < SHARED_CACHE[1]:
            kind = "系統函式庫翻譯碼"
        else:
            kind = "其他原生碼"
        self.native_cache[address] = kind
        return kind


def _quiet(function, *args) -> dict[int, str]:
    """外部符號工具失敗時只略過該批位址。"""
    try:
        return function(*args)
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"hitchprof: 符號解析失敗，略過：{error}", file=sys.stderr)
        return {}


# ---------- 分析 ----------


def step_value(points: list[tuple], t: int) -> int:
    """累計值（只在改變時記錄）在 t 時的值。"""
    i = bisect.bisect_right(points, (t, float("inf"))) - 1
    return points[i][1] if i >= 0 else points[0][1] if points else 0


def pct(part: float, whole: float) -> str:
    return f"{100 * part / whole:5.1f}%" if whole else "    -"


class Analysis:
    def __init__(
        self, cap: Capture, frames: list[Frame], metrics: list[str], args: argparse.Namespace
    ) -> None:
        self.cap, self.args = cap, args
        self.sym = Symbols(cap)
        self.syscalls = syscall_names()
        self.frames = [f for f in frames if f.start >= cap.start and f.end <= cap.end]
        self.metrics = metrics
        intervals = [f.interval for f in self.frames]
        self.median = statistics.median(intervals) if intervals else 0
        self.threshold = args.threshold_ms or max(3 * self.median, self.median + 25)
        lead = (args.lead_ms if args.lead_ms is not None else 2 * self.median) * 1000
        self.events = self._events(int(lead))
        self.windows = [(e["start"], e["end"]) for e in self.events]
        self.window_starts = [w[0] for w in self.windows]
        self.frame_starts = [f.start for f in self.frames]

    def _events(self, lead: int) -> list[dict]:
        events: list[dict] = []
        for frame in self.frames:
            if frame.interval < self.threshold:
                continue
            if events and frame.start - events[-1]["end"] <= 2 * self.median * 1000:
                events[-1]["end"] = frame.end
                events[-1]["frames"].append(frame)
                continue
            events.append(
                {
                    "start": max(frame.start - lead, self.cap.start),
                    "end": frame.end,
                    "frames": [frame],
                }
            )
        return events

    def phase(self, t: int) -> int | None:
        """取樣時間 → 卡頓事件編號；平常為 -1；不在 HUD 涵蓋範圍內為 None。"""
        i = bisect.bisect_right(self.window_starts, t) - 1
        if i >= 0 and t < self.windows[i][1]:
            return i
        j = bisect.bisect_right(self.frame_starts, t) - 1
        return -1 if j >= 0 and t < self.frames[j].end else None

    # --- 數值 ---

    def hitch_time(self) -> int:
        return sum(e - s for s, e in self.windows)

    def normal_time(self) -> int:
        return sum(f.end - f.start for f in self.frames) - self.hitch_time()

    def deltas(
        self, series: dict[int, list[tuple]], windows: list[tuple[int, int]]
    ) -> dict[int, int]:
        out: dict[int, int] = {}
        for key, points in series.items():
            used = sum(step_value(points, e) - step_value(points, s) for s, e in windows)
            if used > 0:
                out[key] = used
        return out

    def totals(self, series: dict[int, list[tuple]]) -> dict[int, int]:
        return self.deltas(series, [(self.cap.start, self.cap.end)])

    def counter_rates(self, windows: list[tuple[int, int]]) -> dict[str, float]:
        points = self.cap.counters
        times = [p[0] for p in points]
        total = collections.Counter()
        duration = 0
        for s, e in windows:
            i, j = bisect.bisect_left(times, s), bisect.bisect_right(times, e) - 1
            if j <= i:
                continue
            duration += points[j][0] - points[i][0]
            for key, _ in COUNTERS:
                total[key] += (points[j][1][key] - points[i][1][key]) % 2**32
        return {k: total[k] * 1e6 / duration for k, _ in COUNTERS} if duration else {}

    def thread_label(self, tid: int) -> str:
        name = self.cap.thread_names.get(tid)
        return f"tid {tid}" + (f"（{name}）" if name else "")

    def proc_label(self, pid: int) -> str:
        return f"{self.cap.proc_names.get(pid, '?')}（pid {pid}）"

    # --- 堆疊 ---

    def state(self, stack: tuple) -> str:
        _t, _tid, mode, x16, native, _x86 = stack
        if mode == "s":
            return f"系統呼叫 {self.syscalls.get(x16, x16)}"
        return self.sym.native(native[0])

    def chain(self, stack: tuple) -> list[str]:
        out: list[str] = []
        for a in stack[5][:X86_FRAMES]:
            name = self.sym.function(a)
            if not out or out[-1] != name:
                out.append(name)
        return out

    def signature(self, stack: tuple) -> str:
        chain = self.chain(stack)[:SIGNATURE_FRAMES]
        return f"[{self.state(stack)}] " + (" <- ".join(chain) if chain else "（沒有 x86 堆疊）")


# ---------- 報告 ----------


def report(cap: Capture, frames: list[Frame], metrics: list[str], args: argparse.Namespace) -> None:
    an = Analysis(cap, frames, metrics, args)
    top = args.top
    print(f"目標 pid {cap.pid}，擷取 {(cap.end - cap.start) / 1e6:.1f} 秒；{cap.stats}")

    by_phase: dict[int, list[tuple]] = collections.defaultdict(list)
    for stack in cap.stacks:
        p = an.phase(stack[0])
        if p is not None:
            by_phase[p].append(stack)
    wanted = {a for stacks in by_phase.values() for s in stacks for a in s[5][:X86_FRAMES]}
    if not an.frames:
        wanted = {a for s in cap.stacks for a in s[5][:X86_FRAMES]}
    an.sym.resolve(wanted)

    if not an.frames:
        print(
            "\n沒有這個程序在擷取期間的 Metal HUD 幀資料，無法判斷哪些時間點卡頓；以下只是整段擷取的統計。"
        )
        print(
            "請確認報告是這個程序的、且 --start-us 是要求產生報告的時間（見 stack.sh hitch 的說明）。"
        )
        whole_capture(an, top)
        return

    print_frames(an)
    if not an.events:
        print("\n擷取期間沒有超過門檻的幀。可延長擷取時間，或以 --threshold-ms 降低門檻。")
        return
    cmp = Comparison(an, by_phase)
    print_highlights(an, cmp)
    print_compare(an, cmp, top)
    print_events(an, cmp, by_phase, top)


def print_frames(an: Analysis) -> None:
    intervals = sorted(f.interval for f in an.frames)
    p99 = intervals[min(len(intervals) - 1, int(len(intervals) * 0.99))]
    print("\n== 幀時間（Metal HUD 效能報告）")
    print(
        f"{len(intervals)} 幀；中位數 {an.median:.2f} ms（約 {1000 / an.median:.0f} FPS）、"
        f"p99 {p99:.2f} ms、最長 {intervals[-1]:.2f} ms"
    )
    hitch_frames = [f for e in an.events for f in e["frames"]]
    total = sum(f.interval for f in hitch_frames)
    print(
        f"卡頓門檻 {an.threshold:.1f} ms：{len(hitch_frames)} 幀、合併為 {len(an.events)} 次卡頓，"
        f"共 {total / 1000:.2f} 秒"
    )
    if an.metrics:
        print("HUD 整段統計（平均 / 最後 / 最小 / 最大）：")
        for line in an.metrics:
            print(f"  {line}")


class Comparison:
    """所有卡頓合計 vs 平常。每列為 (增加量, 卡頓值, 平常值, 鍵)，依增加量由大到小排序。"""

    def __init__(self, an: Analysis, by_phase: dict[int, list[tuple]]) -> None:
        self.an = an
        cap, windows = an.cap, an.windows
        self.hitch_time, self.normal_time = an.hitch_time(), max(an.normal_time(), 1)
        self.threads = self._cpu_rows(cap.threads)
        self.procs = self._cpu_rows(cap.proc_cpu)
        hitch = an.counter_rates(windows)
        normal = an.counter_rates(
            [(f.start, f.end) for f in an.frames if f.interval < an.threshold]
        )
        self.counters = [
            (hitch[k] / normal[k] if normal.get(k) else 0, hitch[k], normal[k], name)
            for k, name in COUNTERS
            if k in hitch and k in normal
        ]
        # 主執行緒（推定）：整段擷取 CPU 最多的執行緒
        totals = an.totals(cap.threads)
        self.main = max(totals, key=totals.get) if totals else None
        hitch_stacks = [s for i, stacks in by_phase.items() if i >= 0 for s in stacks]
        normal_stacks = by_phase.get(-1, [])
        by_thread_h, by_thread_n = collections.defaultdict(list), collections.defaultdict(list)
        for st in hitch_stacks:
            by_thread_h[st[1]].append(st)
        for st in normal_stacks:
            by_thread_n[st[1]].append(st)
        # 各執行緒卡頓 vs 平常的狀態分布差異（總變異距離 0–1）：卡頓時改做別的事或停在等待的執行緒
        self.shift = {}
        for tid, hs in by_thread_h.items():
            ns = by_thread_n.get(tid, [])
            if len(hs) >= 5 and ns:
                rows = count_rows(
                    [an.state(x) for x in hs], [an.state(x) for x in ns], len(hs), len(ns)
                )
                self.shift[tid] = sum(abs(r[0]) for r in rows) / 2
        focus = [self.main] if self.main in by_thread_h else []
        # 卡頓時 CPU 明顯增加的執行緒
        focus += [r[3] for r in self.threads if r[0] >= 0.05 and r[3] in by_thread_h][:2]
        # 卡頓時狀態改變最多的執行緒（例如平常在跑、卡頓時停在系統呼叫；CPU 不多也找得到）
        focus += [
            t for t in sorted(self.shift, key=lambda t: -self.shift[t]) if self.shift[t] >= 0.3
        ][:2]
        self.focus = list(dict.fromkeys(focus))
        self.per_thread = {}
        for tid in self.focus:
            hs, ns = by_thread_h[tid], by_thread_n.get(tid, [])
            states = count_rows(
                [an.state(x) for x in hs], [an.state(x) for x in ns], len(hs), len(ns)
            )
            chains = count_rows(
                [f for x in hs for f in set(an.chain(x))],
                [f for x in ns for f in set(an.chain(x))],
                len(hs),
                len(ns),
            )
            self.per_thread[tid] = (len(hs), len(ns), states, chains)

    def _cpu_rows(self, series: dict) -> list[tuple]:
        hitch, total = self.an.deltas(series, self.an.windows), self.an.totals(series)
        rows = []
        for key in set(hitch) | set(total):
            h = hitch.get(key, 0) / self.hitch_time
            n = max(total.get(key, 0) - hitch.get(key, 0), 0) / self.normal_time
            if h >= 0.01 or n >= 0.01:
                rows.append((h - n, h, n, key))
        return sorted(rows, key=lambda r: -r[0])


def count_rows(hitch: list[str], normal: list[str], nh: int, nn: int) -> list[tuple]:
    """各鍵在卡頓／平常取樣中出現的比例。"""
    ch, cn = collections.Counter(hitch), collections.Counter(normal)
    rows = []
    for key in set(ch) | set(cn):
        h, n = (ch[key] / nh if nh else 0), (cn[key] / nn if nn else 0)
        rows.append((h - n, h, n, key))
    return sorted(rows, key=lambda r: -r[0])


def print_highlights(an: Analysis, cmp: Comparison) -> None:
    """各表增加最多的項目。門檻是經驗值，只用來挑出值得先看的地方。"""
    lines = []
    main = cmp.main
    for diff, h, n, tid in cmp.threads[:2]:
        if diff >= 0.05:
            lines.append(
                f"CPU 增加：{an.thread_label(tid)} 平常 {100 * n:.0f}% → 卡頓 {100 * h:.0f}%"
            )
    main_row = next((r for r in cmp.threads if r[3] == main), None)
    if main_row and main_row[1] < 0.5 * main_row[2]:
        lines.append(
            f"主執行緒（推定 {an.thread_label(main)}）卡頓時 CPU 反而較少"
            f"（{100 * main_row[2]:.0f}% → {100 * main_row[1]:.0f}%）：多半在等待，看它的「狀態」"
        )
    for diff, h, n, pid in cmp.procs[:2]:
        if diff >= 0.1:
            lines.append(
                f"其他程序 CPU 增加：{an.proc_label(pid)} 平常 {100 * n:.0f}% → 卡頓 {100 * h:.0f}%"
            )
    for ratio, h, n, name in cmp.counters:
        if ratio >= 2 and h >= 1000:
            lines.append(f"{name} 卡頓時每秒 {h:.0f} 次，為平常的 {ratio:.1f} 倍")
    for tid in cmp.focus:
        _nh, _nn, states, chains = cmp.per_thread[tid]
        who = "主執行緒" if tid == main else an.thread_label(tid)
        for diff, h, n, key in states[:1]:
            if diff >= 0.1:
                lines.append(f"{who} 狀態：{key} 平常 {100 * n:.0f}% → 卡頓 {100 * h:.0f}%")
        for diff, h, n, key in chains[:3]:
            if diff >= 0.1:
                lines.append(f"{who} 呼叫鏈：{key} 平常 {100 * n:.0f}% → 卡頓 {100 * h:.0f}%")
    print("\n== 重點（卡頓期間明顯比平常多的項目；是相關性，不一定是原因）")
    for line in lines or ["沒有明顯比平常多的項目；看下方各次卡頓的呼叫鏈"]:
        print(f"- {line}")


def print_compare(an: Analysis, cmp: Comparison, top: int) -> None:
    print("\n== 卡頓期間 vs 平常（所有卡頓合計；CPU 以單一核心 = 100%；依增加量排序）")

    def table(title: str, rows: list[tuple], label, unit: str = "%") -> None:
        print(f"\n{title}：")
        for diff, h, n, key in rows[:top]:
            if unit == "%":
                print(
                    f"  卡頓 {100 * h:6.1f}%  平常 {100 * n:6.1f}%  {100 * diff:+6.1f}  {label(key)}"
                )
            else:
                print(f"  卡頓 {h:9.0f}  平常 {n:9.0f}  ×{diff:<5.1f} {label(key)}")

    table("目標程序的執行緒 CPU", cmp.threads, an.thread_label)
    table("其他程序 CPU", cmp.procs, an.proc_label)
    table("目標程序計數（每秒）", cmp.counters, str, unit="/s")
    for tid in cmp.focus:
        nh, nn, states, chains = cmp.per_thread[tid]
        tag = "（主執行緒，推定）" if tid == cmp.main else ""
        tag += f"；狀態變化 {cmp.shift.get(tid, 0):.2f}"
        print(f"\n{an.thread_label(tid)}{tag}：卡頓取樣 {nh} 次、平常取樣 {nn} 次")
        table("  狀態（取樣比例）", [r for r in states if r[1] or r[2] >= 0.01], str)
        table("  呼叫鏈中的函式（含呼叫者；取樣比例）", [r for r in chains if r[1]], str)


def print_events(an: Analysis, cmp: Comparison, by_phase: dict[int, list[tuple]], top: int) -> None:
    print("\n== 各次卡頓（最長的在前）")
    order = sorted(
        range(len(an.events)),
        key=lambda i: an.events[i]["end"] - an.events[i]["start"],
        reverse=True,
    )
    for rank, i in enumerate(order[:top], 1):
        event = an.events[i]
        window = [(event["start"], event["end"])]
        frames = event["frames"]
        when = (
            datetime.fromtimestamp(frames[0].start / 1e6, timezone.utc)
            .astimezone()
            .strftime("%H:%M:%S.%f")[:-3]
        )
        stacks = by_phase.get(i, [])
        duration = (event["end"] - event["start"]) / 1000
        print(
            f"\n#{rank} {when}  {sum(f.interval for f in frames):.1f} ms（{len(frames)} 幀，最長 "
            f"{max(f.interval for f in frames):.1f} ms）；分析區間 {duration:.0f} ms、取樣 {len(stacks)} 次"
        )
        busy = sorted(an.deltas(an.cap.threads, window).items(), key=lambda kv: -kv[1])[:4]
        others = sorted(an.deltas(an.cap.proc_cpu, window).items(), key=lambda kv: -kv[1])[:3]
        print(
            "  CPU："
            + "、".join(f"{an.thread_label(t)} {us / 1000:.0f} ms" for t, us in busy)
            + (
                "；其他程序："
                + "、".join(f"{an.proc_label(p)} {us / 1000:.0f} ms" for p, us in others)
                if others
                else ""
            )
        )
        # 重點執行緒，以及這次卡頓中 CPU 最多的其他執行緒
        shown = list(dict.fromkeys([*cmp.focus, *(t for t, _ in busy)]))
        for tid in [t for t in shown if any(s[1] == t for s in stacks)][:3]:
            sigs = collections.Counter(an.signature(s) for s in stacks if s[1] == tid)
            tag = "（主執行緒）" if tid == cmp.main else ""
            print(f"  {an.thread_label(tid)}{tag} {sum(sigs.values())} 次取樣，最常見的呼叫鏈：")
            for sig, n in sigs.most_common(3):
                print(f"    {n:3d}× {sig}")


def whole_capture(an: Analysis, top: int) -> None:
    cap = an.cap
    duration = max(cap.end - cap.start, 1)
    print("\n執行緒 CPU：")
    for tid, us in sorted(an.totals(cap.threads).items(), key=lambda kv: -kv[1])[:top]:
        print(f"  {100 * us / duration:6.1f}%  {an.thread_label(tid)}")
    print("\n其他程序 CPU：")
    for pid, us in sorted(an.totals(cap.proc_cpu).items(), key=lambda kv: -kv[1])[:top]:
        print(f"  {100 * us / duration:6.1f}%  {an.proc_label(pid)}")
    for tid, count in collections.Counter(s[1] for s in cap.stacks).most_common(3):
        print(f"\n{an.thread_label(tid)}（{count} 次取樣）最常見的呼叫鏈：")
        sigs = collections.Counter(an.signature(s) for s in cap.stacks if s[1] == tid)
        for sig, n in sigs.most_common(top):
            print(f"  {n:4d}× {sig}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("samples", type=Path)
    parser.add_argument("report", type=Path)
    parser.add_argument("--start-us", type=int, required=True)
    parser.add_argument("--threshold-ms", type=float)
    parser.add_argument("--lead-ms", type=float)
    parser.add_argument("--top", type=int, default=12)
    args = parser.parse_args()
    cap = Capture(args.samples)
    if not cap.pid:
        sys.exit(f"{args.samples} 不是 machsample 的輸出")
    frames, metrics = parse_report(args.report, args.start_us) if args.report.exists() else ([], [])
    report(cap, frames, metrics, args)


if __name__ == "__main__":
    main()
