import { SurfaceTransition } from "./ui-transitions";

/** Keep the original article in its own, unscaled viewport. */
export class BlogReader {
  private root = document.createElement('section');
  private frame = document.createElement('iframe');
  private link: HTMLAnchorElement;
  private href = '';
  private transition: SurfaceTransition;
  private visible = false;

  constructor(private back: () => void, private directory: () => void) {
    this.root.id = 'detail-ui';
    this.root.className = 'reading-view';
    this.root.setAttribute('aria-label', '文章阅读');
    this.root.hidden = true;
    this.root.innerHTML = `<nav class="reading-toolbar" aria-label="阅读导航">
      <button type="button" data-reader="back" aria-label="返回文章选择">← <span>返回</span></button>
      <span class="reading-brand">ClosureScope</span>
      <div class="reading-tools"><button type="button" data-reader="directory">DIRECTORY</button><a class="reading-standalone" target="_top">独立阅读 ↗</a></div>
    </nav>`;
    this.link = this.root.querySelector<HTMLAnchorElement>('.reading-standalone')!;
    this.root.querySelector('[data-reader="back"]')!.addEventListener('click', this.back);
    this.root.querySelector('[data-reader="directory"]')!.addEventListener('click', this.directory);
    this.frame.className = 'blog-reader';
    this.frame.addEventListener('load', () => {
      const doc = this.frame.contentDocument;
      if (!doc) return;
      // Retain the original article title, prose, CSS, fonts and SVG math.
      // Only the duplicate site navigation is hidden inside the reader.
      doc.querySelectorAll<HTMLElement>('.site-header, .article-meta .back-link').forEach(node => {
        node.hidden = true;
      });
      doc.addEventListener('keydown', event => {
        const target = event.target as HTMLElement;
        if (target.matches('input, textarea, select, [contenteditable="true"]')) return;
        if (event.key === 'Escape') {
          event.preventDefault();
          this.back();
        } else if (event.key === '/') {
          event.preventDefault();
          this.directory();
        }
      });
    });
    this.root.append(this.frame);
    document.body.append(this.root);
    this.transition = new SurfaceTransition(this.root, this.root, 450, 200);
  }

  open(href: string, title: string) {
    this.frame.title = title;
    this.link.href = href;
    this.link.setAttribute('aria-label', `独立阅读 ${title}`);
    if (this.href !== href) {
      this.href = href;
      this.frame.src = href;
    }
  }

  setVisible(visible: boolean, animated = false) {
    if (this.visible === visible) return;
    this.visible = visible;
    this.root.inert = !visible;
    if (visible) {
      this.transition.show(!animated);
      this.frame.focus();
    } else {
      this.transition.hide(!animated);
    }
  }

  dispose() { this.transition.dispose(); this.root.remove(); }
}
