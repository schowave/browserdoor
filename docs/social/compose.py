"""Composes the GitHub social preview (1280×640) from the app icon and the picker illustration.

Usage: python3 compose.py <repo-root> <output.svg>
"""

import re
import sys
from pathlib import Path

W, H = 1280, 640
FONT = "Helvetica Neue, Helvetica, Arial, sans-serif"


def inner(svg_text, prefix):
    """The children of an <svg> document, with ids prefixed so documents can be combined."""
    body = re.sub(r"^.*?<svg[^>]*>", "", svg_text, count=1, flags=re.S)
    body = re.sub(r"</svg>\s*$", "", body, flags=re.S)
    body = re.sub(r"<title>.*?</title>", "", body, flags=re.S)
    ids = re.findall(r'id="([^"]+)"', body)
    for old in ids:
        body = body.replace(f'id="{old}"', f'id="{prefix}{old}"')
        body = body.replace(f"url(#{old})", f"url(#{prefix}{old})")
        body = body.replace(f'href="#{old}"', f'href="#{prefix}{old}"')
    return body


def main():
    root = Path(sys.argv[1])
    icon = inner((root / "Resources/Icon/AppIcon.svg").read_text(), "icon-")
    picker = inner((root / "docs/picker.svg").read_text(), "picker-")
    svg = f"""<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#11505e"/><stop offset="1" stop-color="#0a2430"/>
    </linearGradient>
    <radialGradient id="light" cx="0.78" cy="0.55" r="0.45">
      <stop offset="0" stop-color="#ffcf70" stop-opacity="0.22"/><stop offset="1" stop-color="#ffcf70" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="{W}" height="{H}" fill="url(#bg)"/>
  <rect width="{W}" height="{H}" fill="url(#light)"/>

  <g transform="translate(72 96) scale(0.17)">{icon}</g>
  <text x="80" y="346" font-family="Avenir Next, Helvetica Neue, sans-serif" font-size="88" font-weight="700" fill="#ffffff">Browserdoor</text>
  <text x="84" y="404" font-family="{FONT}" font-size="30" fill="#e9f1f2">A link picker for macOS.</text>
  <text x="84" y="456" font-family="{FONT}" font-size="25" fill="#b9d3da">Click a link, then choose the Zen space,</text>
  <text x="84" y="490" font-family="{FONT}" font-size="25" fill="#b9d3da">Chrome or Firefox profile, or browser it opens in.</text>
  <rect x="80" y="530" width="452" height="50" rx="10" fill="#000000" fill-opacity="0.28"/>
  <text x="102" y="563" font-family="Menlo, monospace" font-size="21" fill="#e9f1f2">brew install schowave/tap/browserdoor</text>

  <g transform="translate(700 70) scale(1.32)" font-family="{FONT}">{picker}</g>
</svg>"""
    Path(sys.argv[2]).write_text(svg, encoding="utf-8")


if __name__ == "__main__":
    main()
