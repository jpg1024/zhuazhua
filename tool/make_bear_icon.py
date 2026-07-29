# -*- coding: utf-8 -*-
from PIL import Image, ImageDraw

S = 1024
img = Image.new("RGBA", (S, S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

FUR = (198, 141, 92, 255)
FUR_DARK = (128, 84, 46, 255)
INNER_EAR = (245, 214, 183, 255)
MUZZLE = (247, 224, 195, 255)
NOSE = (79, 51, 28, 255)
CHEEK = (244, 152, 156, 210)
EYE = (61, 40, 23, 255)
OUT_W = 22

def circle(cx, cy, r, fill, outline=None, width=0):
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=fill, outline=outline, width=width)

def ellipse(cx, cy, rx, ry, fill, outline=None, width=0):
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=fill, outline=outline, width=width)

# ears
for ex in (250, 774):
    circle(ex, 280, 165, FUR, FUR_DARK, OUT_W)
    circle(ex, 280, 88, INNER_EAR)

# head
circle(512, 560, 385, FUR, FUR_DARK, OUT_W)

# muzzle
ellipse(512, 695, 205, 155, MUZZLE)

# nose (rounded)
ellipse(512, 630, 62, 46, NOSE)

# mouth: small "w" smile
d.arc([440, 630, 516, 720], start=20, end=160, fill=NOSE, width=14)
d.arc([508, 630, 584, 720], start=20, end=160, fill=NOSE, width=14)
d.line([512, 676, 512, 655], fill=NOSE, width=14)

# eyes with highlights
for ex in (352, 672):
    circle(ex, 500, 52, EYE)
    circle(ex + 18, 482, 16, (255, 255, 255, 255))
    circle(ex - 14, 516, 8, (255, 255, 255, 200))

# cheeks
ellipse(262, 620, 72, 48, CHEEK)
ellipse(762, 620, 72, 48, CHEEK)

# top-left soft highlight on head
hl = Image.new("RGBA", (S, S), (0, 0, 0, 0))
hd = ImageDraw.Draw(hl)
hd.ellipse([300, 260, 520, 420], fill=(255, 255, 255, 36))
img = Image.alpha_composite(img, hl)

img.save("bear_1024.png")

sizes = [(256, 256), (128, 128), (64, 64), (48, 48), (32, 32), (16, 16)]
img.resize((256, 256), Image.LANCZOS).save(
    "windows/runner/resources/app_icon.ico", sizes=sizes)
img.resize((256, 256), Image.LANCZOS).save(
    "assets/tray_icon.ico", sizes=sizes)
print("done")
