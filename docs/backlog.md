# Backlog

Things decided but not yet built. Newest first. Anything here is a real
request, not a maybe. If something turns out to be a bad idea, delete it and
say why rather than leaving it to rot.

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
