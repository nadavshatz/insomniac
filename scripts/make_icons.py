#!/usr/bin/env python3
"""Regenerate workflow/icon.png and workflow/icons/*.png (dev-only; needs Pillow).

The shipped workflow does not need Python or Pillow: the PNGs are committed.
"""
from pathlib import Path
from PIL import Image, ImageDraw

S = 1024            # draw at 4x then downsample for anti-aliasing
OUT = 256
ROOT = Path(__file__).resolve().parent.parent / "workflow"

COLORS = {
    "brown": (122, 78, 46), "cream": (243, 229, 205), "green": (52, 168, 83),
    "blue": (66, 133, 244), "amber": (245, 166, 35), "red": (219, 68, 55),
    "grey": (110, 116, 128), "white": (255, 255, 255), "night": (44, 52, 84),
}


def canvas(bg):
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.rounded_rectangle((40, 40, S - 40, S - 40), radius=220, fill=COLORS[bg])
    return im, d


def cup(d, color="cream", steam=True):
    c = COLORS[color]
    d.rounded_rectangle((250, 420, 690, 800), radius=90, fill=c)
    d.ellipse((610, 480, 820, 700), outline=c, width=60)
    d.rounded_rectangle((210, 800, 770, 850), radius=25, fill=c)
    if steam:
        for x in (340, 470, 600):
            d.arc((x - 50, 170, x + 50, 300), 90, 270, fill=c, width=34)
            d.arc((x - 50, 280, x + 50, 400), 270, 90, fill=c, width=34)


def clock(d, color="white"):
    c = COLORS[color]
    d.ellipse((220, 220, 804, 804), outline=c, width=70)
    d.line((512, 512, 512, 330), fill=c, width=60)
    d.line((512, 512, 660, 600), fill=c, width=60)
    d.ellipse((480, 480, 544, 544), fill=c)


def laptop(d, color="white"):
    c = COLORS[color]
    d.rounded_rectangle((200, 470, 824, 610), radius=40, fill=c)       # closed lid
    d.rounded_rectangle((160, 610, 864, 680), radius=30, fill=c)       # base
    d.ellipse((560, 210, 760, 410), fill=c)                            # moon
    d.ellipse((610, 180, 810, 380), fill=COLORS["night"])


def stop(d):
    d.rounded_rectangle((320, 320, 704, 704), radius=60, fill=COLORS["white"])


def warning(d):
    d.polygon([(512, 210), (820, 790), (204, 790)], fill=COLORS["white"])
    d.rounded_rectangle((482, 400, 542, 630), radius=30, fill=COLORS["amber"])
    d.ellipse((477, 670, 547, 740), fill=COLORS["amber"])


def info(d):
    d.ellipse((470, 240, 554, 324), fill=COLORS["white"])
    d.rounded_rectangle((462, 400, 562, 780), radius=40, fill=COLORS["white"])


def pencil(d):
    d.polygon([(300, 724), (330, 610), (640, 300), (724, 384), (414, 694)], fill=COLORS["white"])
    d.polygon([(300, 724), (330, 610), (414, 694)], fill=COLORS["cream"])


ICONS = {
    "../icon": ("brown", lambda d: cup(d)),
    "active": ("green", lambda d: cup(d, "white")),
    "idle": ("brown", lambda d: cup(d, "cream", steam=False)),
    "timer": ("blue", clock),
    "lid": ("night", laptop),
    "stop": ("red", lambda d: stop(d)),
    "warning": ("amber", warning),
    "info": ("grey", info),
    "custom": ("grey", pencil),
}

if __name__ == "__main__":
    (ROOT / "icons").mkdir(exist_ok=True)
    for name, (bg, draw) in ICONS.items():
        im, d = canvas(bg)
        draw(d)
        path = (ROOT / "icons" / f"{name}.png").resolve()
        im.resize((OUT, OUT), Image.LANCZOS).save(path, optimize=True)
        print("wrote", path.relative_to(ROOT.parent))
