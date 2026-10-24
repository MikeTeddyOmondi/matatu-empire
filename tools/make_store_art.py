#!/usr/bin/env python3
"""Generate the experience icon, logo and key art for the Roblox store page.

The matatu is rendered from the same geometry the game uses (tools/make_matatu_mesh.py) with a
"pimped" Vibe livery, then composited with the logo. Needs numpy and Pillow.

Writes to assets/store/:
  icon.png        512x512  experience icon
  logo.png        transparent "MATATU EMPIRE" wordmark, for overlaying on in-game screenshots
  key-art.png     1920x1080 title card (matatu + logo); pair it with in-game screenshots

Usage: python3 tools/make_store_art.py [out_dir]
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

sys.path.insert(0, str(Path(__file__).parent))
import make_matatu_mesh as mm  # noqa: E402

FONT_HEAVY = "/usr/share/fonts/opentype/inter/InterDisplay-Black.otf"
FONT_BOLD = "/usr/share/fonts/opentype/inter/InterDisplay-ExtraBold.otf"

YELLOW = (255, 196, 0)
PINK = (255, 64, 129)
CYAN = (0, 229, 255)
NIGHT = (16, 14, 34)

# Livery for the render: the max-Vibe look (full art wrap, neon, chrome).
PALETTE = {
    "Body": ((0.93, 0.93, 0.90), 0.0),
    "Livery": ((1.0, 0.25, 0.5), 0.9),
    "Glass": ((0.08, 0.10, 0.16), 0.0),
    "Trim": ((0.22, 0.22, 0.25), 0.0),
    "Lights": ((1.0, 0.97, 0.85), 1.0),
    "TailLights": ((1.0, 0.1, 0.1), 1.0),
}


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


# Geometry -----------------------------------------------------------------------------------------

def cylinder_x(cx, cy, cz, radius, width, n=28):
    """Triangles of a cylinder whose axis is X (a wheel)."""
    tris = []
    ring = [(cy + radius * math.sin(2 * math.pi * i / n), cz + radius * math.cos(2 * math.pi * i / n)) for i in range(n)]
    x0, x1 = cx - width / 2, cx + width / 2
    for i in range(n):
        (y0, z0), (y1, z1) = ring[i], ring[(i + 1) % n]
        tris.append([(x0, cy, cz), (x0, y0, z0), (x0, y1, z1)])
        tris.append([(x1, cy, cz), (x1, y1, z1), (x1, y0, z0)])
        tris.append([(x0, y0, z0), (x1, y0, z0), (x1, y1, z1)])
        tris.append([(x0, y0, z0), (x1, y1, z1), (x0, y1, z1)])
    return np.array(tris, float)


def scene():
    parts = mm.build_parts()
    tris, colors, glow = [], [], []
    for name, mesh in parts.items():
        t = np.array(mesh.tris)
        color, g = PALETTE[name]
        tris.append(t)
        colors.append(np.tile(color, (len(t), 1)))
        glow.append(np.full(len(t), g))
    # Graffiti flashes on the body sides (extra livery panels in cyan and yellow).
    extra = mm.Mesh()
    mm.side_panel(extra, 6.5, 9.0, 1.1, 1.9, inset=0.04)
    mm.side_panel(extra, 12.0, 15.5, 1.0, 1.8, inset=0.04)
    t = np.array(extra.tris)
    tris.append(t)
    colors.append(np.tile((0.0, 0.9, 1.0), (len(t), 1)))
    glow.append(np.full(len(t), 0.8))
    extra2 = mm.Mesh()
    mm.side_panel(extra2, 9.2, 11.8, 1.15, 1.85, inset=0.04)
    t = np.array(extra2.tris)
    tris.append(t)
    colors.append(np.tile((1.0, 0.77, 0.0), (len(t), 1)))
    glow.append(np.full(len(t), 0.7))
    # Chrome rims and tyres.
    for s in (mm.FRONT_AXLE, mm.REAR_AXLE):
        for side in (1, -1):
            x = side * (mm.HALF_W + 0.85)
            tyre = cylinder_x(x, -1.0, mm.to_z(s), 2.0, 1.4)
            rim = cylinder_x(x + side * 0.05, -1.0, mm.to_z(s), 1.1, 1.45)
            tris += [tyre, rim]
            colors += [np.tile((0.07, 0.07, 0.08), (len(tyre), 1)), np.tile((0.85, 0.85, 0.9), (len(rim), 1))]
            glow += [np.zeros(len(tyre)), np.zeros(len(rim))]
    return np.concatenate(tris), np.concatenate(colors), np.concatenate(glow)


def render_matatu(width, height, yaw, pitch, distance, focal_scale=1.0, supersample=2):
    """Z-buffered render with transparent background. Returns an RGBA PIL image."""
    W, H = width * supersample, height * supersample
    tris, colors, glow = scene()
    light = np.array([-0.5, 0.8, -0.35])
    light /= np.linalg.norm(light)
    normals = np.cross(tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0])
    normals /= np.linalg.norm(normals, axis=1, keepdims=True) + 1e-12
    shade = 0.35 + 0.65 * np.clip(normals @ light, 0, 1)
    rim_light = np.clip(normals @ np.array([0.6, 0.2, 0.7]), 0, 1) ** 2 * 0.35
    lit = np.clip(colors * shade[:, None] + rim_light[:, None] * np.array([1.0, 0.3, 0.6]), 0, 1)
    lit = lit * (1 - glow[:, None]) + colors * glow[:, None]

    cy, sy, cp, sp = math.cos(yaw), math.sin(yaw), math.cos(pitch), math.sin(pitch)
    rot_y = np.array([[cy, 0, -sy], [0, 1, 0], [sy, 0, cy]])
    rot_x = np.array([[1, 0, 0], [0, cp, -sp], [0, sp, cp]])
    v = tris.reshape(-1, 3) - np.array([0, 2.0, 0])
    v = v @ rot_y.T @ rot_x.T
    v[:, 2] += distance
    f = W * 0.9 * focal_scale
    sx = W / 2 + f * v[:, 0] / v[:, 2]
    syy = H / 2 - f * v[:, 1] / v[:, 2]
    S = np.stack([sx, syy, v[:, 2]], 1).reshape(-1, 3, 3)

    img = np.zeros((H, W, 4))
    zb = np.full((H, W), np.inf)
    for t, c in zip(S, lit):
        x0, x1 = int(max(0, np.floor(t[:, 0].min()))), int(min(W - 1, np.ceil(t[:, 0].max())))
        y0, y1 = int(max(0, np.floor(t[:, 1].min()))), int(min(H - 1, np.ceil(t[:, 1].max())))
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        (ax, ay, az), (bx, by, bz), (cx_, cy_, cz) = t
        den = (by - cy_) * (ax - cx_) + (cx_ - bx) * (ay - cy_)
        if abs(den) < 1e-9:
            continue
        l1 = ((by - cy_) * (xs - cx_) + (cx_ - bx) * (ys - cy_)) / den
        l2 = ((cy_ - ay) * (xs - cx_) + (ax - cx_) * (ys - cy_)) / den
        l3 = 1 - l1 - l2
        m = (l1 >= 0) & (l2 >= 0) & (l3 >= 0)
        z = l1 * az + l2 * bz + l3 * cz
        sub = zb[y0:y1 + 1, x0:x1 + 1]
        upd = m & (z < sub)
        sub[upd] = z[upd]
        img[y0:y1 + 1, x0:x1 + 1][upd] = (*c, 1.0)
    out = Image.fromarray((img * 255).astype(np.uint8), "RGBA")
    return out.resize((width, height), Image.LANCZOS)


# Backgrounds and type -----------------------------------------------------------------------------

def gradient(size, top, bottom):
    w, h = size
    t = np.linspace(0, 1, h)[:, None, None]
    arr = np.array(top)[None, None, :] * (1 - t) + np.array(bottom)[None, None, :] * t
    return Image.fromarray(np.repeat(arr, w, axis=1).astype(np.uint8), "RGB")


def skyline(draw, width, base, scale, color, seed=4):
    """Nairobi-ish skyline silhouette with a KICC tower and saucer."""
    rng = np.random.default_rng(seed)
    x = 0
    while x < width:
        w = int(rng.integers(30, 90) * scale)
        h = int(rng.integers(60, 260) * scale)
        draw.rectangle([x, base - h, x + w, base], fill=color)
        x += w + int(rng.integers(0, 12) * scale)
    kx = int(width * 0.68)
    tower_w, tower_h = int(46 * scale), int(330 * scale)
    draw.rectangle([kx - tower_w // 2, base - tower_h, kx + tower_w // 2, base], fill=color)
    draw.ellipse([kx - int(52 * scale), base - tower_h - int(22 * scale), kx + int(52 * scale), base - tower_h + int(10 * scale)], fill=color)
    draw.pieslice([kx + int(30 * scale), base - int(90 * scale), kx + int(170 * scale), base + int(50 * scale)], 180, 360, fill=color)


def neon_streaks(img, rng, count, colors, y_range, width_range):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    w, _ = img.size
    for _ in range(count):
        y = rng.uniform(*y_range)
        x0 = rng.uniform(-200, w)
        length = rng.uniform(150, 520)
        thick = rng.uniform(*width_range)
        color = colors[int(rng.integers(0, len(colors)))]
        d.line([(x0, y), (x0 + length, y - length * 0.18)], fill=(*color, 230), width=int(thick))
    glow = layer.filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(glow)
    img.alpha_composite(layer)


def outlined_text(draw, xy, text, fnt, fill, outline, width, anchor="mm"):
    draw.text(xy, text, font=fnt, fill=fill, anchor=anchor, stroke_width=width, stroke_fill=outline)


def logo(width):
    """Transparent wordmark: MATATU (yellow) over an EMPIRE badge (pink)."""
    h = int(width * 0.36)
    img = Image.new("RGBA", (width, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    big = font(FONT_HEAVY, int(width * 0.2))
    small = font(FONT_HEAVY, int(width * 0.085))
    outlined_text(d, (width / 2, h * 0.36), "MATATU", big, YELLOW, NIGHT, max(4, width // 60))
    bw, bh = int(width * 0.52), int(h * 0.3)
    bx, by = (width - bw) // 2, int(h * 0.63)
    d.rounded_rectangle([bx, by, bx + bw, by + bh], radius=bh // 3, fill=PINK, outline=NIGHT, width=max(3, width // 120))
    d.text((width / 2, by + bh / 2), "EMPIRE", font=small, fill=(255, 255, 255), anchor="mm")
    shadow = img.copy().filter(ImageFilter.GaussianBlur(width // 80))
    base = Image.new("RGBA", img.size, (0, 0, 0, 0))
    base.alpha_composite(Image.eval(shadow, lambda a: a // 2))
    base.alpha_composite(img)
    return base


def underglow(size, center, rx, ry, color):
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    cx, cy = center
    d.ellipse([cx - rx, cy - ry, cx + rx, cy + ry], fill=(*color, 200))
    return layer.filter(ImageFilter.GaussianBlur(max(6, ry // 2)))


# Outputs ------------------------------------------------------------------------------------------

def make_icon(out: Path):
    size = 512
    bg = gradient((size, size), (255, 120, 40), (120, 20, 90)).convert("RGBA")
    d = ImageDraw.Draw(bg)
    skyline(d, size, int(size * 0.7), 0.55, (60, 10, 60, 255))
    neon_streaks(bg, np.random.default_rng(3), 7, [CYAN, YELLOW, PINK], (size * 0.55, size * 0.85), (5, 10))
    road = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    ImageDraw.Draw(road).polygon([(0, size), (size, size), (size, int(size * 0.68)), (0, int(size * 0.74))], fill=(28, 26, 40, 255))
    bg.alpha_composite(road)

    car = render_matatu(700, 480, yaw=math.radians(34), pitch=math.radians(-10), distance=80, focal_scale=1.6)
    car = car.crop(car.getbbox())
    scale = 470 / car.width
    car = car.resize((int(car.width * scale), int(car.height * scale)), Image.LANCZOS)
    pos = ((size - car.width) // 2 + 6, size - car.height - 18)
    bg.alpha_composite(underglow((size, size), (pos[0] + car.width // 2, pos[1] + car.height - 16), car.width // 2, 20, CYAN))
    bg.alpha_composite(car, pos)

    mark = logo(470)
    bg.alpha_composite(mark, ((size - mark.width) // 2, 14))
    bg.convert("RGB").save(out / "icon.png")
    return bg


def make_key_art(out: Path):
    w, h = 1920, 1080
    bg = gradient((w, h), (255, 150, 60), (90, 20, 100)).convert("RGBA")
    d = ImageDraw.Draw(bg)
    skyline(d, w, int(h * 0.72), 1.5, (70, 18, 70, 255), seed=9)
    skyline(d, w, int(h * 0.76), 1.1, (45, 10, 50, 255), seed=2)
    road = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    rd = ImageDraw.Draw(road)
    rd.polygon([(0, h), (w, h), (w, int(h * 0.74)), (0, int(h * 0.8))], fill=(26, 24, 36, 255))
    for i in range(7):
        x = 140 + i * 270
        rd.polygon([(x, int(h * 0.9)), (x + 150, int(h * 0.885)), (x + 150, int(h * 0.9)), (x, int(h * 0.915))], fill=(235, 235, 230, 255))
    bg.alpha_composite(road)
    neon_streaks(bg, np.random.default_rng(11), 14, [CYAN, YELLOW, PINK], (h * 0.6, h * 0.95), (8, 16))

    car = render_matatu(1700, 1000, yaw=math.radians(30), pitch=math.radians(-7), distance=80, focal_scale=1.6)
    car = car.crop(car.getbbox())
    scale = 1080 / car.width
    car = car.resize((int(car.width * scale), int(car.height * scale)), Image.LANCZOS)
    pos = (w - car.width - 90, h - car.height - 70)
    bg.alpha_composite(underglow((w, h), (pos[0] + car.width // 2, pos[1] + car.height - 30), car.width // 2, 44, CYAN))
    bg.alpha_composite(car, pos)

    mark = logo(820)
    bg.alpha_composite(mark, (80, 70))
    tag = font(FONT_BOLD, 54)
    d = ImageDraw.Draw(bg)
    outlined_text(d, (490, 430), "Run routes across Nairobi", tag, (255, 255, 255), NIGHT, 4)
    bg.convert("RGB").save(out / "key-art.png")


def main():
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("assets/store")
    out.mkdir(parents=True, exist_ok=True)
    logo(1600).save(out / "logo.png")
    make_icon(out)
    make_key_art(out)
    icon = Image.open(out / "icon.png")
    icon.resize((150, 150), Image.LANCZOS).save(out / "icon-150-preview.png")
    print(f"wrote {out}/icon.png, logo.png, key-art.png (+ icon-150-preview.png)")


if __name__ == "__main__":
    main()
