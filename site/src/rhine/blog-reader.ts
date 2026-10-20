import { SurfaceTransition } from "./ui-transitions";

/** Keep the original article in its own, unscaled viewport. */
export class BlogReader {
  private root = document.createElement('section');
  private scene = document.querySelector<HTMLElement>('.scene-visuals')!;
  private resizeObserver: ResizeObserver;
  private frame = document.createElement('iframe');
  private toolbar: HTMLElement;
  private stage = document.querySelector<HTMLElement>('#stage')!;
  private headerLayer = document.createElement('div');
  private headers = [...document.querySelectorAll<HTMLElement>('header.brand, .system-nav')];
  private href = '';
  private transition: SurfaceTransition;
  private visible = false;

  constructor(private back: () => void, private directory: () => void) {
    this.root.id = 'detail-ui';
    this.root.className = 'reading-view';
    this.root.setAttribute('aria-label', '文章阅读');
    this.root.hidden = true;
    this.root.innerHTML = `<nav class="reading-toolbar" aria-label="阅读导航">
      <button type="button" data-reader="back" aria-label="返回文章选择">←</button>
    </nav>`;
    this.toolbar = this.root.querySelector<HTMLElement>('.reading-toolbar')!;
    this.toolbar.inert = true;
    this.root.querySelector('[data-reader="back"]')!.addEventListener('click', this.back);
    this.frame.className = 'blog-reader';
    this.frame.addEventListener('load', () => {
      const doc = this.frame.contentDocument;
      if (!doc) return;
      // Retain the original article title, prose, CSS, fonts and SVG math.
      // Hide duplicate navigation and let the original scene show through.
      doc.body.style.backgroundColor = 'transparent';
      // Hide only the document scrollbar; preserve scrolling and the local
      // horizontal scroll containers used by long formulas and code blocks.
      const chromeStyle = doc.createElement('style');
      chromeStyle.textContent = `html { scrollbar-width: none; }
        html::-webkit-scrollbar, body::-webkit-scrollbar { width: 0; height: 0; }
        main { padding-top: max(80px, env(safe-area-inset-top)); }
        @media (min-width: 601px) {
          main { width: min(1040px, calc(100% - 48px)); }
          article { max-width: 54em; }
        }
        @media (min-width: 601px) and (max-width: 1100px) {
          main { width: calc(100% - 120px); }
        }
        @media (max-width: 600px) {
          main { width: calc(100% - 104px); padding-top: max(72px, env(safe-area-inset-top)); }
        }`;
      doc.head.append(chromeStyle);
      doc.querySelectorAll<HTMLElement>('.site-header, .article-meta .back-link').forEach(node => {
        node.hidden = true;
      });
      this.alignControls();
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
    this.headerLayer.className = 'reading-header-stage';
    this.headerLayer.dataset.mode = 'detail';
    this.headerLayer.hidden = true;
    document.body.append(this.headerLayer);
    this.transition = new SurfaceTransition(this.root, this.root, 450, 200);
    this.resizeObserver = new ResizeObserver(() => { this.alignControls(); this.syncHeader(); });
    this.resizeObserver.observe(this.frame);
    this.resizeObserver.observe(this.stage);
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
    this.root.dataset.animated = String(animated);
    this.scene.dataset.animated = String(animated);
    if (visible) {
      this.syncHeader();
      this.headerLayer.append(...this.headers);
      this.headerLayer.hidden = false;
      this.setReveal(animated ? 0 : 1);
      this.transition.show(!animated);
      this.alignControls();
      this.frame.focus();
    } else {
      this.stage.append(...this.headers);
      this.headerLayer.hidden = true;
      this.setSceneReveal(0);
      this.transition.hide(!animated);
    }
  }

  setReveal(progress: number) {
    if (!this.visible) return;
    this.frame.style.opacity = String(progress);
    this.toolbar.style.opacity = String(progress);
    this.toolbar.inert = progress < .99;
    this.toolbar.setAttribute('aria-hidden', String(progress < .99));
    this.setSceneReveal(progress);
  }

  private setSceneReveal(progress: number) {
    this.scene.style.setProperty('--scene-reading-blur', `${14 * progress}px`);
    this.scene.style.setProperty('--scene-reading-saturation', String(1 - .2 * progress));
    this.scene.style.setProperty('--scene-reading-reveal', String(progress));
  }

  private alignControls() {
    const article = this.frame.contentDocument?.querySelector('article');
    if (article) this.root.style.setProperty('--reader-content-left', `${article.getBoundingClientRect().left}px`);
  }

  private syncHeader() {
    const style = getComputedStyle(this.stage);
    this.headerLayer.style.width = style.width;
    this.headerLayer.style.height = style.height;
    this.headerLayer.style.transform = style.transform;
    this.headerLayer.dataset.layout = this.stage.dataset.layout;
  }

  dispose() {
    this.resizeObserver.disconnect();
    this.setSceneReveal(0);
    this.transition.dispose();
    this.stage.append(...this.headers);
    this.headerLayer.remove();
    this.root.remove();
  }
}
