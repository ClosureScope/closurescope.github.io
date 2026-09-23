import { join, sep } from 'node:path';
import { buildPosts, root } from './build-posts.mjs';

// Reuse Vite's watcher; no second watcher dependency or long-running compiler.
export function typstPlugin() {
  return {
    name: 'typst-articles',
    configureServer(server) {
      const sources = ['posts', 'typst', 'assets'].map(name => join(root, name));
      server.watcher.add(sources);
      let timer;
      const onChange = (event, file) => {
        if (!['add', 'change', 'unlink', 'addDir', 'unlinkDir'].includes(event)) return;
        if (!sources.some(source => file === source || file.startsWith(source + sep))) return;
        clearTimeout(timer);
        timer = setTimeout(() => {
          try {
            buildPosts();
            server.moduleGraph.invalidateAll();
            server.ws.send({ type: 'full-reload', path: '*' });
          } catch (error) {
            console.error(error.message);
            server.ws.send({ type: 'error', err: { message: error.message, stack: '' } });
          }
        }, 150);
      };
      server.watcher.on('all', onChange);
      server.httpServer?.once('close', () => {
        clearTimeout(timer);
        server.watcher.off('all', onChange);
      });
    },
  };
}
