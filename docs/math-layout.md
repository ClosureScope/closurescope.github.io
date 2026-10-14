# 数学排版排查（2026-10-14）

> 历史记录：当前 SVG 分支已移除这里描述的浏览器布局补偿，现行方案见 [SVG 数学公式](svg-math.md)。

正文继续使用 HTML，公式继续使用 Typst 导出的原生 MathML。没有把文章转换成 PDF 或图片，也没有更换已经校准的字体。

## 确认的问题与修复

| 问题 | 原因 | 处理 |
| --- | --- | --- |
| 小括号占位过宽 | Chromium 用最大变体宽度为可伸缩符号占位 | 保留之前按实际字形高度匹配宽度的修复 |
| 根号内容贴近横线 | Typst 会把所选根号字形多出的高度分配到上下空隙，浏览器的分配方式不同 | 读取字体的 radical 常量，测量已有留白，只补足差额；不改变内容基线 |
| `V`、`T`、`f` 上标重合 | 原生布局没有按 Typst 的方式使用字形斜体补偿和数学字距 | 从实际 Book/Bold 字体提取 italic correction 和 MathKern，按字形计算上下标偏移 |
| 长箭头、上括号偏移 | 水平伸缩符号的绘制宽度与布局框不一致 | 为复合表达式上的重音设置实际宽度；单字母重音保留字体锚点 |
| `hat(i)` / `hat(j)` 仍有圆点 | Chromium 的单字形数学排版未执行导出 CSS 请求的 `dtls` 替换 | 使用对应 Unicode 去点字形，保留作者显式设置的 dotted 重音 |
| 多行公式里的矩阵挤成一团 | Typst 0.15.1 辅助 CSS 使用后代选择器，外层对齐规则误伤内层矩阵 | 将规则限制到该表格的直接行、单元格 |
| 部分数学结构会消失 | 0.15.1 的 HTML 导出对 overline、underline、cancel、斜分式尚不完整，警告以前未被构建脚本检查 | 遇到 `was ignored during MathML export` 停止构建，防止发布缺少数学内容的公式；这些结构本身尚未补齐 |

根号和上下标补偿仅用于返回字形墨迹框的排版引擎。Firefox 返回的度量框不同，保留其原生布局；用运行时测量识别，不判断浏览器名字。字体加载、字号及窗口改变时重新测量，先撤销上次补偿，避免累积。

## 验证与边界

`tests/fixtures/math-layout.typ` 同时可编译为 PDF 和 HTML，覆盖行内/独立公式、嵌套根号、根指数、上下标与嵌套上下标、重音、上下括号、分式、嵌套分式、求和、积分、矩阵、分段函数、多行公式以及粗体。

自动检查包括真实 Typst 导出、16/17/24/32px 字号、反复缩放、根号留白、脚标位置、长重音居中、嵌套矩阵列间距，以及文章在 1280/390px 视口下的页面级溢出。测试不是穷举所有 Typst 数学语法。

```bash
pnpm build
pnpm exec playwright-core install chromium firefox
pnpm test:math
MATH_BROWSER=firefox node --test tests/math-layout.test.mjs
# 需要肉眼比较时：
typst compile tests/fixtures/math-layout.typ /tmp/math-layout.pdf
```

脚标补偿目前针对 `msub/msup/msubsup` 的单字形基底。复合基底、前置/多组脚标、作者指定的偏移、特殊字体等保留原生排版，不猜测位置。特别高的根指数、超高拼接括号也保留原生处理。Safari、不同系统的抗锯齿效果尚未验证；不保证 HTML 与 PDF 逐像素一致。

## 实现依据

- [Typst 0.15.1 根号布局](https://github.com/typst/typst/blob/v0.15.1/crates/typst-layout/src/math/radical.rs)
- [Typst 0.15.1 上下标布局](https://github.com/typst/typst/blob/v0.15.1/crates/typst-layout/src/math/scripts.rs)
- [Typst 0.15.1 MathML 导出与辅助 CSS](https://github.com/typst/typst/blob/v0.15.1/crates/typst-html/src/mathml.rs)
- [Chromium 伸缩符号的布局宽度限制](https://mathml.igalia.com/project/#width-of-stretchy-operators-blocked-on-chromiums-refactoring)
