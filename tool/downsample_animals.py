"""一次性资源工具：把 _source_assets/animals_original 下的 1024px 原图
降采样为 512x512 写入 assets/animals/（LANCZOS + optimize，保留透明通道）。

用法（项目根目录）：
    python tool/downsample_animals.py
"""
import glob
import os
import sys

from PIL import Image

SRC = '_source_assets/animals_original'
DST = 'assets/animals'
SIZE = (512, 512)


def main() -> int:
    os.makedirs(DST, exist_ok=True)
    total_src = total_dst = 0
    for path in sorted(glob.glob(os.path.join(SRC, '*.png'))):
        name = os.path.basename(path)
        img = Image.open(path).convert('RGBA')
        if img.size != SIZE:
            img = img.resize(SIZE, Image.LANCZOS)
        out = os.path.join(DST, name)
        img.save(out, optimize=True)
        s, d = os.path.getsize(path), os.path.getsize(out)
        total_src += s
        total_dst += d
        print(f'{name:24s} {s/1024:8.0f} KB -> {d/1024:6.0f} KB')
    print(f'{"TOTAL":24s} {total_src/1024/1024:7.1f} MB -> '
          f'{total_dst/1024/1024:5.1f} MB')
    return 0


if __name__ == '__main__':
    sys.exit(main())
