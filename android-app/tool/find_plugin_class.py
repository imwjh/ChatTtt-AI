import zipfile

ZIP = r"E:\WJH\个人网站\waner\kelivo-master.zip"
with zipfile.ZipFile(ZIP) as z:
    names = [n for n in z.namelist() if "/kotlin/" in n and n.endswith(".kt")]
    roots = sorted(set("/".join(n.split("/kotlin/")[1].split("/")[:-1]) for n in names))
    for r in roots:
        print(r)
    print("---- 含 NativeMessageInputPlugin 的文件 ----")
    for n in names:
        data = z.read(n)
        if b"NativeMessageInputPlugin" in data:
            print(n)
