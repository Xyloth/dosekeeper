#!/usr/bin/env python3
"""Generate DoseKeeper's web and Windows launcher assets.

The mark pairs a capsule with three connected points around a care circle: one
dose status, shared across patient, caregiver, and provider perspectives.

Requires Pillow. Run from any directory:

    python app/tool/generate_brand_assets.py

Use ``--check`` in CI to validate the committed outputs without rewriting them.
"""

from __future__ import annotations

import argparse
import hashlib
import math
from pathlib import Path

try:
    from PIL import Image, ImageDraw
except ImportError as error:  # pragma: no cover - environment guidance
    raise SystemExit(
        "Pillow is required: install it with `python -m pip install Pillow`."
    ) from error


APP_ROOT = Path(__file__).resolve().parents[1]
WEB_ROOT = APP_ROOT / "web"
WINDOWS_RESOURCES = APP_ROOT / "windows" / "runner" / "resources"

PRIMARY = "#0E7C7B"
PRIMARY_DARK = "#075E60"
CREAM = "#FFF6E5"
MINT = "#BFE7E1"
AMBER = "#F4B942"

PNG_OUTPUTS = {
    WEB_ROOT / "favicon.png": (32, False),
    WEB_ROOT / "icons" / "Icon-192.png": (192, False),
    WEB_ROOT / "icons" / "Icon-512.png": (512, False),
    WEB_ROOT / "icons" / "Icon-maskable-192.png": (192, True),
    WEB_ROOT / "icons" / "Icon-maskable-512.png": (512, True),
}
ICO_OUTPUT = WINDOWS_RESOURCES / "app_icon.ico"
ICO_SIZES = ((16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256))


def _scaled(value: float, canvas_size: int) -> int:
    return round(value * canvas_size)


def _brand_mark(size: int, *, maskable: bool) -> Image.Image:
    """Render one antialiased icon at ``size`` square pixels."""

    supersampling = 8 if size <= 48 else 4
    canvas_size = size * supersampling
    image = Image.new("RGBA", (canvas_size, canvas_size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    silhouette = Image.new("L", image.size, 0)
    silhouette_draw = ImageDraw.Draw(silhouette)

    if maskable:
        # Maskable launchers crop the outer field into platform-specific shapes.
        # All meaningful artwork remains within the central 80% safe zone.
        draw.rectangle((0, 0, canvas_size, canvas_size), fill=PRIMARY)
        silhouette_draw.rectangle((0, 0, canvas_size, canvas_size), fill=255)
    else:
        inset = _scaled(0.025, canvas_size)
        bounds = (inset, inset, canvas_size - inset, canvas_size - inset)
        corner_radius = _scaled(0.22, canvas_size)
        draw.rounded_rectangle(
            bounds,
            radius=corner_radius,
            fill=PRIMARY,
        )
        silhouette_draw.rounded_rectangle(
            bounds,
            radius=_scaled(0.22, canvas_size),
            fill=255,
        )

    # A restrained darker field adds depth without relying on gradients.
    draw.ellipse(
        (
            _scaled(0.36, canvas_size),
            _scaled(0.59, canvas_size),
            _scaled(1.12, canvas_size),
            _scaled(1.16, canvas_size),
        ),
        fill=PRIMARY_DARK,
    )

    center = canvas_size / 2
    orbit_radius = _scaled(0.275 if maskable else 0.305, canvas_size)
    orbit_width = max(1, _scaled(0.035, canvas_size))
    orbit_box = (
        round(center - orbit_radius),
        round(center - orbit_radius),
        round(center + orbit_radius),
        round(center + orbit_radius),
    )
    draw.ellipse(orbit_box, outline=MINT, width=orbit_width)

    # Three equal nodes represent the role views sharing the same truth.
    node_radius = _scaled(0.047 if maskable else 0.052, canvas_size)
    for index, angle_degrees in enumerate((-90, 30, 150)):
        angle = math.radians(angle_degrees)
        x = center + orbit_radius * math.cos(angle)
        y = center + orbit_radius * math.sin(angle)
        fill = AMBER if index == 0 else CREAM
        draw.ellipse(
            (
                round(x - node_radius),
                round(y - node_radius),
                round(x + node_radius),
                round(y + node_radius),
            ),
            fill=fill,
        )

    # The central capsule remains legible down to the 16px Windows icon.
    capsule_width = _scaled(0.19 if maskable else 0.205, canvas_size)
    capsule_height = _scaled(0.395 if maskable else 0.425, canvas_size)
    left = round(center - capsule_width / 2)
    top = round(center - capsule_height / 2)
    right = left + capsule_width
    bottom = top + capsule_height

    capsule_mask = Image.new("L", image.size, 0)
    mask_draw = ImageDraw.Draw(capsule_mask)
    mask_draw.rounded_rectangle(
        (left, top, right, bottom),
        radius=capsule_width // 2,
        fill=255,
    )

    capsule_colors = Image.new("RGBA", image.size, CREAM)
    color_draw = ImageDraw.Draw(capsule_colors)
    midpoint = round((top + bottom) / 2)
    color_draw.rectangle((left, midpoint, right, bottom), fill=AMBER)
    capsule = Image.new("RGBA", image.size, (0, 0, 0, 0))
    capsule.paste(capsule_colors, mask=capsule_mask)
    capsule_draw = ImageDraw.Draw(capsule)
    divider_inset = _scaled(0.012, canvas_size)
    capsule_draw.line(
        (left + divider_inset, midpoint, right - divider_inset, midpoint),
        fill=PRIMARY_DARK,
        width=max(1, _scaled(0.018, canvas_size)),
    )
    capsule = capsule.rotate(
        -38,
        resample=Image.Resampling.BICUBIC,
        center=(center, center),
    )
    image.alpha_composite(capsule)

    # Keep the wave and antialiased artwork inside the launcher silhouette.
    image.putalpha(silhouette)

    return image.resize((size, size), Image.Resampling.LANCZOS)


def generate() -> None:
    for path, (size, maskable) in PNG_OUTPUTS.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        _brand_mark(size, maskable=maskable).save(path, format="PNG", optimize=True)

    ICO_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    _brand_mark(256, maskable=False).save(
        ICO_OUTPUT,
        format="ICO",
        sizes=list(ICO_SIZES),
        bitmap_format="png",
    )


def validate() -> None:
    failures: list[str] = []
    for path, (expected_size, maskable) in PNG_OUTPUTS.items():
        try:
            with Image.open(path) as icon:
                icon.load()
                if icon.format != "PNG":
                    failures.append(f"{path}: expected PNG, found {icon.format}")
                if icon.size != (expected_size, expected_size):
                    failures.append(
                        f"{path}: expected {expected_size}x{expected_size}, found {icon.size}"
                    )
                if maskable and icon.convert("RGBA").getchannel("A").getextrema() != (255, 255):
                    failures.append(f"{path}: maskable asset must have an opaque background")
        except (FileNotFoundError, OSError) as error:
            failures.append(f"{path}: {error}")

    try:
        with Image.open(ICO_OUTPUT) as icon:
            sizes = set(icon.ico.sizes())
            missing = set(ICO_SIZES) - sizes
            if icon.format != "ICO":
                failures.append(f"{ICO_OUTPUT}: expected ICO, found {icon.format}")
            if missing:
                failures.append(f"{ICO_OUTPUT}: missing sizes {sorted(missing)}")
    except (FileNotFoundError, OSError) as error:
        failures.append(f"{ICO_OUTPUT}: {error}")

    if failures:
        raise SystemExit("Asset validation failed:\n- " + "\n- ".join(failures))

    for path in (*PNG_OUTPUTS, ICO_OUTPUT):
        digest = hashlib.sha256(path.read_bytes()).hexdigest()[:12]
        print(f"ok  {path.relative_to(APP_ROOT)}  sha256:{digest}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="validate committed outputs without regenerating them",
    )
    args = parser.parse_args()
    if not args.check:
        generate()
    validate()


if __name__ == "__main__":
    main()
