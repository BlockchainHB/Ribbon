import { defineConfig } from 'astro/config';

export default defineConfig({
  site: process.env.PUBLIC_SITE_URL || undefined,
  output: 'static',
  trailingSlash: 'always',
  build: { inlineStylesheets: 'never' },
  vite: { build: { sourcemap: false } },
});
