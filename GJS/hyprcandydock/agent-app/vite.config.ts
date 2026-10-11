import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  base: './',
  build: {
    target: 'esnext',
    assetsInlineLimit: 100000000, // Inline assets where practical or keep standard chunks
    chunkSizeWarningLimit: 3000,
    // Low-RAM builds (e.g. 4 GB laptops) otherwise abort mid-bundle when Monaco's
    // editor + workers are graphed. Skipping the gzip/brotli size pass and
    // throttling Rollup's concurrent file ops cut peak memory meaningfully with
    // no change to the emitted output.
    reportCompressedSize: false,
    rollupOptions: {
      maxParallelFileOps: 2,
      output: {
        manualChunks: undefined,
      },
    },
  },
  worker: {
    format: 'es',
  },
  server: {
    port: 5173,
  },
});
