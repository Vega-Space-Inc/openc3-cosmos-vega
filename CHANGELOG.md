# Changelog

## Unreleased

### Widget
- Roomier grid: station rows 40px (52px single-station), 10px between a
  band's rows, 32px between bands, 14px between pass boxes.

## 0.48.0 - 2026-09-10

The timeline widget rebuilt as a pass-by-band grid, with demo mode and an
onboarding tour.

### Widget
- Per-minute bars coloured on a continuous low-to-high ramp, relative to
  each band's peak; clear minutes keep a stub bar; no-reading minutes draw
  nothing (backed by null-vs-0 counts from Vega).
- One box per pass, hugging the minutes the station actually has; hover
  highlights the cell, click opens it, drag zooms.
- Several ground stations at once: every band becomes a group of rows,
  one per station, on a shared axis compressed on the union of coverage.
- Band identity colours for the band blocks and strips; bands multi-select
  (all on by default); Yesterday / Today / Tomorrow + calendar day picker;
  12h / 24h clock; the chart follows the COSMOS time_zone setting.
- Time labels that never collide: start times at rest, the hovered pass's
  start and end on hover; a live 'now' line with its time on hover.
- Shimmer skeletons while loading; the chart appears whole.
- Demo mode: a fresh install fetches Vega's public read-only demo key and
  shows Demo Org data, with 'Connect your own data' and a key dialog
  (Sign up / Sign in / API keys).
- Onboarding tour (bands, a pass, the pickers, connect your data),
  replayable from the settings menu; ASI Risk Overview rewritten from the
  forecasting technical brief.
- Resize grip (width) remembered per browser; build stamp in the menu.

### Target / interface
- `VegaHttpClientInterface`: recovers from an in-process disconnect (the
  stock HttpClientInterface reconnects into a stale nil and flaps).
- `ApiKeyProtocol` matches the Authorization header case-insensitively
  (the per-request key was never being scrubbed), drops keyless
  authenticated requests instead of collecting 401s, and allows the public
  health and demo-key paths through.
- New `GET_DEMO_KEY` / `DEMO_KEY`; measured history only loads on request.
- No COSMOS limits or state colours on any packet.
- Commands are sent fire-and-forget; read timeout default 90s.

### Commits
- Timeline: drop the row-height experiment's leftovers; history copy no longer promises a 40s wait
- Timeline: key dialog offers Sign up / Sign in, then a small API keys link
- Timeline: 24-hour switch thumb no longer clipped in the menu
- Timeline: tour frames just the band blocks; card body sits lower
- Timeline: tour card is a themed Vuetify card, matching the widget's dialogs
- Timeline: onboarding tour - bands, a pass, the pickers, connect your data
- Timeline: ASI Risk Overview rewritten from the forecasting technical brief
- Timeline: demo-mode settings menu shows only Connect your account and 24-hour time; switch no longer clipped
- Timeline: default to the ISS (then any LEO); hovering the now line shows 'Now · time' and lights the line
- README: packets carry no limits or colours
- Target: no limits or state colours - the chart is the monitoring surface
- Timeline: fetch the demo key before trusting a cached APPROVED_ORGS 200
- Timeline: hovered time shown above the chart; hover and now lines stay inside the grid
- Timeline: demo mode - Vega's public demo key shows data before the user has their own
- Timeline: hovered pass times flank a narrow box instead of stacking; divider ticks hide on hover
- Timeline: pass axis shows start times at rest and the hovered pass's start + end on hover
- Timeline: show/hide no-data bands as a full-width bordered bar; legend divider removed
- Timeline: angled axis hangs start times from the left edge and end times from the right, on two tiers; nothing clipped
- Timeline: angled pass labels when upright ones can't all fit
- Timeline: clock ticks yield to the edge labels by pixel width, not by a time fraction
- Timeline: more air above the time labels; faint hatch inside clear passes
- Timeline: the wide band gap only with several stations; single-station rows stay 5px apart
- Timeline: 8px of clear background between band strips
- Timeline: band strip with equal 8px padding and rounded corners; 4px radius everywhere in the chart
- Timeline: per-pass time labels that fit (range / stacked / start / none), no collisions; 12h/24h setting
- Timeline: bordered Reset zoom; no stub bars in a band with no data
- Timeline: no loading text in the day row - the shimmer says it
- Timeline: Reset zoom as a quiet text action, matching the show/hide bands link; both muted
- Timeline: bands multi-select (all on by default); org switch moves to the settings menu, local only
- Timeline: build stamp in the settings menu
- Timeline: cell outlines and hover backdrop drawn inside the row SVG
- Timeline: Refresh and settings right-aligned on the picker row
- Timeline: identity colour per band for the band block and its strip
- Timeline: expanded row's station name right-aligned above the ticks
- Timeline: band strips only with several stations selected
- Timeline: one tint for every band strip
- Timeline: loading shimmers are the exact size of the controls they cover
- Timeline: last row's bottom outline no longer clipped; outlines stack above the bars
- Timeline: borderless band blocks; alternating band-strip tints in both views
- Timeline: pickers become shimmer blocks while loading
- Timeline: CLEAR note lower in the cell and more muted
- Timeline: label column widens while a row is open so the ticks clear the band block
- Timeline: cell outline as an inset shadow above the bars, so the bottom edge always shows
- Timeline: no title in an expanded row; station name clear of the count ticks
- Timeline: station picker shows two chips then +N, never wraps
- Timeline: pin the selects to 32px so they match the other controls
- Timeline: band header blocks on the left, station names against the tracks
- Timeline: compact 32px controls with 12px type
- Timeline: rows 36px (24px with several stations), 200px expanded
- Timeline: band-group strips run edge to edge
- Timeline: fixed row heights; the resize grip changes width only
- Timeline: rows grow with a resized widget only up to 1.5x their normal height
- Timeline: hide Clear/No data in boxes too narrow for it; a resized widget never clips the rows
- Timeline: shimmer skeleton rows while loading; chart appears whole, no mid-load 'No data'
- Timeline: drop the PASS labels; tinted background behind each band's group of station rows
- Timeline: shorter rows (32px) when several stations are selected
- Timeline: pass boxes hug each station's own coverage
- Timeline: clear minutes keep a stub bar so every observed minute is there to hover
- Timeline: multi-select ground stations - every band gets a row per station
