#!/usr/bin/env python3
"""Generate TigerHub's deterministic SVG design assets without dependencies."""

from pathlib import Path
from math import cos, pi, sin

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "generated"


def write(relative: str, body: str) -> None:
    target = OUT / relative
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(body.strip() + "\n")


def svg(viewbox: str, body: str, *, label: str) -> str:
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="{viewbox}" role="img" aria-label="{label}">
{body}
</svg>'''


def scallop(cx: float, cy: float, radius: float) -> str:
    points = []
    for i in range(14):
        angle = -pi / 2 + i * pi / 7
        r = radius if i % 2 == 0 else radius * 0.93
        points.append((cx + cos(angle) * r, cy + sin(angle) * r))
    # Quadratic mid-point smoothing makes the alternating radii read as lobes.
    mids = [((points[i][0] + points[(i + 1) % 14][0]) / 2,
             (points[i][1] + points[(i + 1) % 14][1]) / 2) for i in range(14)]
    path = f"M {mids[-1][0]:.2f} {mids[-1][1]:.2f} "
    for point, mid in zip(points, mids):
        path += f"Q {point[0]:.2f} {point[1]:.2f} {mid[0]:.2f} {mid[1]:.2f} "
    return path + "Z"


def wordmarks() -> None:
    defs = '''  <defs>
    <clipPath id="tiger-word" clipPathUnits="userSpaceOnUse"><text x="4" y="50" font-family="Space Grotesk, Rubik, sans-serif" font-size="50" font-weight="700">Tiger</text></clipPath>
  </defs>'''
    stripes = '''  <g clip-path="url(#tiger-word)" fill="#512B20">
    <path d="M38 -4 C45 11 46 27 39 42 L51 44 C58 25 55 7 49 -5Z"/>
    <path d="M92 -4 C99 12 99 25 92 39 L104 43 C112 24 109 7 103 -5Z"/>
    <path d="M145 -4 C151 10 151 22 145 35 L157 38 C164 21 161 5 156 -5Z"/>
  </g>'''
    body = f'''{defs}
  <text x="4" y="50" fill="#F76902" font-family="Space Grotesk, Rubik, sans-serif" font-size="50" font-weight="700">Tiger</text>
{stripes}
  <text x="126" y="50" fill="currentColor" font-family="Space Grotesk, Rubik, sans-serif" font-size="50" font-weight="700">Hub</text>'''
    write("wordmark/tigerhub-wide.svg", svg("0 0 230 60", body, label="TigerHub"))
    write("wordmark/tigerhub-compact.svg", svg("0 0 184 48", body.replace('font-size="50"', 'font-size="40"').replace('y="50"', 'y="40"').replace('x="126"', 'x="102"'), label="TigerHub"))
    mono = '<text x="4" y="50" fill="currentColor" font-family="Space Grotesk, Rubik, sans-serif" font-size="50" font-weight="700">TigerHub</text>'
    write("wordmark/tigerhub-monochrome.svg", svg("0 0 230 60", mono, label="TigerHub"))


GLYPHS = {
    "dining": '<path d="M6 3v8M4 3v5a2 2 0 0 0 4 0V3M6 11v10M15 3v18M15 3c4 2 5 7 0 10"/>',
    "events": '<rect x="3" y="5" width="18" height="16" rx="4"/><path d="M7 3v4M17 3v4M3 10h18M8 14h.01M12 14h.01M16 14h.01"/>',
    "calendar": '<rect x="2.5" y="3.5" width="19" height="18" rx="4"/><path d="M7 2v4M17 2v4M3 9h18M7 13h2M11 13h2M15 13h2M7 17h2M11 17h2M15 17h2"/>',
    "housing": '<path d="M3 10 12 3l9 7v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/><path d="M7 13h10v6H7zM8 13l4 3 4-3"/>',
    "post-office": '<path d="M4 10h11a4 4 0 0 1 4 4v7H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z"/><path d="M8 10v11M19 14h3v5M14 6h5v4M14 6v8"/>',
    "makerspace": '<path d="M5 4h14v5H5zM8 9v4l4 3 4-3V9M12 16v5M8 21h8"/><circle cx="12" cy="12" r="1"/>',
    "buildings": '<path d="M3 21V9l9-6 9 6v12M2 21h20M7 11h3v3H7zM14 11h3v3h-3zM10 21v-4h4v4"/>',
    "market": '<path d="M3 5h2l2.2 10h10.9l2-7H6M9 11h9M9 20h.01M17 20h.01"/>',
    "visiting-chef": '<path d="M7 10a4 4 0 1 1 2-7 4 4 0 0 1 6 0 4 4 0 1 1 2 7Z"/><path d="M7 10v8h10v-8M9 14h6M9 18v3M15 18v3"/>',
}


def glyphs() -> None:
    symbols = []
    for name, paths in GLYPHS.items():
        group = f'<g fill="none" stroke="currentColor" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">{paths}</g>'
        write(f"glyphs/{name}.svg", svg("0 0 24 24", "  " + group, label=name.replace("-", " ")))
        symbols.append(f'  <symbol id="{name}" viewBox="0 0 24 24">{group}</symbol>')
    write("glyphs/section-glyphs.svg", svg("0 0 24 24", "\n".join(symbols), label="TigerHub section glyph sprite"))


EMPTY_PROPS = {
    "no-events": '<rect x="100" y="48" width="68" height="62" rx="16"/><path d="M114 42v14M153 42v14M101 67h66M121 82h26"/>',
    "all-closed": '<circle cx="134" cy="76" r="34"/><path d="M134 56v22l15 10M111 108l46-64"/>',
    "offline": '<path d="M104 88c18-20 42-20 60 0M114 100c12-12 28-12 40 0M129 112a7 7 0 0 1 10 0M106 45l56 72"/>',
    "source-down": '<path d="M105 55h58v50h-58zM116 68h36M116 81h28M116 94h18M99 111h70"/>',
    "not-found": '<circle cx="132" cy="76" r="30"/><path d="m154 98 22 22M120 76h24"/>',
    "no-visiting-chefs": '<path d="M103 91h66M111 91a25 25 0 0 1 50 0M130 60v-9M101 103h70"/>',
}


def empty_states() -> None:
    tiger = '''  <g stroke="#512B20" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">
    <path fill="#F76902" d="M23 104V72c0-23 18-41 41-41h13c19 0 35 15 35 35v42H40c-9 0-17-2-17-4Z"/>
    <path fill="#F76902" d="M31 45 24 24l25 11M91 37l19-15-2 27"/>
    <path fill="#FFF1DE" d="M55 76c12-12 31-10 39 3v25H49c-2-11 0-20 6-28Z"/>
    <path fill="none" d="M50 54h1M84 54h1M63 71c5 4 10 4 15 0M51 39v10M82 38v10M35 66l14 2"/>
    <path fill="#F76902" d="M41 101c-10 0-18 7-18 17h34c0-10-6-17-16-17ZM92 101c-10 0-17 7-17 17h34c0-10-7-17-17-17Z"/>
  </g>'''
    for name, prop in EMPTY_PROPS.items():
        body = f'''{tiger}
  <g fill="none" stroke="#512B20" stroke-width="5" stroke-linecap="round" stroke-linejoin="round">{prop}</g>'''
        write(f"empty-states/{name}.svg", svg("0 0 200 140", body, label=name.replace("-", " ")))


def dining() -> None:
    themes = {
        "light": ("#FFF8F3", "#F1D9CA", "#E4B99E"),
        "dark": ("#241A17", "#51372D", "#77513E"),
    }
    for theme, (background, badge, line) in themes.items():
        for ratio, width, height in (("16x9", 1600, 900), ("4x3", 1200, 900)):
            badge_path = scallop(width * 0.76, height * 0.50, height * 0.52)
            body = f'''  <rect width="{width}" height="{height}" fill="{background}"/>
  <path d="{badge_path}" fill="{badge}"/>
  <g fill="none" stroke="{line}" stroke-width="{height * .045:.0f}" stroke-linecap="round">
    <path d="M {width*.08:.0f} {height*.38:.0f} H {width*.49:.0f}"/>
    <path d="M {width*.08:.0f} {height*.50:.0f} H {width*.41:.0f}"/>
    <path d="M {width*.08:.0f} {height*.62:.0f} H {width*.46:.0f}"/>
  </g>'''
            write(f"dining-placeholder/dining-placeholder-{ratio}-{theme}.svg", svg(f"0 0 {width} {height}", body, label="abstract dining placeholder"))


def main() -> None:
    wordmarks()
    glyphs()
    empty_states()
    dining()


if __name__ == "__main__":
    main()
