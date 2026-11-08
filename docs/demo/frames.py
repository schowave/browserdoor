"""Writes the SVG frames of the README demo animation (docs/demo.gif).

The scene: a link is clicked in a chat app, the Doorman picker appears at the pointer,
↓ selects the "Client" Zen space, ↩ opens it, and Zen shows the new tab in that space.
Generic names only. Usage: python3 frames.py <output-dir>; prints "<file> <delay>" per frame.
"""

import os
import sys

W, H = 720, 450
FONT = "Helvetica Neue, Helvetica, Arial, sans-serif"
MONO = "Menlo, monospace"
LINK = "github.com/acme/web/pull/42"

# Picker rows: (label, key, icon kind, color)
ROWS = [
    ("Work", "1", "briefcase", "#f29bbb"),
    ("Client", "2", "planet", "#6cbad9"),
    ("Personal", "3", "letter", "#34e895"),
    ("Google Chrome › Work", "4", "chrome", None),
    ("Safari", "5", "safari", None),
]


def ease(t):
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def desktop():
    return f"""
  <defs>
    <linearGradient id="desk" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2f6c7a"/><stop offset="1" stop-color="#1b2f45"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="150%">
      <feDropShadow dx="0" dy="10" stdDeviation="14" flood-color="#000" flood-opacity="0.35"/>
    </filter>
  </defs>
  <rect width="{W}" height="{H}" fill="url(#desk)"/>
  <rect width="{W}" height="22" fill="#000" fill-opacity="0.28"/>
  <text x="14" y="15" font-family="{FONT}" font-size="12" font-weight="600" fill="#fff">Messages</text>
  <g transform="translate({W - 120} 4)">
    <rect x="0" y="1" width="14" height="13" rx="1.5" fill="none" stroke="#fff" stroke-width="1.3"/>
    <path d="M0 1 L6.5 2.9 V12.1 L0 14 Z" fill="#fff"/>
  </g>
  <text x="{W - 14}" y="15" font-family="{FONT}" font-size="12" fill="#fff" text-anchor="end">Mon 9:41</text>"""


def window(x, y, w, h, title):
    return f"""
  <g filter="url(#shadow)">
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#ffffff"/>
  </g>
  <rect x="{x}" y="{y}" width="{w}" height="30" rx="12" fill="#ececee"/>
  <rect x="{x}" y="{y + 18}" width="{w}" height="12" fill="#ececee"/>
  <circle cx="{x + 16}" cy="{y + 15}" r="5.5" fill="#ff5f57"/>
  <circle cx="{x + 34}" cy="{y + 15}" r="5.5" fill="#febc2e"/>
  <circle cx="{x + 52}" cy="{y + 15}" r="5.5" fill="#28c840"/>
  <text x="{x + w / 2}" y="{y + 19}" font-family="{FONT}" font-size="12" font-weight="600" fill="#4a4a4f" text-anchor="middle">{title}</text>"""


def chat_app(link_pressed):
    x, y = 36, 52
    link_fill = "#0a58d0" if not link_pressed else "#073f97"
    return window(x, y, 430, 300, "Team chat") + f"""
  <circle cx="{x + 32}" cy="{y + 66}" r="14" fill="#c9d6e8"/>
  <text x="{x + 32}" y="{y + 71}" font-family="{FONT}" font-size="12" font-weight="600" fill="#3d5170" text-anchor="middle">MK</text>
  <text x="{x + 56}" y="{y + 60}" font-family="{FONT}" font-size="12" font-weight="600" fill="#1d1d1f">Mara</text>
  <text x="{x + 92}" y="{y + 60}" font-family="{FONT}" font-size="11" fill="#8e8e93">9:38</text>
  <rect x="{x + 56}" y="{y + 68}" width="300" height="56" rx="10" fill="#f1f2f5"/>
  <text x="{x + 70}" y="{y + 90}" font-family="{FONT}" font-size="13" fill="#1d1d1f">Can you review the client fix?</text>
  <text x="{x + 70}" y="{y + 111}" font-family="{FONT}" font-size="13" fill="{link_fill}" text-decoration="underline">{LINK}</text>
  <circle cx="{x + 32}" cy="{y + 160}" r="14" fill="#d8ead1"/>
  <text x="{x + 32}" y="{y + 165}" font-family="{FONT}" font-size="12" font-weight="600" fill="#3f6b35" text-anchor="middle">JS</text>
  <text x="{x + 56}" y="{y + 154}" font-family="{FONT}" font-size="12" font-weight="600" fill="#1d1d1f">Jonas</text>
  <rect x="{x + 56}" y="{y + 162}" width="190" height="34" rx="10" fill="#f1f2f5"/>
  <text x="{x + 70}" y="{y + 184}" font-family="{FONT}" font-size="13" fill="#1d1d1f">On it after lunch 👍</text>
  <rect x="{x + 16}" y="{y + 252}" width="398" height="32" rx="16" fill="#f1f2f5"/>
  <text x="{x + 32}" y="{y + 273}" font-family="{FONT}" font-size="12" fill="#a1a1a6">Message</text>"""


def icon(kind, color, x, y, s=22):
    r = s / 2
    cx, cy = x + r, y + r
    if kind == "chrome":
        return f"""
    <circle cx="{cx}" cy="{cy}" r="{r}" fill="#db4437"/>
    <path d="M{cx} {cy} L{cx + r * 0.87} {cy - r * 0.5} A{r} {r} 0 0 1 {cx + r * 0.5} {cy + r * 0.87} Z" fill="#f4b400"/>
    <path d="M{cx} {cy} L{cx + r * 0.5} {cy + r * 0.87} A{r} {r} 0 0 1 {cx - r * 0.87} {cy - r * 0.5} Z" fill="#0f9d58"/>
    <circle cx="{cx}" cy="{cy}" r="{r * 0.42}" fill="#4285f4" stroke="#fff" stroke-width="1.4"/>"""
    if kind == "safari":
        return f"""
    <circle cx="{cx}" cy="{cy}" r="{r}" fill="#1e90ff"/>
    <circle cx="{cx}" cy="{cy}" r="{r * 0.82}" fill="#fff"/>
    <path d="M{cx} {cy - r * 0.65} L{cx + r * 0.22} {cy} L{cx} {cy + r * 0.65} L{cx - r * 0.22} {cy} Z" fill="#ff3b30" transform="rotate(45 {cx} {cy})"/>"""
    base = f'<rect x="{x}" y="{y}" width="{s}" height="{s}" rx="6" fill="{color}"/>'
    ink = 'fill="#1d1d1f" fill-opacity="0.75"'
    if kind == "briefcase":
        return base + f'<path d="M{x + 5} {y + 9}h{s - 10}v8h-{s - 10}z M{x + 8} {y + 6}h{s - 16}v3h-{s - 16}z" {ink}/>'
    if kind == "planet":
        return base + (f'<circle cx="{cx}" cy="{cy}" r="5" {ink}/>'
                       f'<ellipse cx="{cx}" cy="{cy}" rx="8.5" ry="2.6" fill="none" stroke="#1d1d1f" stroke-opacity="0.75" stroke-width="1.3"/>')
    return base + f'<text x="{cx}" y="{cy + 4.5}" font-family="{FONT}" font-size="12" font-weight="700" {ink} text-anchor="middle">P</text>'


def picker(x, y, selected, opacity):
    w, row_h = 270, 32
    h = 50 + row_h * len(ROWS) + 10
    rows = ""
    for i, (label, key, kind, color) in enumerate(ROWS):
        ry = y + 52 + i * row_h
        if i == selected:
            rows += f'<rect x="{x + 7}" y="{ry - 2}" width="{w - 14}" height="{row_h - 2}" rx="7" fill="#0a84ff" fill-opacity="0.22"/>'
        rows += icon(kind, color, x + 15, ry + 2)
        rows += f'<text x="{x + 47}" y="{ry + 18}" font-family="{FONT}" font-size="13" fill="#1d1d1f">{label}</text>'
        rows += f'<rect x="{x + w - 34}" y="{ry + 4}" width="18" height="18" rx="4" fill="#e5e5ea"/>'
        rows += f'<text x="{x + w - 25}" y="{ry + 17}" font-family="{MONO}" font-size="11" fill="#6e6e73" text-anchor="middle">{key}</text>'
    return f"""
  <g opacity="{opacity:.3f}">
    <g filter="url(#shadow)"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="13" fill="#f7f7f8"/></g>
    <rect x="{x}" y="{y}" width="{w}" height="{h}" rx="13" fill="none" stroke="#d6d6db"/>
    <text x="{x + 15}" y="{y + 27}" font-family="{FONT}" font-size="12" fill="#6e6e73">{LINK}</text>
    <rect x="{x + w - 30}" y="{y + 14}" width="13" height="15" rx="3" fill="none" stroke="#8e8e93" stroke-width="1.3"/>
    <line x1="{x + 10}" y1="{y + 40}" x2="{x + w - 10}" y2="{y + 40}" stroke="#e3e3e8"/>
    {rows}
  </g>"""


def zen(opacity, slide):
    x, y = 250 + slide, 78
    w, h = 440, 330
    spaces = [("briefcase", "#f29bbb"), ("planet", "#6cbad9"), ("letter", "#34e895")]
    side = ""
    for i, (kind, color) in enumerate(spaces):
        ix = x + 20 + i * 36
        if i == 1:
            side += f'<rect x="{ix - 4}" y="{y + 44}" width="30" height="30" rx="8" fill="#6cbad9" fill-opacity="0.35"/>'
        side += icon(kind, color, ix, y + 48)
    tabs = [("Inbox · Client", False), ("Sprint board", False), ("Pull Request #42 · acme/web", True)]
    tab_svg = ""
    for i, (title, active) in enumerate(tabs):
        ty = y + 92 + i * 34
        if active:
            tab_svg += f'<rect x="{x + 12}" y="{ty}" width="128" height="28" rx="7" fill="#ffffff" fill-opacity="0.85"/>'
        tab_svg += f'<circle cx="{x + 28}" cy="{ty + 14}" r="6" fill="{"#1d1d1f" if active else "#7a8794"}" fill-opacity="0.6"/>'
        weight = "600" if active else "400"
        tab_svg += (f'<text x="{x + 40}" y="{ty + 18}" font-family="{FONT}" font-size="11" font-weight="{weight}" fill="#1d1d1f">'
                    f'{title[:18] + "…" if len(title) > 19 else title}</text>')
    content = "".join(
        f'<rect x="{x + 172}" y="{y + 108 + i * 22}" width="{[220, 180, 240, 150, 200, 120][i]}" height="9" rx="4.5" fill="#e6e8ec"/>'
        for i in range(6)
    )
    return f"""
  <g opacity="{opacity:.3f}">
    <g filter="url(#shadow)"><rect x="{x}" y="{y}" width="{w}" height="{h}" rx="12" fill="#dfe9ef"/></g>
    <circle cx="{x + 16}" cy="{y + 15}" r="5.5" fill="#ff5f57"/>
    <circle cx="{x + 34}" cy="{y + 15}" r="5.5" fill="#febc2e"/>
    <circle cx="{x + 52}" cy="{y + 15}" r="5.5" fill="#28c840"/>
    {side}
    <text x="{x + 20}" y="{y + 132 - 46}" font-family="{FONT}" font-size="11" font-weight="700" fill="#2d5a6b" letter-spacing="0.6">CLIENT</text>
    {tab_svg}
    <rect x="{x + 152}" y="{y + 10}" width="{w - 162}" height="{h - 20}" rx="9" fill="#ffffff"/>
    <rect x="{x + 166}" y="{y + 22}" width="{w - 190}" height="22" rx="11" fill="#f1f2f5"/>
    <text x="{x + 180}" y="{y + 37}" font-family="{FONT}" font-size="11" fill="#6e6e73">{LINK}</text>
    <text x="{x + 172}" y="{y + 82}" font-family="{FONT}" font-size="15" font-weight="700" fill="#1d1d1f">Fix client login redirect #42</text>
    {content}
  </g>"""


def pointer(x, y, pressed):
    scale = 0.86 if pressed else 1.0
    return f"""
  <g transform="translate({x} {y}) scale({scale})">
    <path d="M0 0 L0 18 L4.6 13.8 L7.6 20.4 L10.2 19.2 L7.3 12.7 L13 12.5 Z" fill="#000" stroke="#fff" stroke-width="1.2" stroke-linejoin="round"/>
  </g>"""


def keycap(label, opacity):
    x, y = W - 92, H - 70
    return f"""
  <g opacity="{opacity:.3f}">
    <rect x="{x}" y="{y}" width="64" height="46" rx="10" fill="#1d1d1f" fill-opacity="0.82"/>
    <text x="{x + 32}" y="{y + 31}" font-family="{FONT}" font-size="22" font-weight="600" fill="#fff" text-anchor="middle">{label}</text>
  </g>"""


def frame(t):
    """Scene state at time t (seconds)."""
    link = (36 + 70 + 100, 52 + 111 - 5)  # a point on the link text
    start = (620, 400)
    parts = [desktop(), chat_app(link_pressed=1.6 <= t < 1.9)]

    # Pointer: glide to the link, click.
    p = ease((t - 0.2) / 1.3)
    px, py = lerp(start[0], link[0], p), lerp(start[1], link[1], p)

    picker_on = 1.9 <= t < 4.7
    picker_opacity = min(1.0, (t - 1.9) / 0.15) if picker_on else 0.0
    if 4.5 <= t < 4.7:
        picker_opacity = max(0.0, (4.7 - t) / 0.2)
    selected = 0 if t < 3.0 else 1
    if picker_opacity > 0:
        parts.append(picker(link[0] - 20, link[1] + 12, selected, picker_opacity))

    if 2.8 <= t < 3.6:
        parts.append(keycap("↓", min(1.0, (t - 2.8) / 0.1, (3.6 - t) / 0.15)))
    if 3.9 <= t < 4.7:
        parts.append(keycap("↩", min(1.0, (t - 3.9) / 0.1, (4.7 - t) / 0.15)))

    if t >= 4.7:
        z = ease((t - 4.7) / 0.5)
        parts.append(zen(z, (1 - z) * 40))

    if t < 4.7:
        parts.append(pointer(px, py, pressed=1.6 <= t < 1.9))
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{"".join(parts)}</svg>'


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    fps = 12
    duration = 7.4
    hold_end = 2.0  # last frame stays longer before the loop restarts
    n = int(duration * fps)
    for i in range(n):
        t = i / fps
        path = os.path.join(out, f"frame-{i:03d}.svg")
        with open(path, "w", encoding="utf-8") as f:
            f.write(frame(t))
        delay = 1 / fps + (hold_end if i == n - 1 else 0)
        print(f"{path} {delay:.3f}")


if __name__ == "__main__":
    main()
