#!/usr/bin/env python3
"""Wine PE DLL 位址 → 函式名。用法：pesym.py <vmmap 區段檔（起點 路徑）> addr...
以每個 DLL 檔案的最低映射位址當作 image base，搭配 COFF 符號表（section 相對）求最近符號。"""
import sys,subprocess,re,functools,os
if len(sys.argv) < 3:
    sys.exit(__doc__)
LO=os.environ.get('LLVM_BIN', '/opt/homebrew/opt/llvm/bin') + '/'
regions={}
for l in open(sys.argv[1]):
    a,p=l.split(None,1); p=p.strip(); a=int(a,16)
    regions[p]=min(a,regions.get(p,a))
bases=sorted((b,p) for p,b in regions.items())
@functools.lru_cache(None)
def syms(path):
    secs={}
    for l in subprocess.run([LO+'llvm-objdump','-h',path],capture_output=True,text=True).stdout.splitlines():
        m=re.match(r'\s*(\d+)\s+(\S+)\s+([0-9a-f]+)\s+([0-9a-f]+)',l)
        if m: secs[int(m[1])+1]=int(m[4],16)
    out=[]
    for l in subprocess.run([LO+'llvm-objdump','--syms',path],capture_output=True,text=True).stdout.splitlines():
        m=re.search(r'\(sec\s+(\d+)\).*?(0x[0-9a-f]+) (\S+)$',l)
        if m and int(m[1]) in secs: out.append((secs[int(m[1])]+int(m[2],16),m[3]))
    out.sort(); return out
def resolve(a):
    cand=[(b,p) for b,p in bases if b<=a]
    if not cand: return '?'
    b,p=cand[-1]
    s=syms(p)
    # 映像以 64K 對齊載入：實際 base = 最低映射位址向下取 64K；換算成 PE 檔內的 VA 再查符號
    hdr=subprocess.run([LO+'llvm-readobj','--file-headers',p],capture_output=True,text=True).stdout
    imgbase=int(re.search(r'ImageBase: (0x[0-9A-Fa-f]+)',hdr)[1],16)
    base=b & ~0xffff
    va=a-base+imgbase
    best=[x for x in s if x[0]<=va]
    name=best[-1][1]+'+0x%x'%(va-best[-1][0]) if best else '?'
    return '%s!%s'%(os.path.basename(p),name)
for x in sys.argv[2:]:
    print(x, resolve(int(x,16)))
