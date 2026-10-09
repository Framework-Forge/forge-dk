import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';
import path from 'node:path';
const root = fileURLToPath(new URL('..', import.meta.url));
const index = process.argv.indexOf('--toolchain');
const toolchain = index >= 0 ? path.resolve(process.argv[index + 1]) : root;
const require = createRequire(path.join(toolchain, 'package.json'));
const { build } = await import(pathToFileURL(require.resolve('vite')).href);
const { svelte, vitePreprocess } = await import(pathToFileURL(path.join(toolchain,
  'node_modules/@sveltejs/vite-plugin-svelte/src/index.js')).href);
const sveltePath = path.dirname(require.resolve('svelte/package.json'));
const sveltePackage = require('svelte/package.json');
const aliases = Object.entries(sveltePackage.exports).flatMap(([key, value]) => {
  const target = typeof value === 'string' ? value : value.browser || value.default;
  return target ? [{ find: key === '.' ? /^svelte$/ : 'svelte' + key.slice(1), replacement: path.join(sveltePath, target) }] : [];
}).sort((a, b) => String(b.find).length - String(a.find).length);
await build({ configFile: false, root, base: './',
  plugins: [svelte({ configFile: false, preprocess: vitePreprocess() })],
  resolve: { alias: aliases },
  build: { outDir: 'build', emptyOutDir: true, assetsDir: 'assets' } });
