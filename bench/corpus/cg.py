#!/usr/bin/env python3
"""cg.py <corpus.tsv> <callgrind.out...>: corpus.c hot|prep's T lines with the instructions per execution taken from
callgrind's dumps (corpus.c -DCORPUS_CALLGRIND: one dump per statement and mode, labelled "<id> <mode> <executions>",
its Ir the counted regions only) and cycles -1; the rest as corpus.c printed it. A statement without a dump keeps -1."""
import sys
ir = {}
for f in sys.argv[2:]:
    label = n = None
    for l in open(f, errors='replace'):
        if l.startswith('desc: Trigger: Client Request: '): label = l.split(': ', 2)[2].strip()
        elif l.startswith(('summary:', 'totals:')): n = int(l.split()[1])
    if label and n is not None:
        i, m, k = label.rsplit(' ', 2); ir[i] = (n, int(k))
for l in open(sys.argv[1], errors='replace'):
    p = l.rstrip('\n').split('\t')
    if p[0] == 'T' and len(p) >= 12:
        n, k = ir.get(p[1], (None, 0))
        p[8] = f'{n / k:.1f}' if n is not None and k else '-1'; p[9] = '-1'
    print('\t'.join(p))
