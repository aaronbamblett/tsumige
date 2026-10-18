# /// script
# dependencies = ["numpy", "pillow"]
# ///
"""Split a logo into an untinted foreground layer and a recolourable shadow layer.

The shadow is the saturated part of the artwork (the offset brush stroke). Its
colour is stored as a grayscale shade so an app can tint it with the active
theme's accent gradient. The foreground keeps the original pixels untouched.

On-light artwork is dark ink on transparent. Its ink can be saturated, so the
split also requires the shadow to be brighter than --min-brightness. Keep that
floor above the ink's brightest channel.

Usage:
  uv run brand/split_logo.py --input art.png --threshold 0.30 \
      --out-foreground fg.png --out-shadow shadow.png
  uv run brand/split_logo.py --input art_on_light.png --threshold 0.30 \
      --min-brightness 0.45 \
      --out-foreground fg.png --out-shadow shadow.png
"""

import argparse
import pathlib

import numpy as np
from PIL import Image

# A fully opaque bright pixel more saturated than this fraction of the way from
# the foreground paint to the split threshold is a shadow pixel the split
# missed. Only solid pixels fail the run; anti-aliased edges may carry some hue.
OFFENDER_BAND = 0.5


def saturation(rgb: np.ndarray) -> np.ndarray:
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    return np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)


def foreground_paint(foreground: np.ndarray) -> float:
    """Saturation of the foreground's modal opaque colour."""
    opaque = foreground[..., 3] == 255
    if not opaque.any():
        return 0.0
    colours, counts = np.unique(foreground[..., :3][opaque], axis=0, return_counts=True)
    paint = colours[counts.argmax()].astype(np.float64)
    return float((paint.max() - paint.min()) / max(paint.max(), 1))


def split(
    source: np.ndarray, threshold: float, min_brightness: float = 0.0
) -> tuple[np.ndarray, np.ndarray]:
    rgb = source[..., :3].astype(np.float64) / 255
    alpha = source[..., 3]
    is_shadow = (saturation(rgb) > threshold) & (alpha > 0)
    if min_brightness > 0:
        is_shadow &= rgb.max(-1) > min_brightness

    foreground = np.zeros_like(source)
    foreground[..., :3] = source[..., :3]
    foreground[..., 3] = np.where(is_shadow, 0, alpha)

    shadow = np.zeros_like(source)
    shadow[..., :3] = source[..., :3].max(-1)[..., None]
    shadow[..., 3] = np.where(is_shadow, alpha, 0)
    return foreground, shadow


def verify(
    source: np.ndarray,
    foreground: np.ndarray,
    shadow: np.ndarray,
    threshold: float,
    min_brightness: float,
) -> str:
    alpha = source[..., 3].astype(np.int32)
    fg_alpha = foreground[..., 3].astype(np.int32)
    sh_alpha = shadow[..., 3].astype(np.int32)

    if not np.array_equal(fg_alpha + sh_alpha, alpha):
        raise SystemExit(
            f"FAIL: layer alpha does not reproduce the original "
            f"({int((fg_alpha + sh_alpha != alpha).sum())} px differ)"
        )
    if np.any((fg_alpha > 0) & (sh_alpha > 0)):
        raise SystemExit(
            f"FAIL: {int(((fg_alpha > 0) & (sh_alpha > 0)).sum())} px present in both layers"
        )

    rgb = source[..., :3].astype(np.float64) / 255
    sat = saturation(rgb)
    paint = foreground_paint(foreground)
    band = paint + abs(threshold - paint) * OFFENDER_BAND
    above = (fg_alpha > 0) & (sat > band)
    solid = above & (fg_alpha == 255) & (rgb.max(-1) > min_brightness)
    report = (
        f"paint band={band:.3f} (paint {paint:.3f}): "
        f"{int(above.sum())} fg px above it, {int(solid.sum())} fully opaque"
    )
    if solid.any():
        raise SystemExit(
            f"FAIL: {int(solid.sum())} fully opaque foreground px stayed above the "
            f"paint band (max saturation {float(sat[solid].max()):.3f}); "
            f"threshold {threshold} is too high for this artwork"
        )
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=pathlib.Path)
    parser.add_argument("--threshold", required=True, type=float)
    parser.add_argument("--min-brightness", type=float, default=0.0)
    parser.add_argument("--out-foreground", required=True, type=pathlib.Path)
    parser.add_argument("--out-shadow", required=True, type=pathlib.Path)
    args = parser.parse_args()

    if args.min_brightness < 0 or args.min_brightness > 1:
        raise SystemExit("--min-brightness must be between 0 and 1")

    source = np.asarray(Image.open(args.input).convert("RGBA"))
    foreground, shadow = split(source, args.threshold, args.min_brightness)
    report = verify(source, foreground, shadow, args.threshold, args.min_brightness)

    args.out_foreground.parent.mkdir(parents=True, exist_ok=True)
    args.out_shadow.parent.mkdir(parents=True, exist_ok=True)
    Image.fromarray(foreground, "RGBA").save(args.out_foreground)
    Image.fromarray(shadow, "RGBA").save(args.out_shadow)

    shadow_px = int((shadow[..., 3] > 0).sum())
    foreground_px = int((foreground[..., 3] > 0).sum())
    floor = f", min brightness {args.min_brightness}" if args.min_brightness else ""
    print(
        f"split {args.input.name} at {args.threshold}{floor}: "
        f"foreground {foreground_px} px, shadow {shadow_px} px; {report}"
    )


if __name__ == "__main__":
    main()
