"""Print the TigerHub window geometry, but only if it is safe to capture.

`grim -g` captures whatever is on screen at those coordinates, not the window's
own buffer. If anything is drawn over the app, that is what lands in the file.
This has already put a browser, a lock screen, and a notification panel full of
someone's messages into a capture.

Cropping to the window rules out grabbing the wrong *region*. It does nothing
about something on top of the right region, so this refuses instead:

  * the window must exist and be on the active workspace
  * no other window may overlap it while sitting higher in the stack

Hyprland orders `focusHistoryID` by how recently a window was focused, and 0 is
the current one, so a lower id over the same pixels means that window is in
front. That is the check that catches a terminal or a browser sitting on top.

Compositor overlays (notification drawers, bars) are layer-shell surfaces that
never appear in `hyprctl clients` at all, and the ones here are full screen and
permanently mapped, so their geometry says nothing about whether they are
visible. `_capture_check.py` inspects the resulting image for those.

Exits non-zero with a reason on stderr rather than printing geometry.
"""

import json
import sys

CLASS = "dev.colewiz.tigerhub"


def rects_overlap(a, b) -> bool:
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def main() -> int:
    clients = json.load(sys.stdin)

    app = next((c for c in clients if c.get("class") == CLASS), None)
    if app is None:
        print(f"no window with class {CLASS}", file=sys.stderr)
        return 1

    x, y = app["at"]
    width, height = app["size"]
    if width <= 0 or height <= 0:
        print("window has no size yet", file=sys.stderr)
        return 1

    app_rect = (x, y, width, height)
    app_ws = (app.get("workspace") or {}).get("id")
    app_rank = app.get("focusHistoryID", 0)

    blockers = []
    for other in clients:
        if other.get("address") == app.get("address"):
            continue
        if (other.get("workspace") or {}).get("id") != app_ws:
            continue
        if other.get("hidden") or not other.get("mapped", True):
            continue
        ox, oy = other.get("at", (0, 0))
        ow, oh = other.get("size", (0, 0))
        if ow <= 0 or oh <= 0:
            continue
        if not rects_overlap(app_rect, (ox, oy, ow, oh)):
            continue
        # Lower focusHistoryID means more recently focused, so it is in front.
        if other.get("focusHistoryID", 0) < app_rank:
            blockers.append(other.get("class") or other.get("title") or "?")

    if blockers:
        print(
            "refusing to capture: these windows are on top of the app: "
            + ", ".join(sorted(set(blockers))),
            file=sys.stderr,
        )
        return 2

    print(f"{x},{y} {width}x{height}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
