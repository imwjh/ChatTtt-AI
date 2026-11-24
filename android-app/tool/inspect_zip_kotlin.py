import zipfile

ZIP = r"E:\WJH\个人网站\waner\kelivo-master.zip"
with zipfile.ZipFile(ZIP) as z:
    names = [n for n in z.namelist() if "/kotlin/" in n and n.endswith(".kt")]
    print("kt files:", len(names))
    roots = sorted(set(n.split("/kotlin/")[1].split("/")[0] for n in names))
    print("roots:", roots)
    for n in names:
        if "input" in n.lower():
            print("  ", n)
