#!/usr/bin/env python3
"""Crop a frozen fullscreen screenshot, burn in optional annotations, copy to Wayland clipboard,
optionally save, and send a rich BigPicture preview notification to Quickshell."""

import datetime
import json
import math
import os
import subprocess
import sys
from PIL import Image, ImageDraw, ImageFont


def load_font(px_size):
    candidates = [
        "/usr/share/fonts/TTF/Inter-Bold.ttf",
        "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/noto/NotoSans-Bold.ttf",
        "/usr/share/fonts/Adwaita/AdwaitaSans-Bold.ttf",
        "/usr/share/fonts/liberation/LiberationSans-Bold.ttf",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, max(10, int(round(px_size))))
            except Exception:
                pass
    return ImageFont.load_default()


def contrast_rgba(rgba):
    lum = 0.299 * rgba[0] + 0.587 * rgba[1] + 0.114 * rgba[2]
    return (17, 24, 39, 255) if lum > 155 else (255, 255, 255, 255)


def hex_to_rgba(color_str, alpha=255):
    s = str(color_str or "#EF4444").strip().lstrip("#")
    if len(s) == 6:
        return (int(s[0:2], 16), int(s[2:4], 16), int(s[4:6], 16), alpha)
    if len(s) == 8:
        return (int(s[2:4], 16), int(s[4:6], 16), int(s[6:8], 16), alpha)
    return (239, 68, 68, alpha)


def render_annotations(img, annotations, sx, sy):
    if not annotations:
        return img

    base = img.convert("RGBA")
    scale = (sx + sy) / 2.0

    for item in annotations:
        tool = item.get("tool", "pen")
        color = item.get("color", "#EF4444")
        width = max(1, int(round(float(item.get("width", 4)) * scale)))
        is_hl = tool == "highlighter"
        alpha = 105 if is_hl else 255
        rgba = hex_to_rgba(color, alpha)

        layer = Image.new("RGBA", base.size, (0, 0, 0, 0))
        draw = ImageDraw.Draw(layer)

        if tool in ("pen", "highlighter"):
            pts = item.get("points") or []
            if len(pts) == 1:
                px, py = pts[0][0] * sx, pts[0][1] * sy
                r = max(1, width / 2.0)
                draw.ellipse((px - r, py - r, px + r, py + r), fill=rgba)
            elif len(pts) >= 2:
                scaled = [(p[0] * sx, p[1] * sy) for p in pts]
                draw.line(scaled, fill=rgba, width=width, joint="curve")
                # Round caps on endpoints
                r = width / 2.0
                for px, py in (scaled[0], scaled[-1]):
                    draw.ellipse((px - r, py - r, px + r, py + r), fill=rgba)
        elif tool == "line":
            x1, y1 = float(item.get("x1", 0)) * sx, float(item.get("y1", 0)) * sy
            x2, y2 = float(item.get("x2", 0)) * sx, float(item.get("y2", 0)) * sy
            draw.line([(x1, y1), (x2, y2)], fill=rgba, width=width)
        elif tool == "arrow":
            x1, y1 = float(item.get("x1", 0)) * sx, float(item.get("y1", 0)) * sy
            x2, y2 = float(item.get("x2", 0)) * sx, float(item.get("y2", 0)) * sy
            angle = math.atan2(y2 - y1, x2 - x1)
            head_len = max(14.0 * scale, width * 3.0)
            p2 = (x2 - head_len * math.cos(angle - math.pi / 5.2), y2 - head_len * math.sin(angle - math.pi / 5.2))
            p3 = (x2 - head_len * math.cos(angle + math.pi / 5.2), y2 - head_len * math.sin(angle + math.pi / 5.2))
            draw.line([(x1, y1), (x2, y2)], fill=rgba, width=width)
            draw.line([p2, (x2, y2), p3], fill=rgba, width=width, joint="curve")
            r = width / 2.0
            for px, py in ((x1, y1), (x2, y2), p2, p3):
                draw.ellipse((px - r, py - r, px + r, py + r), fill=rgba)
        elif tool == "text":
            tx = float(item.get("x", 0)) * sx
            ty = float(item.get("y", 0)) * sy
            txt = str(item.get("text") or "")
            if txt:
                fsize = float(item.get("size", 24)) * scale
                font = load_font(fsize)
                draw.text((tx, ty), txt, fill=rgba, font=font)
        elif tool == "number":
            cx = float(item.get("x", 0)) * sx
            cy = float(item.get("y", 0)) * sy
            num = str(item.get("num", 1))
            rad = max(13.0 * scale, float(item.get("radius", 14)) * scale)
            draw.ellipse((cx - rad, cy - rad, cx + rad, cy + rad), fill=rgba)
            font = load_font(rad * 1.15)
            fg = contrast_rgba(rgba)
            draw.text((cx, cy), num, fill=fg, font=font, anchor="mm")
        elif tool == "rect":
            x1, y1 = float(item.get("x1", 0)) * sx, float(item.get("y1", 0)) * sy
            x2, y2 = float(item.get("x2", 0)) * sx, float(item.get("y2", 0)) * sy
            draw.rectangle([min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)], outline=rgba, width=width)
        elif tool == "ellipse":
            x1, y1 = float(item.get("x1", 0)) * sx, float(item.get("y1", 0)) * sy
            x2, y2 = float(item.get("x2", 0)) * sx, float(item.get("y2", 0)) * sy
            draw.ellipse([min(x1, x2), min(y1, y2), max(x1, x2), max(y1, y2)], outline=rgba, width=width)

        base = Image.alpha_composite(base, layer)

    return base.convert("RGB")


def main():
    if len(sys.argv) < 8:
        print("Usage: screenshot-crop.py <src_png> <mode:copy|save> <x> <y> <w> <h> <logical_w> <logical_h> [out_dir] [annotations_json]", file=sys.stderr)
        sys.exit(1)

    src_path = sys.argv[1]
    mode = sys.argv[2]
    rx, ry, rw, rh = float(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
    lw, lh = float(sys.argv[7]), float(sys.argv[8])

    if not os.path.exists(src_path):
        print(f"Source screenshot not found: {src_path}", file=sys.stderr)
        sys.exit(1)

    img = Image.open(src_path)
    pw, ph = img.size
    sx = pw / max(1.0, lw)
    sy = ph / max(1.0, lh)

    # Optional annotations JSON (10th argument)
    if len(sys.argv) >= 11 and sys.argv[10].strip():
        try:
            annotations = json.loads(sys.argv[10])
            if isinstance(annotations, list) and annotations:
                img = render_annotations(img, annotations, sx, sy)
        except Exception as e:
            print(f"Annotation render warning: {e}", file=sys.stderr)

    left = max(0, min(pw - 1, int(round(rx * sx))))
    top = max(0, min(ph - 1, int(round(ry * sy))))
    right = max(left + 1, min(pw, int(round((rx + rw) * sx))))
    bottom = max(top + 1, min(ph, int(round((ry + rh) * sy))))

    cropped = img.crop((left, top, right, bottom))

    if mode == "save":
        raw_dir = sys.argv[9] if len(sys.argv) >= 10 and sys.argv[9].strip() else "~/Pictures/Screenshots"
        out_dir = os.path.expanduser(raw_dir)
        os.makedirs(out_dir, exist_ok=True)
        ts = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
        out_path = os.path.join(out_dir, f"screenshot-{ts}.png")
    else:
        out_path = "/tmp/expressive-shot-clipboard.png"

    cropped.save(out_path, "PNG")

    # Copy PNG to Wayland clipboard if wl-copy is available
    try:
        with open(out_path, "rb") as f:
            subprocess.run(["wl-copy", "-t", "image/png"], stdin=f, check=False)
    except FileNotFoundError:
        pass

    # Fire a rich Quickshell notification with the screenshot BigPicture preview
    summary = "Screenshot saved" if mode == "save" else "Screenshot copied"
    body = f"{right - left} × {bottom - top} · {os.path.basename(out_path)}" if mode == "save" else f"{right - left} × {bottom - top} copied to clipboard"
    payload = json.dumps({
        "appName": "Screenshot",
        "appIcon": "applets-screenshooter",
        "attachmentImage": out_path,
        "summary": summary,
        "body": body,
    })
    subprocess.run(["qs", "ipc", "call", "shell", "pushMockNotification", payload], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


if __name__ == "__main__":
    main()
