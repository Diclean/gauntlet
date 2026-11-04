#!/usr/bin/env python3
"""Generates the placeholder raster assets for the Dares app (no third-party deps)."""
import math
import os
import struct
import zlib

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Dares", "Resources")
ASSETS = os.path.join(ROOT, "Assets.xcassets")


def write_png(path, width, height, pixel_fn):
    raw = bytearray()
    for y in range(height):
        raw.append(0)  # filter: none
        row = bytearray()
        for x in range(width):
            r, g, b, a = pixel_fn(x, y)
            row += bytes((r, g, b, a))
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
    print("wrote", path)


def star_polygon(cx, cy, outer, inner, points=5):
    poly = []
    for i in range(points * 2):
        angle = -math.pi / 2 + i * math.pi / points
        radius = outer if i % 2 == 0 else inner
        poly.append((cx + radius * math.cos(angle), cy + radius * math.sin(angle)))
    return poly


def point_in_polygon(x, y, poly):
    inside = False
    j = len(poly) - 1
    for i in range(len(poly)):
        xi, yi = poly[i]
        xj, yj = poly[j]
        if (yi > y) != (yj > y):
            if x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                inside = not inside
        j = i
    return inside


def make_app_icon(path, size=1024):
    cx = cy = size / 2.0
    outer = size * 0.40
    poly = star_polygon(cx, cy, outer, outer * 0.40)
    bg = (0xFF, 0x6D, 0x00, 255)
    fg = (0xFF, 0xFF, 0xFF, 255)

    def pixel(x, y):
        # subtle vertical gradient on the background
        t = y / float(size)
        base = (0xFF, int(0x6D + (0x9A - 0x6D) * (1 - t)), int(0x00 + (0x2E) * (1 - t)), 255)
        if point_in_polygon(x + 0.5, y + 0.5, poly):
            return fg
        return base

    write_png(path, size, size, pixel)


def make_sample_proof(path, width=1200, height=1600):
    sun_cx, sun_cy, sun_r = width * 0.5, height * 0.30, width * 0.16
    ground_y = height * 0.72

    def pixel(x, y):
        t = y / float(height)
        if y > ground_y:
            g = (1 - t) * 0.35
            return (int(0x2E + 60 * (1 - g)), int(0x6B + 90 * (1 - g)), int(0x3A + 60 * (1 - g)), 255)
        r = (1 - t) * 255
        g = (1 - t) * 180
        b = 120 + (1 - t) * 120
        dx, dy = x - sun_cx, y - sun_cy
        if dx * dx + dy * dy <= sun_r * sun_r:
            return (0xFF, 0xE5, 0x8A, 255)
        return (int(min(r, 255)), int(min(g, 255)), int(min(b, 255)), 255)

    write_png(path, width, height, pixel)


def main():
    os.makedirs(os.path.join(ASSETS, "AccentColor.colorset"), exist_ok=True)
    os.makedirs(os.path.join(ASSETS, "AppIcon.appiconset"), exist_ok=True)
    make_app_icon(os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon-1024.png"))
    make_sample_proof(os.path.join(ROOT, "SampleProof.png"))


if __name__ == "__main__":
    main()
