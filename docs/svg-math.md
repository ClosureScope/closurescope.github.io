# SVG 数学公式

正文仍为 HTML。共享模板在 HTML 导出时使用 Typst 官方 `html.frame` 生成公式 SVG，PDF 导出返回原公式。字形、上下标、分式、根号、重音、矩阵均由 Typst 的分页排版引擎决定。

## 实现

- `typst/web-math.typ`：HTML 专用 show rule；用字体实际边界测量完整高度，再与基线高度相减得到下伸量，输出 em 尺寸和 CSS 基线偏移。没有为某个字符单独添加间距。
- `scripts/prepare-typst-fonts.py`：把仓库内中文、楷体、等宽字体还原为 OpenType。网页编译使用这些字体与 Typst 0.15.1 内置字体，并禁用系统字体搜索，保证 CI 与本地使用相同来源。
- `scripts/svg-math.mjs`：为各 SVG 的字形定义和内部引用分配独立 ID，避免多公式嵌入同一页面时冲突。文档内编号链接保留。
- CSS：短公式保持自然字号，行内公式跟随正文基线；长公式在自身容器内滚动。公式不依赖浏览器数学字体和 JavaScript 才能显示。
- 旧 `math-spacing.js`、`math-layout.js`、字体数学度量提取与对应样式补偿已移除。

## 辅助技术

SVG 视觉层设置 `aria-hidden="true"`。旁边保留视觉隐藏但仍在可访问树中的原生 MathML；如果公式设置 `alt`，则使用作者描述。尚未使用真实屏幕阅读器逐一验证朗读质量。

Typst 0.15.1 的原生 MathML 尚不支持部分结构（例如 `overline`、`cancel`）。SVG 能正常绘制，但为了不留下残缺的辅助表示，遇到这些结构需要提供完整 `alt`：

```typst
#math.equation(
  block: true,
  alt: "x 上方带横线，加上被划去的 y",
  $overline(x) + cancel(y)$,
)
```

未提供描述且 MathML 导出报告内容被忽略时，构建仍会明确失败。

## 验证

- 同一数学样例启用/不启用新 show rule 的 PDF，在固定创建时间后逐字节相同。
- Chromium、Firefox 验证行内基线、16/17/24/32px 缩放、公式编号与引用、SVG ID 唯一性及引用完整性。
- 全部本地文章在 1280px 和 390px 宽度检查页面溢出；超长公式保持字号并滚动。
- 验证无 JavaScript 时仍显示公式，悬停公式时不出现复制控件。
- 测试样例包含根号、上下标、重音、分式、求和、积分、矩阵、分段函数、多行与粗体，以及带描述的原生 MathML 不支持的结构。

```bash
pnpm build
pnpm exec playwright-core install chromium firefox
pnpm test:math
MATH_BROWSER=firefox node --test tests/math-svg.test.mjs
```

Safari 和实际屏幕阅读器仍需进一步验证。浏览器与 PDF 查看器的抗锯齿可能不同；正文换行、分页也不会与 PDF 完全相同。

SVG 增加页面体积：当前六篇已跟踪文章的 HTML 约 25–1265 KiB，gzip 后约 6–175 KiB（本地估算，实际传输取决于服务器压缩）。它换取固定的公式布局，也避免下载数学网页字体和运行布局补偿脚本。

GitHub Pages 工作流在推送 `main` 时发布。
