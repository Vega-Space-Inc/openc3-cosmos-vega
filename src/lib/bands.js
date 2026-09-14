// Copyright 2026 Vega Space, Inc.
// All Rights Reserved.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
// See LICENSE.md for more details.
//
// This file may also be used under the terms of a commercial license
// if purchased from Vega Space, Inc.

// Band identity colours and band-key normalisation.

// History points once keyed counts by the raw FrequencyBand name
// ("S-band"); day_detail and current history use the chart label ("S").
// Accept both.
export function normalizeBandKeys(counts) {
  const out = {}
  for (const [k, v] of Object.entries(counts)) {
    let label = String(k)
      .replace(/[-_ ]?band$/i, '')
      .replace(/_/g, ' ')
      .toUpperCase()
    label = { KU: 'Ku', KA: 'Ka', MMWAVE: 'mmWave' }[label] || label
    out[label] = v
  }
  return out
}

// Identity colour per band - for the band block and the tinted strip
// behind its rows, never for the bars (those keep the severity ramp).
// Hues stay clear of the ramp's green / amber / red.
export const BAND_COLORS = {
  VHF: '#7e57c2',
  UHF: '#42a5f5',
  L: '#26a69a',
  S: '#ec407a',
  C: '#5c6bc0',
  X: '#29b6f6',
  Ku: '#ab47bc',
  Ka: '#78909c',
  mmWave: '#8d6e63',
}
export function bandColor(band) {
  if (BAND_COLORS[band]) return BAND_COLORS[band]
  // Unknown band: a stable hue from its name
  let h = 0
  for (const ch of String(band)) h = (h * 31 + ch.charCodeAt(0)) % 360
  return `hsl(${h}, 55%, 60%)`
}
export function bandTint(band, alpha) {
  const c = bandColor(band)
  if (c.startsWith('#')) {
    const r = parseInt(c.slice(1, 3), 16)
    const g = parseInt(c.slice(3, 5), 16)
    const b = parseInt(c.slice(5, 7), 16)
    return `rgba(${r}, ${g}, ${b}, ${alpha})`
  }
  return c.replace('hsl(', 'hsla(').replace(')', `, ${alpha})`)
}
