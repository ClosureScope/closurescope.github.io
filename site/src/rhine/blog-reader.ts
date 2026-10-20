/** Render the existing article document in a separate, unscaled viewport.
 * No reference CSS, document reveal markup or font overrides enter the article.
 */
export class BlogReader {
  private frame = document.createElement('iframe');
  private href = '';
  constructor(private back: () => void) {
    this.frame.className = 'blog-reader';
    this.frame.hidden = true;
    this.frame.addEventListener('load', () => {
      const doc = this.frame.contentDocument;
      if (!doc) return;
      // The archive shell already shows the title and navigation. Hide only
      // duplicate page chrome inside this frame; keep article/prose, its CSS,
      // fonts and mathematical SVG completely intact. Standalone pages retain
      // their original header and title.
      doc.querySelectorAll<HTMLElement>('.site-header, .article-header').forEach(node => {
        node.hidden = true;
      });
      doc.querySelectorAll<HTMLAnchorElement>('.brand, .back-link').forEach(link => {
        link.addEventListener('click', event => {
          event.preventDefault();
          this.back();
        });
      });
      doc.addEventListener('keydown', event => {
        if (event.key === 'Escape') {
          event.preventDefault();
          this.back();
        }
      });
    });
    document.body.append(this.frame);
  }
  open(href: string, title: string) {
    this.frame.title = title;
    if (this.href !== href) {
      this.href = href;
      this.frame.src = href;
    }
  }
  update(visible: boolean, opacity: number) {
    const slot = document.querySelector<HTMLElement>('.blog-reader-slot');
    const panel = document.querySelector<HTMLElement>('#detail-content');
    this.frame.hidden = !visible || !slot || !panel || opacity < 0.01;
    if (this.frame.hidden || !slot || !panel) return;
    const rect = slot.getBoundingClientRect();
    const clip = panel.getBoundingClientRect();
    const top = Math.max(0, rect.top, clip.top);
    const bottom = Math.min(innerHeight, rect.bottom, clip.bottom);
    // Give the article the genuinely visible height so its last lines remain
    // reachable by scrolling the article itself, even in a short detail panel.
    Object.assign(this.frame.style, {
      left: `${rect.left}px`, top: `${top}px`,
      width: `${rect.width}px`, height: `${Math.max(0, bottom - top)}px`,
      opacity: String(opacity),
    });
  }
  dispose() { this.frame.remove(); }
}
