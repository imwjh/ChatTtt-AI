import re
import zipfile

ZIP = r"E:\WJH\个人网站\waner\kelivo-master.zip"
with zipfile.ZipFile(ZIP) as z:
    lock = z.read("kelivo-master/pubspec.lock").decode("utf-8")

for name in ("irondash_engine_context", "irondash_message_channel"):
    m = re.search(r"\n  %s:\n(?:.*\n)*?    version: \"([^\"]+)\"" % name, lock)
    print(name, "->", m.group(1) if m else "NOT IN UPSTREAM LOCK")

# 上游 pubspec 里对 irondash 的声明
with zipfile.ZipFile(ZIP) as z:
    ps = z.read("kelivo-master/pubspec.yaml").decode("utf-8")
for line in ps.split("\n"):
    if "irondash" in line:
        print("pubspec:", line.strip())
