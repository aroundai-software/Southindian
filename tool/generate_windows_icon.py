"""Builds the multi-resolution Windows icon from the mobile app icon.

flutter_launcher_icons only emits a single 256px frame, which Windows
downscales badly for the 16px taskbar and Explorer views.

Run from the project root:  python tool/generate_windows_icon.py
"""

from pathlib import Path

from PIL import Image

SOURCE = Path("assets/icon/app_icon.png")
TARGET = Path("windows/runner/resources/app_icon.ico")
SIZES = [16, 24, 32, 48, 64, 128, 256]


def main() -> None:
    icon = Image.open(SOURCE).convert("RGBA")

    # Square the canvas before resizing so no frame ends up distorted.
    if icon.width != icon.height:
        side = max(icon.size)
        square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
        square.paste(icon, ((side - icon.width) // 2, (side - icon.height) // 2))
        icon = square

    frames = [icon.resize((s, s), Image.LANCZOS) for s in SIZES]
    frames[-1].save(TARGET, format="ICO", sizes=[(s, s) for s in SIZES])

    print(f"wrote {TARGET} with sizes {SIZES}")


if __name__ == "__main__":
    main()
