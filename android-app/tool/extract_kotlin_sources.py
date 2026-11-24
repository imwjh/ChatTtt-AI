import os
import zipfile

ZIP = r"E:\WJH\个人网站\waner\kelivo-master.zip"
DEST = r"E:\WJH\个人网站\waner\ChatTtt\android-app\android\app\src\main\kotlin\com\imwjh\chatttt"

with zipfile.ZipFile(ZIP) as z:
    names = [
        n for n in z.namelist()
        if "/kotlin/com/psyche/kelivo/" in n
        and (n.endswith(".kt") or n.endswith(".java"))
    ]
    print("total:", len(names))
    for n in names:
        rel = n.split("/kotlin/com/psyche/kelivo/")[1]
        target = os.path.join(DEST, rel.replace("/", os.sep))
        os.makedirs(os.path.dirname(target), exist_ok=True)
        data = z.read(n).replace(b"com.psyche.kelivo", b"com.imwjh.chatttt")
        with open(target, "wb") as f:
            f.write(data)
    # 报告 input 包下的文件
    print("---- input 包 ----")
    for n in names:
        if "/input/" in n:
            print("  ", n.split("/kelivo/")[1])
