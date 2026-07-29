# -*- coding: utf-8 -*-
import colorsys
from PIL import Image

src = Image.open("assets/animals/cat.png").convert("RGBA")
px = src.load()
w, h = src.size

ORANGE_HUE = 24 / 360.0

for y in range(h):
    for x in range(w):
        r, g, b, a = px[x, y]
        if a == 0:
            continue
        hh, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        if s < 0.45:  # gray/black body fur, keep saturated yellow eyes intact
            nv = min(1.0, 0.55 + 0.45 * (v ** 0.55))
            ns = 0.80 - 0.25 * v
            nr, ng, nb = colorsys.hsv_to_rgb(28 / 360.0, ns, nv)
            px[x, y] = (int(nr * 255), int(ng * 255), int(nb * 255), a)

src.save("assets/animals/cat.png")
print("done", src.size)
