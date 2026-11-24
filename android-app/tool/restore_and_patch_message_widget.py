"""从原始 zip 恢复单个文件，并把助手消息操作栏整块替换为 SizedBox.shrink。

用法：python tool\restore_and_patch_message_widget.py
"""
import io
import os
import zipfile

ZIP = os.path.join("..", "..", "kelivo-master.zip")
REL = "kelivo-master/lib/features/chat/widgets/chat_message_widget.dart"
TARGET = os.path.join("lib", "features", "chat", "widgets", "chat_message_widget.dart")

with zipfile.ZipFile(ZIP) as z:
    data = z.read(REL)
with io.open(TARGET, "wb") as f:
    f.write(data)
print("restored from zip")

with io.open(TARGET, encoding="utf-8") as f:
    lines = f.read().split("\n")

# 找到含 ('assistant-actions' 的 AnimatedSwitcher 起始行
anchor = None
for i, line in enumerate(lines):
    if "('assistant-actions'" in line:
        anchor = i
        break
if anchor is None:
    raise SystemExit("anchor not found")

# 向上找到 AnimatedSwitcher( 开头
start = None
for j in range(anchor, -1, -1):
    if lines[j].strip() == "AnimatedSwitcher(":
        start = j
        break
if start is None:
    raise SystemExit("AnimatedSwitcher( not found")

indent = len(lines[start]) - len(lines[start].lstrip())
# 结束：同缩进的 ")," 或 ");"
end = None
for k in range(start + 1, len(lines)):
    stripped = lines[k].strip()
    line_indent = len(lines[k]) - len(lines[k].lstrip())
    if line_indent == indent and stripped in (",)", ");", "),", ")"):
        end = k
        break
if end is None:
    raise SystemExit("end not found")

print("replacing lines %d-%d" % (start + 1, end + 1))
replacement = [
    " " * indent + "// ChatTtt：助手消息下方的操作栏（复制 / 重新回答 / TTS / 翻译 / 更多）已移除。",
    " " * indent + "const SizedBox.shrink(),",
]
lines[start:end + 1] = replacement
with io.open(TARGET, "w", encoding="utf-8") as f:
    f.write("\n".join(lines))
print("done")
