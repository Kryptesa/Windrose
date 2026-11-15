"""Original deterministic monochrome surfaces from the approved texture study."""
import random

from PIL import Image, ImageDraw, ImageFilter


def pattern(size, kind, pixels_per_logical):
    if kind == "flat":
        return Image.new("L", (size, size), 255)
    if kind not in ("paint", "hatch"):
        raise ValueError(f"Unknown surface: {kind}")
    rng = random.Random(1114)
    scale = pixels_per_logical
    detail = max(24, round(size / (scale * .6)))
    surface = Image.frombytes("L", (detail, detail),
        bytes(rng.randint(220, 255) for _ in range(detail * detail)))
    surface = surface.resize((size, size), Image.Resampling.BICUBIC)
    draw = ImageDraw.Draw(surface)
    if kind == "paint":
        for _ in range(110):
            x, y = rng.randrange(size), rng.randrange(size)
            length = rng.uniform(.7, 3.5) * scale
            draw.line((x, y, x + length, y - rng.uniform(0, .7) * scale),
                fill=rng.choice([193, 215, 246, 255]), width=max(1, round(scale * .25)))
        return surface.filter(ImageFilter.GaussianBlur(max(.25, scale * .14)))
    for x in range(-size, size * 2, max(1, round(7 * scale))):
        for y in range(0, size, max(1, round(13 * scale))):
            if rng.random() < .45:
                continue
            yy = y + rng.uniform(-2, 2) * scale
            length = rng.uniform(3, 9) * scale
            xx = x + yy * .5 + rng.uniform(-1, 1) * scale
            draw.line((xx, yy, xx + length * .5, yy - length),
                fill=rng.randint(207, 228), width=max(1, round(.35 * scale)))
    return surface
