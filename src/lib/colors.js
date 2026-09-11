// The severity colour ramp for the bars, and the clear-minute stub.

// Colour ramp. Each slice is coloured by its interferer count RELATIVE to
// the band's own peak in the loaded window - green (quiet) through amber to
// red (the band's worst minute) - the same continuous low -> high strip the
// Vega app draws. Relative, not the API's absolute tone thresholds: with
// real traffic every minute clears "high >= 10", which paints the whole day
// one colour and says nothing. The ramp is quantised to RAMP_STEPS colours
// so a lane is at most RAMP_STEPS <path> elements no matter how many
// minutes it holds. Level is also encoded by slice height and spelled out
// in the tooltip, so hue is never the only cue.
export const RAMP_STEPS = 16
export const RAMP_STOPS = [
  [0x43, 0xa0, 0x47], // green
  [0xff, 0xb3, 0x00], // amber
  [0xe5, 0x39, 0x35], // red
]
export function rampColor(level) {
  const t = Math.min(1, Math.max(0, level)) * (RAMP_STOPS.length - 1)
  const i = Math.min(RAMP_STOPS.length - 2, Math.floor(t))
  const f = t - i
  const rgb = RAMP_STOPS[i].map((a, k) =>
    Math.round(a + (RAMP_STOPS[i + 1][k] - a) * f),
  )
  return `rgb(${rgb.join(',')})`
}
export const RAMP_COLORS = Array.from({ length: RAMP_STEPS }, (_, i) =>
  rampColor(i / (RAMP_STEPS - 1)),
)
// A clear minute (analysed, nothing there) still gets a bar: a stub a
// couple of pixels tall in a muted green, so the minute is there to hover
// and the row reads as "observed and clear" rather than "nothing here".
export const CLEAR_STUB_COLOR = 'rgba(67, 160, 71, 0.55)'
export const CLEAR_STUB_H = 0.05 // of CHART_H
export const CLEAR_STEP = RAMP_STEPS // index of the stub path in a row's path list
export const BAR_COLORS = [...RAMP_COLORS, CLEAR_STUB_COLOR]
