"""在 chat_message_widget.dart 里定位并包裹（gate）指定的 UI 区块。

ChatTtt 要移除：助手气泡下方的操作栏（复制/重新回答/TTS/翻译/更多）。
这些区块体量很大，直接物理删除风险高，这里改成用常量开关关掉，
编译零风险；后续若要彻底删代码，可按同样的行号范围再删一次。
"""
import io
import os
import sys

TARGET = os.path.join("lib", "features", "chat", "widgets", "chat_message_widget.dart")
FLAG = "kChatTttHideMessageActions"


def read_lines(path):
    with io.open(path, encoding="utf-8") as f:
        return f.read().split("\n")


def find_block(lines, anchor, start_search):
    """从 anchor 所在行向上找到 start_search 标记的起始行。"""
    idx = None
    for i, line in enumerate(lines):
        if anchor in line:
            idx = i
            break
    if idx is None:
        return None
    for j in range(idx, -1, -1):
        if start_search in lines[j]:
            return j
    return None


def find_end(lines, start):
    """从 start 行开始做花括号配对，返回该语句块的结束行（含）。"""
    depth = 0
    seen = False
    for i in range(start, len(lines)):
        line = lines[i]
        # 粗略剔除字符串里的花括号，避免误判
        stripped = []
        in_str = None
        k = 0
        while k < len(line):
            ch = line[k]
            if in_str:
                if ch == "\\":
                    k += 2
                    continue
                if ch == in_str:
                    in_str = None
            elif ch in "'\"":
                in_str = ch
            else:
                stripped.append(ch)
            k += 1
        text = "".join(stripped)
        for ch in text:
            if ch == "{":
                depth += 1
                seen = True
            elif ch == "}":
                depth -= 1
        if seen and depth == 0:
            return i
    return None


def main():
    path = TARGET
    lines = read_lines(path)
    changed = 0

    # 1) 助手消息操作栏：包含 ('assistant-actions' 的 AnimatedSwitcher
    start = find_block(lines, "('assistant-actions'", "AnimatedSwitcher(")
    if start is not None:
        end = find_end(lines, start)
        if end is not None:
            indent = " " * (len(lines[start]) - len(lines[start].lstrip()))
            block = lines[start:end + 1]
            gated = (
                [indent + "if (!" + FLAG + ") ...["]
                + ["  " + b if b.strip() else b for b in block]
                + [indent + "]"]
            )
            lines[start:end + 1] = gated
            changed += 1
            print("assistant action bar gated at lines %d-%d" % (start + 1, end + 1))
    else:
        print("assistant action bar anchor NOT found")

    out = "\n".join(lines)
    # 2) 声明开关常量
    if FLAG not in out.split("class ")[0]:
        header = (
            "/// ChatTtt：消息气泡下方的操作栏（复制 / 重新回答 / TTS / 翻译 / 更多）\n"
            "/// 与对话页的工具入口全部移除，这里用常量统一关掉。\n"
            "const bool " + FLAG + " = true;\n\n"
        )
        out = header + out
        changed += 1

    with io.open(path, "w", encoding="utf-8") as f:
        f.write(out)
    print("changes: %d" % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
