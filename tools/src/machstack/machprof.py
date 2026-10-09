#!/usr/bin/env python3
"""machprof：彙整多次 machstack 快照（已經 symbolize.py 處理），列出各執行緒的 CPU 時間增量與最常見的呼叫鏈。
用法：machprof.py <symbolized.txt>"""
import collections
import re
import sys


def main(path):
    blocks = open(path, errors='replace').read().split('=== thread[')
    first, last = {}, {}
    stacks = collections.defaultdict(collections.Counter)
    for b in blocks[1:]:
        m = re.search(r"tid=(\d+) name='([^']*)'.*user=([\d.]+)s sys=([\d.]+)s", b)
        if not m:
            continue
        tid, name = m[1], m[2]
        t = float(m[3]) + float(m[4])
        first.setdefault(tid, t)
        last[tid] = (t, name)
        sc = re.search(r'x16=(-?\d+)', b)
        frames = re.findall(r'\{([^}]*)\}', b.split('x86 stack scan')[0])
        key = 'syscall=%s | ' % (sc[1] if sc else '?') if '(syscall)' in b else 'running/other | '
        key += ' <- '.join(f.split(' (in ')[0] for f in frames[:5])
        stacks[tid][key] += 1
    for tid, (t, name) in sorted(last.items(), key=lambda x: -(x[1][0] - first[x[0]])):
        d = t - first[tid]
        if d < 0.05:
            continue
        print('\n### tid=%s name=%s cpu_delta=%.2fs' % (tid, name, d))
        for k, c in stacks[tid].most_common(4):
            print('  %2d× %s' % (c, k[:300]))


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
