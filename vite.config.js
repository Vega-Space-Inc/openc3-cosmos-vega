import { defineConfig } from 'vite'
import cssInjectedByJsPlugin from 'vite-plugin-css-injected-by-js'
import vue from '@vitejs/plugin-vue'

const DEFAULT_EXTENSIONS = ['.mjs', '.js', '.ts', '.jsx', '.tsx', '.json']

export default defineConfig({
  build: {
    outDir: 'tools/widgets/TimelineWidget',
    emptyOutDir: true,
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
