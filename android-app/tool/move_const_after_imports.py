"""把常量声明从文件头移到 import 之后（dart 要求 directive 先于 declaration）。"""
import io
import os
import sys

path = sys.argv[1]
with io.open(path, encoding="utf-8") as f:
    text = f.read()

lines = text.split("\n")
# 取出文件头部的常量声明块
block = []
while lines and (lines[0].startswith("///") or
                  lines[0].startswith("const bool kChatTtt") or
                  lines[0].strip() == ""):
    block.append(lines[0])
    lines = lines[1:]
block = [b for b in block if b.strip() != ""]

if not block:
    print("nothing to move")
    sys.exit(0)

last_import = 0
for i, line in enumerate(lines):
    if line.startswith("import ") or line.startswith("export "):
        last_import = i

out = lines[:last_import + 1] + [""] + block + lines[last_import + 1:]
with io.open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print("moved %d lines after line %d" % (len(block), last_import + 1))
