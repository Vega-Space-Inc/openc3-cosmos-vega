import { defineConfig } from 'vite'
import cssInjectedByJsPlugin from 'vite-plugin-css-injected-by-js'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
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
