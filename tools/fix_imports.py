"""Настройки импорта текстур ассетов: сжатие для видеокарты + мипмапы (иначе мерцание и гигабайты VRAM).
Запуск после первого импорта: python tools/fix_imports.py, затем повторный --import.
"""
import glob
import os
import re

ROOT = os.path.join(os.path.dirname(__file__), "..")
changed = 0
for path in glob.glob(os.path.join(ROOT, "assets", "**", "*.import"), recursive=True):
    src = path[:-7]
    if not re.search(r"\.(jpg|jpeg|png)$", src, re.I):
        continue
    if src.endswith("ground_mask.png"):
        continue          # маску читаем на процессоре — без сжатия
    s = open(path, encoding="utf-8").read()
    o = s
    s = re.sub(r"compress/mode=\d", "compress/mode=2", s)
    s = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=true", s)
    normal = "_nor" in os.path.basename(src)
    s = re.sub(r"compress/normal_map=\d", "compress/normal_map=%d" % (1 if normal else 0), s)
    s = re.sub(r"detect_3d/compress_to=\d", "detect_3d/compress_to=0", s)
    if s != o:
        open(path, "w", encoding="utf-8").write(s)
        changed += 1
print("исправлено файлов импорта:", changed)
