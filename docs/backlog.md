# Backlog

Things decided but not yet built. Newest first. Anything here is a real
request, not a maybe. If something turns out to be a bad idea, delete it and
say why rather than leaving it to rot.

---

## Masthead wordmark: orange on "Tiger", with tiger striping

Requested 2026-08-30.

Currently `_Wordmark` in `client/lib/app_shell.dart` splits the name at the
internal capital and puts `scheme.onSurface` on "Tiger" and `scheme.primary`
on "Hub". **Swap it.** "Tiger" carries the orange, "Hub" is the quiet half.

Then stripe the "Tiger" half like a tiger: dark stripes over the orange, in a
soft near-black rather than pure black, tuned to sit against that orange
without going harsh.

**How to actually do the stripes.** A `TextSpan` cannot carry a pattern, so
this needs one of:

- a `ShaderMask` over just the "Tiger" span with a repeating `LinearGradient`
  of hard stops (orange, dark, orange), angled maybe 12 to 20 degrees off
  vertical. Cheapest, and the stripes stay straight rather than following the
  letterforms;
- or a `CustomPainter` that paints the glyphs and clips the stripe shapes to
  them, which allows tapered stripes that actually look drawn.

Start with the ShaderMask. If the straight stripes read as a barcode rather
than as an animal, escalate to the painter.

**Watch the contrast.** The stripes cut the effective lightness of the orange,
so check the wordmark against both light and dark surfaces before shipping.
CLAUDE.md section 4 says colour is validated, never eyeballed, and a striped
wordmark is exactly the kind of thing that looks fine on the dark theme and
turns to mud on the light one.

Related: [[app-icon]] uses the same tiger idea, so the two should agree.

---

## Mailing address: copy buttons, and a default address that drives the app

Requested 2026-08-30.

**The problem.** Web order forms split an address across several fields, so
having the address as one block means selecting a piece at a time by hand every
single time. That is the annoying part, and it is what the copy buttons are for.

**What it should do:**

- Show the address as its own lines, each line with **its own copy button**, so
  a form asking for street, city, state and ZIP separately can be filled by
  tapping down the list.
- Also a **copy the whole address** button, for the forms that take one blob.
- A button that **changes which address you are looking at**, for when you need
  someone else's area or you are checking a different hall.

**The bigger half: a default address set during first run setup.**

- First launch asks where you live, once, and that becomes the default.
- The address screen then opens on your address instead of asking every time.
- That default is not only for mail. It is a **location anchor**, and other
  parts of the app should use it: ordering dining locations by proximity, and
  anything else where "nearest to me" beats alphabetical.

**Note for whoever builds it.** The proximity half needs coordinates per housing
area, which the current `housing_areas.json` does not carry, and the zone based
mail model (CLAUDE.md 7.9) means an "address" is an office plus a line 2 format,
not a street address per hall. So the anchor is probably the residence area's
own location, not the post office's. Check that before designing the sort.
