#!/usr/bin/env python3
"""Generates the bundled demo proofs used by `DemoAPIClient`.

Six small photos (JPEG) and one short looping video (MP4). No third-party Python
dependencies: the photos are rendered as PNG and converted with macOS `sips`, the
video is produced with `ffmpeg` when it is installed.
"""
import os
import shutil
import struct
import subprocess
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Dares", "Resources", "DemoMedia")
WIDTH, HEIGHT = 480, 640


def write_png(path, width, height, pixel_fn):
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        row = bytearray()
        for x in range(width):
            r, g, b, a = pixel_fn(x, y)
            row += bytes((max(0, min(255, int(r))), max(0, min(255, int(g))), max(0, min(255, int(b))), a))
        raw += row

    def chunk(typ, data):
        return (struct.pack(">I", len(data)) + typ + data
                + struct.pack(">I", zlib.crc32(typ + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as handle:
        handle.write(png)


def mix(a, b, t):
    t = max(0.0, min(1.0, t))
    return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))


def circle(x, y, cx, cy, r):
    dx, dy = x - cx, y - cy
    return dx * dx + dy * dy <= r * r


def scene_sunrise(x, y):
    """Dawn over a hill."""
    horizon = HEIGHT * 0.68
    if y > horizon:
        depth = (y - horizon) / (HEIGHT - horizon)
        return mix((36, 62, 48), (18, 34, 28), depth) + (255,)
    t = y / horizon
    sky = mix((250, 176, 72), (255, 236, 176), t)
    if circle(x, y, WIDTH * 0.52, HEIGHT * 0.46, WIDTH * 0.17):
        return (255, 244, 200, 255)
    hill = HEIGHT * 0.60 + WIDTH * 0.16 * ((x / WIDTH) - 0.5) ** 2 * 8
    if y > hill:
        return mix((96, 74, 92), (58, 44, 62), (y - hill) / (HEIGHT - hill)) + (255,)
    return sky + (255,)


def scene_kitchen(x, y):
    """A pan on a counter."""
    counter = HEIGHT * 0.68
    if y > counter:
        return mix((120, 84, 56), (84, 58, 40), (y - counter) / (HEIGHT - counter)) + (255,)
    wall = mix((236, 214, 186), (206, 178, 146), y / counter)
    if circle(x, y, WIDTH * 0.5, HEIGHT * 0.45, WIDTH * 0.28):
        pan = mix((58, 58, 62), (30, 30, 34), (y - HEIGHT * 0.2) / (HEIGHT * 0.6))
        if circle(x, y, WIDTH * 0.52, HEIGHT * 0.42, WIDTH * 0.13):
            return mix((236, 176, 72), (214, 142, 44), (x / WIDTH)) + (255,)
        return pan + (255,)
    return wall + (255,)


def scene_field(x, y):
    """A phone face down in the grass."""
    horizon = HEIGHT * 0.30
    if y < horizon:
        return mix((150, 196, 236), (206, 230, 246), y / horizon) + (255,)
    depth = (y - horizon) / (HEIGHT - horizon)
    grass = mix((126, 176, 92), (72, 122, 60), depth)
    if (WIDTH * 0.34 < x < WIDTH * 0.66) and (HEIGHT * 0.56 < y < HEIGHT * 0.78):
        return mix((46, 48, 54), (24, 26, 30), depth) + (255,)
    return grass + (255,)


def scene_sunset_swim(x, y):
    """Sunset over water."""
    horizon = HEIGHT * 0.52
    if y < horizon:
        t = y / horizon
        sky = mix((104, 58, 132), (252, 150, 84), t)
        if circle(x, y, WIDTH * 0.68, HEIGHT * 0.34, WIDTH * 0.13):
            return (255, 226, 170, 255)
        return sky + (255,)
    depth = (y - horizon) / (HEIGHT - horizon)
    water = mix((58, 72, 122), (24, 34, 68), depth)
    if int(y) % 26 < 3:
        water = mix(water, (255, 210, 160), 0.45)
    if circle(x, y, WIDTH * 0.34, HEIGHT * 0.62, WIDTH * 0.07):
        return (36, 28, 34, 255)
    return water + (255,)


def scene_letter(x, y):
    """A handwritten letter with a stamp."""
    paper = mix((248, 244, 232), (232, 226, 210), y / HEIGHT)
    for index in range(9):
        line_y = HEIGHT * 0.28 + index * HEIGHT * 0.062
        if abs(y - line_y) < 3 and WIDTH * 0.16 < x < WIDTH * 0.84:
            if (x // 14) % 5 != 0:
                return mix(paper, (92, 92, 108), 0.75) + (255,)
    if circle(x, y, WIDTH * 0.76, HEIGHT * 0.16, WIDTH * 0.11):
        return mix((206, 68, 58), (168, 40, 36), y / HEIGHT) + (255,)
    return paper + (255,)


def scene_road(x, y):
    """A long walk at golden hour."""
    horizon = HEIGHT * 0.42
    if y < horizon:
        return mix((246, 202, 120), (250, 236, 200), y / horizon) + (255,)
    depth = (y - horizon) / (HEIGHT - horizon)
    road = mix((122, 104, 92), (74, 62, 56), depth)
    if abs(x - WIDTH * 0.5) < WIDTH * 0.06 * (0.4 + depth):
        return mix((196, 180, 166), (150, 138, 128), depth) + (255,)
    return road + (255,)


SCENES = [
    ("demo-proof-1", scene_sunrise),
    ("demo-proof-2", scene_kitchen),
    ("demo-proof-3", scene_field),
    ("demo-proof-4", scene_sunset_swim),
    ("demo-proof-5", scene_letter),
    ("demo-proof-6", scene_road),
]


def to_jpeg(png_path, jpg_path):
    try:
        subprocess.run(
            ["sips", "-s", "format", "jpeg", "-s", "formatOptions", "62", png_path, "--out", jpg_path],
            check=True,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        os.remove(png_path)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def make_video(path):
    ffmpeg = shutil.which("ffmpeg")
    if ffmpeg is None:
        return False
    command = [
        ffmpeg, "-y", "-loglevel", "error",
        "-f", "lavfi", "-i", "testsrc2=size=320x240:rate=12:duration=3",
        "-c:v", "libx264", "-profile:v", "baseline", "-level", "3.0",
        "-pix_fmt", "yuv420p", "-movflags", "+faststart", path,
    ]
    try:
        subprocess.run(command, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def main():
    os.makedirs(ROOT, exist_ok=True)
    for name, scene in SCENES:
        png = os.path.join(ROOT, name + ".png")
        jpg = os.path.join(ROOT, name + ".jpg")
        write_png(png, WIDTH, HEIGHT, scene)
        if not to_jpeg(png, jpg):
            jpg = png
        print("wrote", os.path.relpath(jpg, ROOT), os.path.getsize(jpg), "bytes")

    video = os.path.join(ROOT, "demo-proof-video.mp4")
    if make_video(video):
        print("wrote demo-proof-video.mp4", os.path.getsize(video), "bytes")
    else:
        print("skipped the demo video: ffmpeg is not installed")


if __name__ == "__main__":
    main()
