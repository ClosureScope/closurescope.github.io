# ClosureScope 博客

文章全部写在 `.typ` 中，使用 Typst 原生数学语法、标题、代码块和图片。文章统一引用你提供的 `typst/template.typ`，保留 `frame-it`、`tablem`、`definition` 等命令。Astro 只负责网站外壳；不使用 Markdown/MDX、LaTeX、KaTeX 或 MathJax。

```text
posts/*.typ + typst/template.typ（原有笔记模板）+ assets/*
    ↓ Typst 0.15.1（实验性 HTML 导出）
.generated/*.html + posts.json
    ↓ Astro（首页文章列表、文章页、样式）
site/dist/（可部署的静态网站）
```

## 启动

在 WSL 终端运行：

```bash
cd ~/blog
pnpm dev
```

访问终端显示的地址，默认 <http://localhost:4321>。VS Code 使用 Remote WSL 打开此目录，也可以运行 `code .`。

修改 `posts/`、`typst/`、`assets/` 下的文件后会自动重新编译、刷新浏览器，新增和删除文章也会更新列表。编译错误显示在终端和浏览器错误遮罩中；修正保存后恢复。Ctrl+C 停止服务。

## 新文章

复制示例，文件名用小写英文、数字和连字符，文件名就是 URL：

```bash
cp posts/hello-world.typ posts/least-squares.typ
```

然后在这个 `.typ` 中修改 `title`、`date`（`YYYY-MM-DD`）、`category` 和正文。不需要另写 frontmatter、JSON 或注册路由。每篇文章选一个主分类：`RL`、`Optimization`、`Machine Learning`、`Mathematics` 或 `Systems`。分类名单统一写在 `scripts/categories.mjs`。

````typst
#import "../typst/template.typ": *
#show: article.with(
  title: "最小二乘",
  date: "2026-09-23",
  category: "Optimization",
)

= 问题

普通正文，以及行内公式 $A x = b$。

$ nabla f(x) = A^T (A x - b) $

== 实现

```python
def gradient(A, x, b):
    return A.T @ (A @ x - b)
```

#image("../assets/gradient.svg", alt: "梯度下降示意图")

#definition[梯度][梯度指出函数增长最快的方向。]
````

新文章会出现在 `/posts/least-squares/`，首页按分类分组，只显示有文章的分类；分类内按日期倒序排列。旧的 `/posts/` 列表地址会跳转到首页。Typst 默认不为标题编号；模板已设置自动编号，`= ...` 显示为 `1. ...`，`== ...` 显示为 `1.1. ...`。网页中它们分别是 `h2`、`h3`，文章标题由 Astro 输出为 `h1`。Typst 独立导出的 HTML 和 PDF 会在正文开头显示 `article` 的标题；网站构建时传入 `site=true`，避免标题重复。`article` 是在原模板末尾加的博客入口，复用原模板的定义框等命令；正文可以直接用 `definition`、`theorem` 等原有命令。迁移旧笔记时，把原来的整篇文档 `#show` 改为 `#show: article.with(...)`，并补上日期、分类。

图片放在 `assets/`，从文章使用相对路径引用。当前 Typst 会把图片内嵌进 HTML，不需要另外复制到网站 public 目录。

## 构建

```bash
pnpm build:posts  # 仅编译文章，便于排查 Typst 问题
pnpm build        # 编译所有文章并构建静态网站
pnpm preview      # 预览 site/dist 中的生产构建
```

独立验证 Typst HTML：

```bash
mkdir -p .generated
typst compile --root . --features html posts/hello-world.typ .generated/hello-world.html
typst compile --root . posts/hello-world.typ /tmp/hello-world.pdf # 可选：直接导出带标题的 PDF
```

部署时上传 `site/dist/` 即可，服务器不需要 Node 或 Typst。当前 URL 按域名根路径设计；若以后部署到 `/blog/` 等子路径，需要同时调整 Astro `base` 和导航 URL。

### GitHub Pages

本站配置为 GitHub 用户主页：仓库名 `closurescope.github.io`，网址 <https://closurescope.github.io/>。GitHub 用户名是 `ClosureScope`，但 GitHub Pages 要求用户主页仓库名中的用户名部分使用小写。先将本仓库推送到 `ClosureScope/closurescope.github.io`，然后在仓库 **Settings → Pages → Build and deployment → Source** 选择 **GitHub Actions**。以后每次推送到 `main`，`.github/workflows/deploy.yml` 都会安装固定版本的 Node、pnpm 和 Typst，构建 `site/dist/` 并发布。首次发布完成前，网址可能显示 404。

## 目录

| 路径 | 用途 |
| --- | --- |
| `posts/*.typ` | 文章正文与元信息，唯一写作来源 |
| `typst/template.typ` | 你提供的笔记模板，附加 `article` 博客入口与元信息 |
| `assets/` | 文章图片 |
| `scripts/build-posts.mjs` | 调用 Typst，读取元信息，提取 HTML 正文和公式样式 |
| `scripts/categories.mjs` | 可用的文章分类及其显示顺序 |
| `scripts/typst-plugin.mjs` | 复用 Vite 文件监听与刷新机制 |
| `site/src/pages/` | 首页与文章路由 |
| `site/src/styles/global.css` | 网站排版和代码样式 |
| `site/public/fonts/` | 网页正文、强调文字、代码字体及授权文件 |
| `.generated/` | 中间产物，自动生成，不要编辑或提交 |
| `site/dist/` | 生产产物，不提交 |

## 环境与依赖

本机初始化前：WSL2/Linux、Git 2.43.0、Node 18.19.1、npm 9.2.0；未安装 Typst 和 pnpm。

本项目使用 Node **22.23.2**、pnpm **10.17.1**、Typst **0.15.1**、Astro **7.3.4**。唯一直接网站依赖是 Astro，具体依赖树由 `pnpm-lock.yaml` 固定。没有额外引入 UI 框架、代码高亮库或文件监听库。

本机的 Node 与 Typst 官方二进制位于被 Git 忽略的 `.tools/`，命令通过已有 PATH 中的 `~/.local/bin/` 链接使用；pnpm 安装在 `~/.local/`。系统 `/usr/bin/node` 未被替换。不要删除 `.tools/`，否则这些链接会失效。所有工具均在 WSL/Linux 内运行。

模板使用 Typst Universe 的 `frame-it:2.0.0`、`tablem:0.3.0`。本机已缓存它们；新机器首次编译时 Typst 可能需要联网获取这两个包。

代码字体选用 [JetBrains Mono 2.304](https://github.com/JetBrains/JetBrainsMono/releases/tag/v2.304)，授权为 [SIL OFL 1.1](https://github.com/JetBrains/JetBrainsMono/blob/master/OFL.txt)。TTF 已安装在本机 `~/.local/share/fonts/`；网页所需的 WOFF2 和授权文件在 `site/public/fonts/`，读者无需自行安装。代码字体规则直接写在共享的 `typst/template.typ` 的 `article` 函数内，Typst 的代码块和行内 `raw` 均使用它。中文代码字符回退到 Noto Sans SC，与旧笔记的字体顺序一致；若文章需要严格按字符列对齐，应避免混用不同字体的中英文字符。

旧笔记中的 [Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc) 和 [Noto Serif SC](https://github.com/google/fonts/tree/main/ofl/notoserifsc) 现已从 Google Fonts 官方文件安装到本机 `~/.local/share/fonts/`，均使用 SIL OFL 1.1 授权。共享模板的 `font-hei`、`font-song` 已恢复这两个原始字体名。网站也随站点分发其 WOFF2 版本，正文中文使用 Noto Serif SC，强调和代码中的中文使用 Noto Sans SC。英文正文使用 [Libertinus Serif](https://github.com/alerque/libertinus)，与 Typst 模板的字体顺序一致。完整中文字体使 `site/public/fonts/` 约为 23 MB；首次访问需要下载所用的字体，此后由浏览器缓存。

楷体使用 CTAN 的 [FandolKai](https://ctan.org/pkg/fandol)，官方 README 标为 GPL 加字体例外。`FandolKai-Regular.otf` 已安装在本机 `~/.local/share/fonts/`，网站也分发其 WOFF2 版本，供强调文字使用。新 WSL 环境需要重新安装上述四款本地字体，运行 `fc-cache -f ~/.local/share/fonts`；可用 `fc-match 'JetBrains Mono'`、`fc-match 'Noto Sans SC'`、`fc-match 'Noto Serif SC'` 和 `fc-match FandolKai` 检查。

迁移到其他机器时，先安装上述 Node、pnpm 和 [Typst 0.15.1 官方发行版](https://github.com/typst/typst/releases/tag/v0.15.1)，确保命令在 PATH 中，再运行：

```bash
pnpm install --frozen-lockfile
pnpm dev
```

也可用 `TYPST_BIN=/absolute/path/to/typst pnpm dev` 指定编译器。

## HTML 实测与限制

采用直接 HTML 的原因：这个最小示例实测能输出可选择的正文、语义化标题、带高亮的 Python `pre/code`、内嵌图片和原生 MathML。无需整篇变成图片，也无需转写公式语法。构建脚本还保留 Typst 在 HTML head 中输出的 MathML 辅助 CSS。

**Typst HTML 导出仍是实验功能。** [官方文档](https://typst.app/docs/reference/html/) 明确表示它仍不完整，不建议用于生产用例。这是一个固定版本、已验证当前示例的最小博客原型，不代表任意 Typst 文档或宏包均可稳定导出。`pnpm build` 成功只表示静态站点构建成功，不意味着 Typst 的 HTML 功能已稳定。

当前边界：

- HTML 不等同于 PDF 页面排版；分页、精确位置、复杂绘图或某些第三方包可能不支持，需要逐项验证。没有尝试把 PDF 模板强行搬进网页。
- 数学由浏览器原生 MathML 渲染；应使用现代 Chrome/Edge、Firefox 或 Safari。不同系统的数学字体会影响细节，本版没有绑定网络字体。
- 图片内嵌会增大 HTML；少量技术插图足够，未来图片较多时再考虑独立资源输出。
- Typst 尚不直接输出 HTML 片段。本项目针对固定版本的完整 HTML 提取 body 与 style，不解释 `.typ` 源码；升级编译器后需要重新验证输出结构。
- 网站标题与导航由 Astro 显示；独立导出的 Typst HTML 和 PDF 在正文开头显示文章标题，没有扉页或自动目录。Typst 的字体设置不会自动变成网页 CSS，网页正文使用 `site/src/styles/global.css` 中的字体。`frame-it` 的 `definition` 已实际验证可导出 HTML；其他宏包功能需按需逐一验证。
- 旧模板使用的 `Libertinus Serif`、`Noto Serif SC`、`Noto Sans SC`、`FandolKai` 已通过网页 CSS 映射到随站点分发的字体。网页与 PDF 的行距、字距、分页和数学排版仍可能不同。
- 开发时任一源文件变化会重编译全部文章，适合初期的小博客；数量明显增加后再做增量构建。
- 当前只发布 `posts/` 直属 `.typ`，没有草稿开关；辅助 Typst 文件放到 `typst/`。文章内容视为本人可信内容。

Git 已初始化到 `main`；是否已连接远程仓库和发布，请以 `git remote -v` 与 GitHub Actions 的运行结果为准。

## 本次验证

- Typst 0.15.1 直接编译示例 HTML 与 PDF 成功，公式使用内置 `nabla`，`definition` 来自你的模板。
- `pnpm dev` 成功启动，首页文章列表和文章页均返回 HTTP 200。
- Chromium 实测桌面和 390px 手机宽度：公式、Python 高亮、缩进和图片正常，页面无横向溢出。
- 实测修改正文自动刷新、新增/删除文章更新列表和路由、编译错误遮罩及修复恢复。
- `pnpm build` 成功生成首页、旧地址跳转页和示例文章页；`pnpm preview` 的生产页面也通过 Chromium 显示检查。
- 字体检查文章的 PDF 确认嵌入 JetBrains Mono 和 FandolKai；示例文章仍导出为一页 PDF。

浏览器验证工具临时安装在 `/tmp/blog-browser-check/`，未加入项目依赖。VS Code/Tinymist 可能在 `posts/` 生成 PDF，已忽略这类产物。

通常 `pnpm dev` 在前台运行，Ctrl+C 停止。Astro 7 在检测到编程代理环境时会自动转为后台；此时可以用 `pnpm dev stop`、`pnpm dev status` 管理。需要前台运行时用 `pnpm dev --ignore-lock`。
