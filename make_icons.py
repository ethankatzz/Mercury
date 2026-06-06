#!/usr/bin/env python3
"""Generate Mercury's art from the chrome logo.

Both the menu-bar mark and the dock icon are the *isolated* chrome glyphs on a
fully transparent background -- no plate, no squircle. Only size/padding differ.

Source resolution order (first that exists wins):
  1. the original square upload (if still mounted)
  2. the high-detail chrome render from the Cadence exploration
  3. Mercury's existing AppIcon.png
"""
import os
import numpy as np
from PIL import Image, ImageFilter

OUT = "/home/claude/mercury/Resources"
CANDIDATES = [
    "/mnt/user-data/uploads/poopfartyhdf.png",
    "/home/claude/Cadence/Resources/DockIcon.png",
    "/home/claude/mercury/Resources/AppIcon.png",
]
SRC = next((p for p in CANDIDATES if os.path.exists(p)), None)
if SRC is None:
    raise SystemExit("no logo source found")
print("source:", SRC)

# scipy is optional; fall back to a small BFS if it's unavailable
try:
    from scipy import ndimage
    def _label(mask):
        return ndimage.label(mask)[0]
except Exception:
    def _label(mask):
        from collections import deque
        h, w = mask.shape
        lbl = np.zeros((h, w), np.int32)
        cur = 0
        for sy in range(h):
            for sx in range(w):
                if mask[sy, sx] and lbl[sy, sx] == 0:
                    cur += 1
                    q = deque([(sy, sx)]); lbl[sy, sx] = cur
                    while q:
                        y, x = q.popleft()
                        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                            ny, nx = y+dy, x+dx
                            if 0<=ny<h and 0<=nx<w and mask[ny,nx] and lbl[ny,nx]==0:
                                lbl[ny,nx]=cur; q.append((ny,nx))
        return lbl


def isolate(src_path):
    """RGBA of just the glyphs, transparent background. Composite over black
    first so any pre-existing transparent corners join the background flood."""
    im = Image.open(src_path).convert("RGBA")
    bg = Image.new("RGBA", im.size, (0, 0, 0, 255))
    im = Image.alpha_composite(bg, im).convert("RGB")
    arr = np.asarray(im).astype(np.int16)
    luma = 0.299 * arr[:, :, 0] + 0.587 * arr[:, :, 1] + 0.114 * arr[:, :, 2]
    near_black = luma < 34

    lbl = _label(near_black)
    # background = the dark field: any near-black blob that touches the image
    # border OR is large in area. (A rendered plate may have a bright rim that
    # splits it from the border ring, so border-connectivity alone isn't enough.
    # Small interior dark reflections inside the chrome stay, keeping the glyphs
    # solid.)
    border_ids = set(np.unique(np.concatenate([lbl[0, :], lbl[-1, :], lbl[:, 0], lbl[:, -1]])))
    border_ids.discard(0)
    big_ids = set()
    if lbl.max() > 0:
        counts = np.bincount(lbl.ravel())
        thresh = 0.03 * lbl.size
        big_ids = {i for i in range(1, len(counts)) if counts[i] > thresh}
    bg_ids = border_ids | big_ids
    background = np.isin(lbl, list(bg_ids))
    # A rendered plate can leave a thin bright rim between the outer ring and the
    # inner plate; both are now background, so grow the background a few px to
    # close that rim. Glyphs sit well inside, so they're unaffected.
    try:
        from scipy import ndimage as _nd
        background = _nd.binary_dilation(background, iterations=6)
    except Exception:
        pass

    alpha = np.where(background, 0, 255).astype(np.uint8)
    alpha_img = Image.fromarray(alpha, "L").filter(ImageFilter.GaussianBlur(0.7))
    rgba = np.dstack([arr.astype(np.uint8), np.asarray(alpha_img)])
    glyph = Image.fromarray(rgba, "RGBA")
    return glyph.crop(glyph.getbbox())


def fit_square(glyph, size, fill_frac):
    target = int(size * fill_frac)
    w, h = glyph.size
    scale = target / max(w, h)
    g = glyph.resize((max(1, round(w * scale)), max(1, round(h * scale))), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(g, ((size - g.size[0]) // 2, (size - g.size[1]) // 2), g)
    return canvas


glyph = isolate(SRC)
print("isolated glyph bbox:", glyph.size)

# ---------- menu-bar mark ----------
pad = int(0.05 * max(glyph.size))
ribbon = Image.new("RGBA", (glyph.size[0] + 2 * pad, glyph.size[1] + 2 * pad), (0, 0, 0, 0))
ribbon.paste(glyph, (pad, pad), glyph)
target_h = 88
scale = target_h / ribbon.size[1]
ribbon = ribbon.resize((max(1, int(ribbon.size[0] * scale)), target_h), Image.LANCZOS)
ribbon.save(f"{OUT}/RibbonIcon.png")
print("ribbon:", ribbon.size)

# ---------- dock icon: isolated, transparent, breathing room ----------
SIZE = 1024
dock_img = fit_square(glyph, SIZE, fill_frac=0.74)
dock_img.save(f"{OUT}/AppIcon.png")
print("dock:", dock_img.size)

# ---------- .icns ----------
try:
    sizes = [16, 32, 64, 128, 256, 512, 1024]
    icons = [dock_img.resize((s, s), Image.LANCZOS) for s in sizes]
    dock_img.save(f"{OUT}/AppIcon.icns", format="ICNS", append_images=icons)
    print("icns: ok")
except Exception as e:
    print("icns failed:", e)
