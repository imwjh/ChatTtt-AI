"""裁掉 ChatTtt 用不到的 Android 权限（对应功能已移除）。"""
import io
import re
import sys

path = sys.argv[1]
with io.open(path, encoding="utf-8") as f:
    text = f.read()

drop = [
    "MANAGE_EXTERNAL_STORAGE",
    "SCHEDULE_EXACT_ALARM",
    "RECEIVE_BOOT_COMPLETED",
    "REQUEST_IGNORE_BATTERY_OPTIMIZATIONS",
    "SYSTEM_ALERT_WINDOW",
    "POST_PROMOTED_NOTIFICATIONS",
    "READ_CALENDAR",
    "WRITE_CALENDAR",
    "ACCESS_COARSE_LOCATION",
    "ACCESS_FINE_LOCATION",
    "hardware.location",
    "PACKAGE_USAGE_STATS",
]

lines = text.split("\n")
out = []
skip_block = False
removed = 0
for line in lines:
    if "PACKAGE_USAGE_STATS" in line:
        skip_block = True
        removed += 1
        continue
    if skip_block:
        removed += 1
        if "ProtectedPermissions" in line:
            skip_block = False
        continue
    hit = None
    for d in drop:
        if d in line:
            hit = d
            break
    if hit:
        removed += 1
        continue
    out.append(line)

with io.open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out))
print("removed %d lines" % removed)
