#!/usr/bin/env python3
"""machstack 輸出後處理：替 x86 位址補上符號。

- dyld shared cache 內的系統函式庫：交給 symx86（Rosetta 下 dladdr，同一 slide）
- 磁碟上的 Mach-O（wine、ntdll.so、win32u.so…）：atos -arch x86_64 -l <load>

用法：symbolize.py machstack-output.txt
symx86 位置：環境變數 SYMX86，預設 build/tools/symx86。
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
SYMX86 = os.environ.get("SYMX86") or str(REPO_ROOT / "build" / "tools" / "symx86")

# machstack 的 frame 行：0x<16 位位址> ... [img <路徑> load=0x<載入位址> off=0x<偏移>]
FRAME = re.compile(r"0x([0-9a-f]{16}).*\[img (\S+) load=0x([0-9a-f]+) off=0x([0-9a-f]+)\]")


def run(command: list[str], stdin: str | None = None) -> str:
    return subprocess.run(command, input=stdin, capture_output=True, text=True, check=True).stdout


def collect_addresses(lines: list[str]) -> tuple[set[int], dict[tuple[str, int], set[int]]]:
    """把 frame 位址分成 shared cache 內的位址，與依 (Mach-O 路徑, 載入位址) 分組的磁碟映像位址。"""
    in_shared_cache: set[int] = set()
    on_disk: dict[tuple[str, int], set[int]] = {}
    for line in lines:
        frame = FRAME.search(line)
        if not frame:
            continue
        address, image, load = int(frame[1], 16), frame[2], int(frame[3], 16)
        if Path(image).exists():
            on_disk.setdefault((image, load), set()).add(address)
        else:
            in_shared_cache.add(address)
    return in_shared_cache, on_disk


def symbolize_shared_cache(addresses: set[int]) -> dict[int, str]:
    """symx86 每行輸入一個十六進位位址，輸出「位址 符號」（查不到時符號為 ?）。"""
    stdin = "".join(f"{address:x}\n" for address in sorted(addresses))
    symbols = {}
    for line in run(["arch", "-x86_64", SYMX86], stdin).splitlines():
        address, _, symbol = line.partition(" ")
        if symbol != "?":
            symbols[int(address, 16)] = symbol
    return symbols


def symbolize_on_disk(image: str, load: int, addresses: set[int]) -> dict[int, str]:
    """atos 依輸入順序每個位址輸出一行；查不到時原樣輸出位址。

    單一映像失敗（例如不是 x86_64 Mach-O）只略過該映像，其餘位址照常補符號。
    """
    ordered = sorted(addresses)
    command = ["atos", "-arch", "x86_64", "-o", image, "-l", hex(load), *map(hex, ordered)]
    try:
        output = run(command)
    except subprocess.CalledProcessError as error:
        print(f"symbolize: 略過 {image}：{error.stderr.strip()}", file=sys.stderr)
        return {}
    name = Path(image).name
    return {
        address: f"{name}`{symbol}"
        for address, symbol in zip(ordered, output.splitlines())
        if not symbol.startswith("0x")
    }


def main(path: Path) -> None:
    lines = path.read_text(errors="replace").splitlines()
    in_shared_cache, on_disk = collect_addresses(lines)

    symbols: dict[int, str] = {}
    if in_shared_cache:
        symbols.update(symbolize_shared_cache(in_shared_cache))
    for (image, load), addresses in on_disk.items():
        symbols.update(symbolize_on_disk(image, load, addresses))

    for line in lines:
        frame = FRAME.search(line)
        symbol = symbols.get(int(frame[1], 16)) if frame else None
        print(f"{line[: line.index('[img')]}{{{symbol}}}" if symbol else line)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
