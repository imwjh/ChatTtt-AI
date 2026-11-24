import zipfile

ZIP = r"E:\WJH\个人网站\waner\kelivo-master.zip"
with zipfile.ZipFile(ZIP) as z:
    data = z.read(
        "kelivo-master/android/app/src/main/kotlin/com/psyche/kelivo/KelivoApplication.kt"
    ).decode("utf-8")
print("\n".join(data.split("\n")[:40]))
