#!/usr/bin/env python3
"""Wine PE DLL 位址 → 函式名。

用法：pesym.py <vmmap 區段檔（每行：起點 路徑）> addr...

以每個 DLL 檔案的最低映射位址當作載入 base，換算成 PE 檔內的 VA 後交給 llvm-symbolizer（COFF 符號表）。
LLVM 工具位置：環境變數 LLVM_BIN，預設 /opt/homebrew/opt/llvm/bin。
"""

from __future__ import annotations

import bisect
import functools
import json
import os
import re
import subprocess
import sys
from pathlib import Path

LLVM_BIN = Path(os.environ.get("LLVM_BIN", "/opt/homebrew/opt/llvm/bin"))

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
def image_base(dll: str) -> int:
    match = IMAGE_BASE.search(llvm("llvm-readobj", "--file-headers", dll))
    if not match:
        raise ValueError(f"找不到 ImageBase：{dll}")
    return int(match[1], 16)


def to_va(regions: list[tuple[int, str]], address: int) -> tuple[str, int] | None:
    """執行時位址 → (DLL, PE 檔內 VA)；不在任何 DLL 內時回傳 None。"""
    index = bisect.bisect_right(regions, (address, chr(0x10FFFF))) - 1
    if index < 0:
        return None
    lowest_mapping, dll = regions[index]
    # 實際載入 base = 最低映射位址向下取 64K
    return dll, address - (lowest_mapping & IMAGE_ALIGNMENT_MASK) + image_base(dll)


def symbolize(dll: str, addrs: list[int]) -> list[str]:
    """回傳各 VA 的「符號+偏移」（最近的前一個符號），找不到時為 "?"。"""
    output = llvm("llvm-symbolizer", f"--obj={dll}", "--output-style=JSON", *map(hex, addrs))
    names = []
    for va, entry in zip(addrs, json.loads(output)):
        symbol = entry["Symbol"][0]
        start = symbol.get("StartAddress")
        if symbol.get("FunctionName") and start:
            names.append(f"{symbol['FunctionName']}+{va - int(start, 16):#x}")
        else:
            names.append("?")
    return names


def main(argv: list[str]) -> None:
    if len(argv) < 3:
        sys.exit(__doc__)
    regions = load_regions(Path(argv[1]))
    addresses = argv[2:]
    located = [to_va(regions, int(address, 16)) for address in addresses]
    by_dll: dict[str, list[int]] = {}
    for found in located:
        if found:
            by_dll.setdefault(found[0], []).append(found[1])
    names = {dll: dict(zip(addrs, symbolize(dll, addrs))) for dll, addrs in by_dll.items()}
    for address, found in zip(addresses, located):
        print(address, f"{Path(found[0]).name}!{names[found[0]][found[1]]}" if found else "?")


if __name__ == "__main__":
    main(sys.argv)
