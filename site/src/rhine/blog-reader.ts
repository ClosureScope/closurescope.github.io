import { SurfaceTransition } from "./ui-transitions";

/** Keep the original article in its own, unscaled viewport. */
export class BlogReader {
  private root = document.createElement('section');
  private frame = document.createElement('iframe');
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
    </nav>`;
    this.root.querySelector('[data-reader="back"]')!.addEventListener('click', this.back);
    this.frame.className = 'blog-reader';
    this.frame.addEventListener('load', () => {
      const doc = this.frame.contentDocument;
      if (!doc) return;
      // Retain the original article title, prose, CSS, fonts and SVG math.
      // Hide duplicate navigation and let the original scene show through.
      // This background change never alters prose typography or SVG math.
      doc.body.style.backgroundColor = 'transparent';
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
      this.frame.style.opacity = animated ? "0" : "1";
      this.transition.show(!animated);
      this.frame.focus();
    } else {
      this.transition.hide(!animated);
    }
  }

  setReveal(progress: number) {
    if (this.visible) this.frame.style.opacity = String(progress);
  }

  dispose() { this.transition.dispose(); this.root.remove(); }
}
