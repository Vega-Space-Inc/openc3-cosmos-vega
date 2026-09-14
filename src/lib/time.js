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

// Time-zone helpers: calendar days and clock labels in the COSMOS
// 'time_zone' setting ('local', 'UTC', or an IANA name).

// --- Time zone ---
// The chart follows the COSMOS 'time_zone' setting (Admin / Settings), the
// same one the top-bar clock uses: 'local' (the browser's zone), 'UTC', or
// an IANA zone name. Days are that zone's calendar days (midnight to
// midnight there), and every label is rendered in it. Vega's API is queried
// by UTC date, so a display day is stitched from the one or two UTC days
// that overlap it (see utcFetchDays).
export const partsFormatters = {}
export function zoneParts(ms, tz) {
  const key = tz || 'local'
  let fmt = partsFormatters[key]
  if (!fmt) {
    fmt = new Intl.DateTimeFormat('en-US', {
      timeZone: key === 'local' ? undefined : key,
      hourCycle: 'h23',
      year: 'numeric',
      month: 'numeric',
      day: 'numeric',
      hour: 'numeric',
      minute: 'numeric',
      weekday: 'short',
    })
    partsFormatters[key] = fmt
  }
  const p = {}
  for (const part of fmt.formatToParts(new Date(ms))) p[part.type] = part.value
  return {
    y: Number(p.year),
    m: Number(p.month) - 1,
    d: Number(p.day),
    hh: Number(p.hour) % 24,
    mm: Number(p.minute),
    wd: String(p.weekday).slice(0, 3).toUpperCase(),
  }
}
// Minutes the zone is ahead of UTC at the given instant.
export function zoneOffsetMin(ms, tz) {
  const p = zoneParts(ms, tz)
  return (
    (Date.UTC(p.y, p.m, p.d, p.hh, p.mm) - Math.floor(ms / 60000) * 60000) /
    60000
  )
}
// Epoch ms of midnight on the zone's calendar day (y, m, d). Two passes so
// a DST change between the guess and the answer is absorbed.
export function zoneMidnightMs(y, m, d, tz) {
  const guess = Date.UTC(y, m, d)
  const first = guess - zoneOffsetMin(guess, tz) * 60000
  return guess - zoneOffsetMin(first, tz) * 60000
}

export function pad2(n) {
  return String(n).padStart(2, '0')
}
