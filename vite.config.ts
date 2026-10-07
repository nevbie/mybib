import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { VitePWA } from 'vite-plugin-pwa'

// On GitHub Pages the app lives under /<repo>/; the deploy workflow sets BASE_PATH.
const base = process.env.BASE_PATH ?? '/'

export default defineConfig({
  base,
  plugins: [
    react(),
    VitePWA({
      registerType: 'autoUpdate',
      includeAssets: ['icon.svg', 'apple-touch-icon.png'],
      manifest: {
        name: 'mybib · Meine Bibliothek',
        short_name: 'mybib',
        // explicit app identity (also lets phones with a stuck earlier install install it afresh)
        id: 'mybib-app',
        description: 'Catalogue your books, board games, DVDs and CDs',
        theme_color: '#0f766e',
        background_color: '#f6faf9',
        display: 'standalone',
        start_url: base,
        scope: base,
        icons: [
          { src: 'icon-192.png', sizes: '192x192', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png' },
          { src: 'icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'maskable' },
        ],
      },
      workbox: {
        // keep cover images from Open Library / Google Books / Cover Art Archive available offline
        runtimeCaching: [
          {
            urlPattern: /^https:\/\/(covers\.openlibrary\.org|books\.google\.com|books\.googleusercontent\.com|coverartarchive\.org|archive\.org|[a-z0-9.-]+\.archive\.org)\//,
            handler: 'CacheFirst',
            options: {
              cacheName: 'covers',
              expiration: { maxEntries: 3000, maxAgeSeconds: 60 * 60 * 24 * 365 },
              cacheableResponse: { statuses: [0, 200] },
            },
          },
        ],
      },
    }),
  ],
  test: { environment: 'node' },
})
