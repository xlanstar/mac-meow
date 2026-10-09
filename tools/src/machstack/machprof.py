#!/usr/bin/env python3
"""machprof：彙整多次 machstack 快照（已經 symbolize.py 處理），列出各執行緒的 CPU 時間增量與最常見的呼叫鏈。

用法：machprof.py <symbolized.txt>
"""

from __future__ import annotations

import collections
import re
import sys
from pathlib import Path

THREAD_HEADER = re.compile(r"tid=(\d+) name='([^']*)'.*user=([\d.]+)s sys=([\d.]+)s")
SYSCALL_NUMBER = re.compile(r"x16=(-?\d+)")
SYMBOLIZED_FRAME = re.compile(r"\{([^}]*)\}")

MIN_CPU_DELTA_SECONDS = 0.05  # 忽略幾乎沒吃 CPU 的執行緒
TOP_STACKS = 4  # 每個執行緒列出幾種最常見的呼叫鏈
FRAMES_PER_STACK = 5
MAX_STACK_CHARS = 300


def stack_key(block: str) -> str:
    """把一個執行緒快照歸納成「狀態 | 前幾層符號」的字串，用來計數相同的呼叫鏈。"""
    if "(syscall)" in block:
        number = SYSCALL_NUMBER.search(block)
        state = f"syscall={number[1] if number else '?'}"
    else:
        state = "running/other"
    frames = SYMBOLIZED_FRAME.findall(block.split("x86 stack scan")[0])
    symbols = (frame.split(" (in ")[0] for frame in frames[:FRAMES_PER_STACK])
    return f"{state} | " + " <- ".join(symbols)


def main(path: Path) -> None:
    blocks = path.read_text(errors="replace").split("=== thread[")
    first_cpu: dict[str, float] = {}
    last_seen: dict[str, tuple[float, str]] = {}
    stacks: dict[str, collections.Counter[str]] = collections.defaultdict(collections.Counter)

    for block in blocks[1:]:
        header = THREAD_HEADER.search(block)
        if not header:
            continue
        tid, name = header[1], header[2]
        cpu = float(header[3]) + float(header[4])
        first_cpu.setdefault(tid, cpu)
        last_seen[tid] = (cpu, name)
        stacks[tid][stack_key(block)] += 1

    def cpu_delta(tid: str) -> float:
        return last_seen[tid][0] - first_cpu[tid]

    for tid in sorted(last_seen, key=cpu_delta, reverse=True):
        delta = cpu_delta(tid)
        if delta < MIN_CPU_DELTA_SECONDS:
            continue
        print(f"\n### tid={tid} name={last_seen[tid][1]} cpu_delta={delta:.2f}s")
        for key, count in stacks[tid].most_common(TOP_STACKS):
            print(f"  {count:2d}× {key[:MAX_STACK_CHARS]}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]))
