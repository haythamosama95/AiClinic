import path from 'node:path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { devApiPlugin } from './server/dev-plugin.ts'

export default defineConfig({
  plugins: [react(), devApiPlugin()],
  resolve: {
    alias: {
      '@': path.resolve(import.meta.dirname, './src'),
    },
  },
  server: {
    proxy: {
      '/gateway': {
        target: 'http://127.0.0.1:8787',
        changeOrigin: true,
        rewrite: (requestPath) => requestPath.replace(/^\/gateway/, ''),
      },
    },
  },
})
