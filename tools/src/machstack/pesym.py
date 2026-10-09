#!/usr/bin/env python3
"""Wine PE DLL 位址 → 函式名。

用法：pesym.py <vmmap 區段檔（每行：起點 路徑）> addr...

以每個 DLL 檔案的最低映射位址當作 image base，搭配 COFF 符號表（section 相對）求最近符號。
LLVM 工具位置：環境變數 LLVM_BIN，預設 /opt/homebrew/opt/llvm/bin。
"""

from __future__ import annotations

import bisect
import functools
import os
import re
import subprocess
import sys
from pathlib import Path

LLVM_BIN = Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin"))

SECTION_HEADER = re.compile(r"\s*(\d+)\s+(\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)")
COFF_SYMBOL = re.compile(r"\(sec\s+(\d+)\).*?(0x[0-9a-f]+) (\S+)$")
IMAGE_BASE = re.compile(r"ImageBase: (0x[0-9A-Fa-f]+)")
IMAGE_ALIGNMENT_MASK = ~0xFFFF  # Wine 以 64K 對齊載入 PE 映像


def llvm(tool: str, *args: str) -> str:
    return subprocess.run(
        [str(LLVM_BIN / tool), *args], capture_output=True, text=True, check=True
    ).stdout


def load_regions(vmmap_file: Path) -> list[tuple[int, str]]:
    """回傳依位址排序的 (最低映射位址, DLL 路徑)。"""
    lowest: dict[str, int] = {}
    for line in vmmap_file.read_text().splitlines():
        if not line.strip():
            continue
        start_hex, path = line.split(None, 1)
        path = path.strip()
        start = int(start_hex, 16)
        lowest[path] = min(start, lowest.get(path, start))
    return sorted((start, path) for path, start in lowest.items())


@functools.cache
def symbols(dll: str) -> list[tuple[int, str]]:
    """回傳依 VA 排序的 (VA, 符號名稱)。"""
    # COFF 符號表的 section 編號從 1 起算，objdump -h 的 Idx 從 0 起算
    section_va: dict[int, int] = {}
    for line in llvm("llvm-objdump", "-h", dll).splitlines():
        section = SECTION_HEADER.match(line)
        if section:
            section_va[int(section[1]) + 1] = int(section[4], 16)
    found = []
    for line in llvm("llvm-objdump", "--syms", dll).splitlines():
        symbol = COFF_SYMBOL.search(line)
        if symbol and int(symbol[1]) in section_va:
            found.append((section_va[int(symbol[1])] + int(symbol[2], 16), symbol[3]))
    return sorted(found)


@functools.cache
def image_base(dll: str) -> int:
    match = IMAGE_BASE.search(llvm("llvm-readobj", "--file-headers", dll))
    if not match:
        raise ValueError(f"找不到 ImageBase：{dll}")
    return int(match[1], 16)


def resolve(regions: list[tuple[int, str]], address: int) -> str:
    index = bisect.bisect_right(regions, (address, chr(0x10FFFF))) - 1
    if index < 0:
        return "?"
    lowest_mapping, dll = regions[index]
    # 實際載入 base = 最低映射位址向下取 64K；換算成 PE 檔內的 VA 再查符號
    va = address - (lowest_mapping & IMAGE_ALIGNMENT_MASK) + image_base(dll)
    table = symbols(dll)
    nearest = bisect.bisect_right(table, (va, chr(0x10FFFF))) - 1
    name = f"{table[nearest][1]}+{va - table[nearest][0]:#x}" if nearest >= 0 else "?"
    return f"{Path(dll).name}!{name}"


def main(argv: list[str]) -> None:
    if len(argv) < 3:
        sys.exit(__doc__)
    regions = load_regions(Path(argv[1]))
    for address in argv[2:]:
        print(address, resolve(regions, int(address, 16)))


if __name__ == "__main__":
    main(sys.argv)
