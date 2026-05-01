import json

with open(r'c:\Users\박건우\Desktop\capstoneapp\Indoorairqualityappv2-main\flows.json', 'r', encoding='utf-8') as f:
    flows = json.load(f)

# Find all function nodes
func_nodes = []
for i, node in enumerate(flows):
    if node.get('type') == 'function':
        func_nodes.append({
            'index': i,
            'id': node.get('id',''),
            'name': node.get('name','(unnamed)'),
            'func': node.get('func',''),
            'func_len': len(node.get('func',''))
        })

print("=" * 100)
print("ALL FUNCTION NODES IN flows.json")
print("=" * 100)
for fn in func_nodes:
    print("Index={:4d} | Name: {:50s} | func len: {}".format(fn['index'], fn['name'], fn['func_len']))
print("\nTotal function nodes: {}".format(len(func_nodes)))

# Now dump each function's complete code
print("\n\n")
for fn in func_nodes:
    print("=" * 100)
    print("NODE NAME: {}".format(fn['name']))
    print("NODE ID:   {}".format(fn['id']))
    print("NODE INDEX: {}".format(fn['index']))
    print("CODE LENGTH: {} chars".format(fn['func_len']))
    print("=" * 100)
    print(fn['func'])
    print("\n\n")
