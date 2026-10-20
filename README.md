# TigerHub

Campus info app for RIT. Dining hours, events, SHED equipment availability, post office hours and campus mail in one place. Built with Flutter, with no server: the app reads RIT's public endpoints on the device and keeps working offline.

<p>
  <img src="screenshots/dashboard.webp" alt="Today dashboard with dining and events" width="280">
  <img src="screenshots/map.webp" alt="Campus map with building categories" width="280">
</p>

Not affiliated with or endorsed by RIT. Only public endpoints are contacted, and no credentials are stored.

## Run it

```sh
scripts/dev build     # linux release build
scripts/dev app       # launch it
scripts/dev test      # analyze and test
scripts/dev package   # single-file AppImage
```

Targets are Linux, Android and iOS. Web is not supported, since most upstreams send no CORS headers.

## Layout

- `client/` the Flutter app. `lib/data/sources/` has one scraper per upstream.
- `assets/` art and hand-maintained config, each file with a last-verified date.
- `design/` UI tokens.
- `scripts/` dev tooling.
