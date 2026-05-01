import json, sys, os

with open('Indoorairqualityappv2-main/flows.json', 'r', encoding='utf-8') as f:
    nodes = json.load(f)

funcs = [n for n in nodes if n.get('type') == 'function']
print(f'Total function nodes: {len(funcs)}')
print()
for i, fn in enumerate(funcs, 1):
    name = fn.get('name', '(unnamed)')
    nid = fn.get('id', '?')
    outs = fn.get('outputs', 1)
    print(f'  {i:2d}. [{nid}] {name}  (outputs={outs})')

print()
print('='*80)
print()

# Now dump each function's code verbatim
for i, fn in enumerate(funcs, 1):
    name = fn.get('name', '(unnamed)')
    nid = fn.get('id', '?')
    outs = fn.get('outputs', 1)
    code = fn.get('func', '')
    
    print('=' * 80)
    print(f' NODE #{i}: "{name}"')
    print(f' ID: {nid}')
    print(f' Outputs: {outs}')
    print('=' * 80)
    print(code)
    print()
    print()
