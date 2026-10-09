#!/usr/bin/env python3
"""machstack 輸出後處理：替 x86 位址補上符號。
- dyld shared cache 內的系統函式庫：交給 symx86（Rosetta 下 dladdr，同一 slide）
- 磁碟上的 Mach-O（wine、ntdll.so、win32u.so…）：atos -arch x86_64 -l <load>
用法：symbolize.py machstack-output.txt（symx86 位置：環境變數 SYMX86，預設 build/tools/symx86）"""
import re, subprocess, sys, os
root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..', '..'))
symx86 = os.environ.get('SYMX86') or os.path.join(root, 'build', 'tools', 'symx86')
if len(sys.argv) != 2:
    sys.exit(__doc__)
lines = open(sys.argv[1], errors='replace').read().splitlines()
pat = re.compile(r'0x([0-9a-f]{16}).*\[img (\S+) load=0x([0-9a-f]+) off=0x([0-9a-f]+)\]')
cache, disk = set(), {}
for l in lines:
    m = pat.search(l)
    if not m: continue
    a, path, load = int(m[1], 16), m[2], int(m[3], 16)
    if os.path.exists(path): disk.setdefault((path, load), set()).add(a)
    else: cache.add(a)
sym = {}
if cache:
    out = subprocess.run(['arch', '-x86_64', symx86], input='\n'.join('%x' % a for a in sorted(cache)) + '\n',
                         capture_output=True, text=True).stdout
    for o in out.splitlines():
        k, _, v = o.partition(' ')
        if v != '?': sym[int(k, 16)] = v
for (path, load), addrs in disk.items():
    addrs = sorted(addrs)
    out = subprocess.run(['atos', '-arch', 'x86_64', '-o', path, '-l', hex(load)] + [hex(a) for a in addrs],
                         capture_output=True, text=True).stdout.splitlines()
    for a, o in zip(addrs, out):
        if not o.startswith('0x'): sym[a] = os.path.basename(path) + '`' + o
for l in lines:
    m = pat.search(l)
    if m and int(m[1], 16) in sym:
        l = l[:l.index('[img')] + '{' + sym[int(m[1], 16)] + '}'
    print(l)
