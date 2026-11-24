"""移除 Kotlin 侧对 NativeMessageInputPlugin 的引用。

该插件类在上游依赖里并不存在（属于未同步的原生输入法增强功能），
与 ChatTtt 的聊天主链路无关，直接摘掉以保证可编译。
"""
import io
import os
import re

ROOT = os.path.join("android", "app", "src", "main", "kotlin", "com", "imwjh", "chatttt")

APP = os.path.join(ROOT, "KelivoApplication.kt")
MAIN = os.path.join(ROOT, "MainActivity.kt")
TEST = os.path.join(ROOT, "input", "MirrorConnectionSelectionTest.kt")

with io.open(APP, encoding="utf-8") as f:
    app = f.read()
app = app.replace("import com.imwjh.chatttt.input.NativeMessageInputPlugin\n", "")
app = app.replace(
    "    lateinit var messageInput: NativeMessageInputPlugin\n        private set\n",
    "",
)
app = app.replace("            messageInput = NativeMessageInputPlugin(this, messenger)\n", "")
with io.open(APP, "w", encoding="utf-8") as f:
    f.write(app)
print("patched KelivoApplication.kt")

with io.open(MAIN, encoding="utf-8") as f:
    main = f.read()
main = re.sub(r"[ \t]*kelivo\.messageInput\.(attachActivity|detachActivity)\(this\)\r?\n", "", main)
with io.open(MAIN, "w", encoding="utf-8") as f:
    f.write(main)
print("patched MainActivity.kt")

if os.path.exists(TEST):
    os.remove(TEST)
    print("removed stray test file")
