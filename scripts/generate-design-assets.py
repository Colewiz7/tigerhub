#!/usr/bin/env python3
"""Generate TigerHub's deterministic SVG design assets without dependencies."""

from pathlib import Path

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


def wordmarks() -> None:
    # Three uneven horizontal brush marks. Their different lengths and curves
    # keep them from reading as either a barcode or a strikethrough. The top
    # and bottom marks die inside the word instead of crossing every letter.
    stripe_paths = '''
    <path d="M7 15 C24 10 38 17 54 14 C69 11 82 9 96 13 C86 16 74 19 60 18 C41 21 26 15 8 20Z"/>
    <path d="M30 28 C48 23 67 31 84 27 C99 23 112 25 123 30 C110 31 99 34 85 33 C66 37 49 29 31 34Z"/>
    <path d="M8 41 C24 36 39 44 53 40 C62 38 70 38 78 42 C69 45 60 47 51 46 C35 49 23 42 9 47Z"/>'''

    def body(size: int, baseline: int, hub_x: int, scale: float = 1.0) -> str:
        defs = f'''  <defs>
    <clipPath id="tiger-word" clipPathUnits="userSpaceOnUse"><text x="4" y="{baseline}" font-family="Space Grotesk, Rubik, sans-serif" font-size="{size}" font-weight="700">Tiger</text></clipPath>
  </defs>'''
        transform = '' if scale == 1 else f' transform="scale({scale})"'
        return f'''{defs}
  <text x="4" y="{baseline}" fill="#F76902" font-family="Space Grotesk, Rubik, sans-serif" font-size="{size}" font-weight="700">Tiger</text>
  <g clip-path="url(#tiger-word)" fill="#512B20"{transform}>{stripe_paths}
  </g>
  <text x="{hub_x}" y="{baseline}" fill="currentColor" font-family="Space Grotesk, Rubik, sans-serif" font-size="{size}" font-weight="700">Hub</text>'''

    write("wordmark/tigerhub-wide.svg", svg("0 0 230 60", body(50, 50, 126), label="TigerHub"))
    write("wordmark/tigerhub-compact.svg", svg("0 0 184 48", body(40, 40, 102, .8), label="TigerHub"))

    # In monochrome the same marks knock transparent channels out of Tiger,
    # while Hub and the remaining letterforms follow currentColor.
    mono = f'''  <defs>
    <mask id="striped-tiger"><text x="4" y="50" fill="white" font-family="Space Grotesk, Rubik, sans-serif" font-size="50" font-weight="700">Tiger</text><g fill="black">{stripe_paths}</g></mask>
  </defs>
  <rect x="4" y="7" width="120" height="45" fill="currentColor" mask="url(#striped-tiger)"/>
  <text x="126" y="50" fill="currentColor" font-family="Space Grotesk, Rubik, sans-serif" font-size="50" font-weight="700">Hub</text>'''
    write("wordmark/tigerhub-monochrome.svg", svg("0 0 230 60", mono, label="TigerHub"))


def post_office_mockups() -> None:
    themes = {
        "light": ("#FFF8F5", "#FFF1E8", "#FFE4D3", "#2B1710", "#76584A", "#F76902", "#512B20"),
        "dark": ("#1B110E", "#261814", "#35231C", "#FFEDE5", "#CDB1A4", "#F76902", "#512B20"),
    }
    mailbox = '<path d="M4 10h11a4 4 0 0 1 4 4v7H4a2 2 0 0 1-2-2v-7a2 2 0 0 1 2-2Z"/><path d="M8 10v11M19 14h3v5M14 6h5v4M14 6v8"/>'
    for mode, (bg, card, module, ink, muted, orange, stripe) in themes.items():
        body = f'''  <rect width="1440" height="900" fill="{bg}"/>
  <text x="96" y="104" fill="{ink}" font-family="Rubik, sans-serif" font-size="42" font-weight="650">Post offices</text>
  <text x="96" y="142" fill="{muted}" font-family="Rubik, sans-serif" font-size="20">Global Village Post Office · Fall semester</text>
  <rect x="72" y="182" width="1296" height="630" rx="34" fill="{card}"/>
  <g transform="translate(112 222) scale(1.5)" fill="none" stroke="{orange}" stroke-width="1.75" stroke-linecap="round" stroke-linejoin="round">{mailbox}</g>
  <text x="166" y="254" fill="{ink}" font-family="Rubik, sans-serif" font-size="28" font-weight="650">Global Village Post Office</text>
  <text x="112" y="306" fill="{muted}" font-family="Rubik, sans-serif" font-size="19">4000 Global Village Plaza · Rochester, NY 14623</text>
  <path d="M112 345 C230 326 338 362 456 343 C571 325 677 359 790 341" fill="none" stroke="{orange}" stroke-width="4" stroke-linecap="round" stroke-dasharray="2 14"/>
  <rect x="112" y="382" width="570" height="344" rx="28" fill="{module}"/>
  <rect x="714" y="382" width="570" height="344" rx="28" fill="{module}"/>
  <rect x="142" y="410" width="8" height="288" rx="4" fill="{orange}"/>
  <rect x="744" y="410" width="8" height="288" rx="4" fill="{orange}"/>
  <text x="174" y="438" fill="{ink}" font-family="Rubik, sans-serif" font-size="24" font-weight="650">Package pickup</text>
  <text x="650" y="438" text-anchor="end" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.5">FALL</text>
  <text x="174" y="488" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.8">MON TO FRI</text>
  <text x="397" y="565" text-anchor="middle" fill="{ink}" font-family="Rubik, sans-serif" font-size="45" font-weight="500">10:00 AM – 1:00 PM</text>
  <path d="M366 594 C387 586 406 602 427 593" fill="none" stroke="{stripe}" stroke-width="5" stroke-linecap="round"/>
  <text x="397" y="650" text-anchor="middle" fill="{ink}" font-family="Rubik, sans-serif" font-size="45" font-weight="500">2:00 PM – 4:30 PM</text>
  <text x="776" y="438" fill="{ink}" font-family="Rubik, sans-serif" font-size="24" font-weight="650">Shipping window</text>
  <text x="1252" y="438" text-anchor="end" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.5">FALL</text>
  <text x="776" y="488" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.8">MON TO FRI</text>
  <text x="999" y="594" text-anchor="middle" fill="{ink}" font-family="Rubik, sans-serif" font-size="45" font-weight="500">10:00 AM – 4:00 PM</text>
  <text x="776" y="680" fill="{muted}" font-family="Rubik, sans-serif" font-size="17">Closed Saturday and Sunday</text>'''
        write(f"mockups/post-office-hours-{mode}.svg", svg("0 0 1440 900", body, label=f"post office hours {mode} mockup"))


def dashboard_mockups() -> None:
    themes = {
        "light": ("#FFF8F5", "#FFF1E8", "#FFE4D3", "#2B1710", "#76584A", "#F76902"),
        "dark": ("#1B110E", "#261814", "#35231C", "#FFEDE5", "#CDB1A4", "#F76902"),
    }
    for mode, (bg, card, raised, ink, muted, orange) in themes.items():
        body = f'''  <rect width="1440" height="900" fill="{bg}"/>
  <text x="72" y="76" fill="{ink}" font-family="Rubik, sans-serif" font-size="38" font-weight="650">Customize Today</text>
  <text x="72" y="112" fill="{muted}" font-family="Rubik, sans-serif" font-size="19">Cards are instances. Choose their scope, size and order.</text>
  <rect x="1040" y="54" width="328" height="62" rx="31" fill="{orange}"/>
  <text x="1204" y="93" text-anchor="middle" fill="#2B1710" font-family="Rubik, sans-serif" font-size="19" font-weight="650">+ ADD CARD</text>
  <rect x="72" y="154" width="826" height="674" rx="32" fill="{card}"/>
  <text x="102" y="202" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.8">DASHBOARD PREVIEW</text>
  <rect x="102" y="230" width="372" height="260" rx="28" fill="{raised}"/>
  <circle cx="136" cy="267" r="11" fill="{orange}"/><text x="160" y="276" fill="{ink}" font-family="Rubik, sans-serif" font-size="25" font-weight="650">Dining</text>
  <text x="132" y="330" fill="{orange}" font-family="Rubik, sans-serif" font-size="66" font-weight="550">6</text><text x="132" y="362" fill="{muted}" font-family="Rubik, sans-serif" font-size="14" letter-spacing="1.4">OPEN NOW</text>
  <rect x="494" y="230" width="374" height="260" rx="28" fill="{raised}"/>
  <circle cx="528" cy="267" r="11" fill="{orange}"/><text x="552" y="276" fill="{ink}" font-family="Rubik, sans-serif" font-size="25" font-weight="650">Events</text>
  <text x="528" y="318" fill="{muted}" font-family="Rubik, sans-serif" font-size="16">All campus · Today</text>
  <rect x="102" y="510" width="766" height="136" rx="28" fill="{raised}"/>
  <circle cx="136" cy="550" r="11" fill="{orange}"/><text x="160" y="559" fill="{ink}" font-family="Rubik, sans-serif" font-size="25" font-weight="650">Computer Science House events</text>
  <text x="132" y="602" fill="{muted}" font-family="Rubik, sans-serif" font-size="16">Next: Open house · 7:00 PM</text>
  <rect x="102" y="666" width="372" height="132" rx="28" fill="{raised}"/><text x="132" y="716" fill="{ink}" font-family="Rubik, sans-serif" font-size="23" font-weight="650">Calendar</text><text x="132" y="754" fill="{muted}" font-family="Rubik, sans-serif" font-size="16">Week at a glance</text>
  <rect x="494" y="666" width="374" height="132" rx="28" fill="{raised}"/><text x="524" y="716" fill="{ink}" font-family="Rubik, sans-serif" font-size="23" font-weight="650">Mailing address</text><text x="524" y="754" fill="{muted}" font-family="Rubik, sans-serif" font-size="16">Global Village</text>
  <rect x="926" y="154" width="442" height="674" rx="32" fill="{card}"/>
  <text x="962" y="202" fill="{ink}" font-family="Rubik, sans-serif" font-size="26" font-weight="650">Selected card</text>
  <text x="962" y="246" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.6">TYPE</text><text x="962" y="282" fill="{ink}" font-family="Rubik, sans-serif" font-size="20">Events</text>
  <text x="962" y="340" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.6">SCOPE</text>
  <rect x="962" y="360" width="370" height="58" rx="20" fill="{raised}"/><text x="986" y="396" fill="{ink}" font-family="Rubik, sans-serif" font-size="18">Computer Science House</text>
  <text x="962" y="474" fill="{muted}" font-family="Rubik, sans-serif" font-size="15" letter-spacing="1.6">SIZE</text>
  <rect x="962" y="494" width="104" height="52" rx="26" fill="{raised}"/><text x="1014" y="527" text-anchor="middle" fill="{muted}" font-family="Rubik, sans-serif" font-size="16">Compact</text>
  <rect x="1078" y="494" width="112" height="52" rx="26" fill="{orange}"/><text x="1134" y="527" text-anchor="middle" fill="#2B1710" font-family="Rubik, sans-serif" font-size="16" font-weight="650">Standard</text>
  <rect x="1202" y="494" width="104" height="52" rx="26" fill="{raised}"/><text x="1254" y="527" text-anchor="middle" fill="{muted}" font-family="Rubik, sans-serif" font-size="16">Wide</text>
  <text x="962" y="604" fill="{muted}" font-family="Rubik, sans-serif" font-size="16">Wide cards collapse to full width on phones.</text>
  <rect x="962" y="682" width="176" height="58" rx="29" fill="{orange}"/><text x="1050" y="718" text-anchor="middle" fill="#2B1710" font-family="Rubik, sans-serif" font-size="17" font-weight="650">DONE</text>
  <text x="1170" y="718" fill="{muted}" font-family="Rubik, sans-serif" font-size="17">Remove card</text>'''
        write(f"mockups/modular-dashboard-{mode}.svg", svg("0 0 1440 900", body, label=f"modular dashboard {mode} mockup"))


def main() -> None:
    wordmarks()
    post_office_mockups()
    dashboard_mockups()


if __name__ == "__main__":
    main()
