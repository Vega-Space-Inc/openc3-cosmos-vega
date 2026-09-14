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

// Per-browser settings kept in localStorage.

export const API_KEY_LS_KEY = 'vega_widget_api_key'
export const SIZE_LS_KEY = 'vega_widget_size'
export const TIME_24H_LS_KEY = 'vega_widget_24h'
export const TOUR_LS_KEY = 'vega_widget_tour_complete'

export function readStoredFlag(key, fallback) {
  try {
    const raw = localStorage.getItem(key)
    return raw === null ? fallback : raw === '1'
  } catch (e) {
    return fallback
  }
}
export function readStoredSize() {
  try {
    const raw = localStorage.getItem(SIZE_LS_KEY)
    if (!raw) return null
    const { w } = JSON.parse(raw)
    return Number.isFinite(w) && w > 0 ? { w } : null
  } catch (e) {
    return null
  }
}

export function readStoredApiKey() {
  try {
    return localStorage.getItem(API_KEY_LS_KEY) || null
  } catch (e) {
    return null // storage blocked (private mode etc.) - key lasts this page only
  }
}
