import { defineConfig } from 'astro/config';
import { buildPosts } from '../scripts/build-posts.mjs';
import { typstPlugin } from '../scripts/typst-plugin.mjs';

buildPosts();

export default defineConfig({
  site: 'https://closurescope.github.io',
  output: 'static',
  trailingSlash: 'always',
  redirects: { '/posts': '/' },
  devToolbar: { enabled: false },
  vite: { plugins: [typstPlugin()] },
});
