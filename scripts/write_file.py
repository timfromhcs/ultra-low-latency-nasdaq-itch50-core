import sys, base64
mode = sys.argv[1] # 'w' or 'a'
path = sys.argv[2]
data = base64.b64decode(sys.argv[3]).decode('utf-8')
with open(path, mode) as fp:
    fp.write(data)
