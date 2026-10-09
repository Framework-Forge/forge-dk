import { defineConfig } from 'vite';
import { svelte, vitePreprocess } from '@sveltejs/vite-plugin-svelte';

export default defineConfig({
  base: './',
  plugins: [svelte({ configFile: false, preprocess: vitePreprocess() })],
  build: { outDir: 'build', emptyOutDir: true, target: 'es2020' },
});
