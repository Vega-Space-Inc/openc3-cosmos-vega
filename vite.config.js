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

import { defineConfig } from 'vite'
import cssInjectedByJsPlugin from 'vite-plugin-css-injected-by-js'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  // Build stamp shown in the widget's settings menu, so a stale cached
  // bundle in the browser is obvious at a glance.
  define: {
    __VEGA_WIDGET_BUILD__: JSON.stringify(
      new Date().toISOString().slice(0, 16).replace('T', ' ') + ' UTC',
    ),
  },
  // public/ belongs to the gem (the store image), not to this build -- without
  // this Vite would copy it into the widget output directory.
  publicDir: false,
  build: {
    outDir: 'tools/widgets/TimelineWidget',
    emptyOutDir: true,
    // COSMOS's WidgetModel copies <widget>.umd.min.js.map alongside the js
    // unconditionally at install, so the map must ship. It is small now that
    // @openc3/vue-common is no longer bundled (was 4 MB for a 1.5 MB bundle).
    sourcemap: true,
    lib: {
      entry: './src/TimelineWidget.vue',
      name: 'TimelineWidget',
      fileName: (format, entryName) => `${entryName}.${format}.min.js`,
      formats: ['umd'],
    },
    rollupOptions: {
      external: ['single-spa', 'vue', 'pinia', 'vue-router', 'vuetify'],
      output: {
        globals: {
          'single-spa': 'singleSpa',
          vue: 'Vue',
          pinia: 'Pinia',
          'vue-router': 'VueRouter',
          vuetify: 'Vuetify',
        },
      },
    },
  },
  plugins: [vue(), cssInjectedByJsPlugin()],
  resolve: {
    extensions: [...DEFAULT_EXTENSIONS, '.vue'], // not recommended but saves us from having to change every SFC import
  },
})
