export function enableMathCopy(root) {
  if (!root) return;
  const status = document.createElement('span');
  status.className = 'math-copy-status';
  status.setAttribute('role', 'status');
  root.append(status);
  for (const formula of root.querySelectorAll('.math-formula')) {
    const semantic = formula.querySelector('.math-semantic');
    const math = semantic?.querySelector('math');
    if (!semantic) continue;
    let text = semantic.textContent.trim();
    if (math) {
      const copy = math.cloneNode(true);
      copy.setAttribute('xmlns', 'http://www.w3.org/1998/Math/MathML');
      text = copy.outerHTML;
    }
    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'math-copy';
    button.textContent = math ? '复制 MathML' : '复制公式说明';
    formula.addEventListener('pointerdown', event => {
      if (event.pointerType === 'touch' && event.target !== button) {
        button.focus({ preventScroll: true });
      }
    });
    button.addEventListener('click', async () => {
      try {
        await navigator.clipboard.writeText(text);
        status.textContent = '';
        requestAnimationFrame(() => { status.textContent = '已复制公式'; });
      } catch {
        // Clipboard permission may be unavailable on HTTP previews or denied.
        const dialog = document.createElement('dialog');
        dialog.className = 'math-copy-dialog';
        dialog.setAttribute('aria-label', '复制公式');
        const label = document.createElement('label');
        label.textContent = '请复制下面的内容：';
        const input = document.createElement('textarea');
        input.readOnly = true;
        input.value = text;
        label.append(input);
        const close = document.createElement('button');
        close.textContent = '关闭';
        close.addEventListener('click', () => dialog.close());
        dialog.append(label, close);
        dialog.addEventListener('close', () => { dialog.remove(); button.focus(); });
        document.body.append(dialog);
        dialog.showModal();
        input.focus();
        input.select();
      }
    });
    formula.append(button);
  }
}
