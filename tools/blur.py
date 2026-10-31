"""Upright web copy + face-blurred print copy. Usage: blur.py src web_out blur_out "x,y,r" ...
x, y, r are fractions of the upright image width (x, r) and height (y)."""
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageOps

src, web_out, blur_out, *faces = sys.argv[1:]
img = ImageOps.exif_transpose(Image.open(src)).convert("RGB")
img.thumbnail((1600, 1600))
img.save(web_out, quality=85)

w, h = img.size
out = img.copy()
for f in faces:
    fx, fy, fr = map(float, f.split(","))
    cx, cy, r = fx * w, fy * h, fr * w
    box = tuple(int(v) for v in (cx - r, cy - r * 1.25, cx + r, cy + r * 1.25))
    region = img.crop(box).filter(ImageFilter.GaussianBlur(r / 3))
    mask = Image.new("L", region.size, 0)
    ImageDraw.Draw(mask).ellipse((0, 0, *region.size), fill=255)
    out.paste(region, box[:2], mask.filter(ImageFilter.GaussianBlur(r / 8)))
out.save(blur_out, quality=85)
print(src, img.size)
