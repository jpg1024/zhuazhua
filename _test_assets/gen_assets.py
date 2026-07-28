# 生成测试素材：白底图片 + 带 MTL 的低模金字塔 OBJ
import struct, zlib, os

out_dir = os.path.join(os.path.dirname(__file__))

def png_chunk(tag, data):
    c = tag + data
    return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c))

def write_png(path, w, h, pixel_fn):
    raw = b''
    for y in range(h):
        raw += b'\x00'
        for x in range(w):
            raw += bytes(pixel_fn(x, y))
    ihdr = struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0)
    with open(path, 'wb') as f:
        f.write(b'\x89PNG\r\n\x1a\n')
        f.write(png_chunk(b'IHDR', ihdr))
        f.write(png_chunk(b'IDAT', zlib.compress(raw)))
        f.write(png_chunk(b'IEND', b''))

# 白底 + 中央橙色圆形（模拟白底宠物照片）
W = H = 200
cx, cy, r = 100, 110, 60
def px(x, y):
    if (x-cx)**2 + (y-cy)**2 <= r*r:
        return (240, 140, 60)
    if (x-cx)**2 + (y-cy-70)**2 <= 900:  # 底部小圆当"脚"
        return (200, 100, 40)
    return (255, 255, 255)
write_png(os.path.join(out_dir, 'test_white_bg.png'), W, H, px)

# 低模彩色金字塔 OBJ + MTL
obj = """mtllib pyramid.mtl
v -1 0 -1
v 1 0 -1
v 1 0 1
v -1 0 1
v 0 1.6 0
vn 0 -1 0
usemtl body
f 1//1 2//1 3//1
f 1//1 3//1 4//1
usemtl face
f 1//1 2//1 5//1
f 2//1 3//1 5//1
f 3//1 4//1 5//1
f 4//1 1//1 5//1
"""
mtl = """newmtl body
Kd 0.9 0.55 0.2
Ka 0.2 0.1 0.05
newmtl face
Kd 0.35 0.55 0.9
Ka 0.05 0.1 0.2
"""
with open(os.path.join(out_dir, 'pyramid.obj'), 'w') as f:
    f.write(obj)
with open(os.path.join(out_dir, 'pyramid.mtl'), 'w') as f:
    f.write(mtl)
print('done')
