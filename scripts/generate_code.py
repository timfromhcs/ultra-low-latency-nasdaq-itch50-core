# Complete Code Generator for ITCH Core
import os

def w(fn, c):
    os.makedirs(os.path.dirname(fn), exist_ok=True)
    with open(fn, 'w') as fp:
        fp.write(c.strip() + '
')
    print(f'Generated {fn}')
