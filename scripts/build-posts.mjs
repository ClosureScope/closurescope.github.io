import { execFileSync, spawnSync } from 'node:child_process';
import { existsSync, mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { namespaceSvgIds } from './svg-math.mjs';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, '.generated');
const compiler = process.env.TYPST_BIN || 'typst';
const fontPython = join(root, '.tools', 'fonttools', 'bin', 'python');
const python = process.env.FONTTOOLS_PYTHON || (existsSync(fontPython) ? fontPython : 'python3');

export function typst(args) {
  const result = spawnSync(compiler, args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  if (result.error || result.status !== 0) {
    throw new Error(`Typst 编译失败：${result.stderr || result.error?.message}`);
  }
  // 0.15.1 silently drops some mathematical constructs despite exit status 0.
  // Never publish an equation with missing mathematical meaning.
  if (/was ignored during MathML export/.test(result.stderr)) {
    throw new Error(`Typst HTML 导出丢失了数学内容，已停止构建。请为该公式设置 math.equation(alt: ...) 提供完整描述：\n${result.stderr}`);
  }
  return result.stdout;
}

export function buildPosts() {
  const version = typst(['--version']).trim();
  if (!/^typst 0\.15\.1\b/.test(version)) {
    throw new Error(`本项目验证并固定使用 Typst 0.15.1；当前为 ${version}。请安装匹配版本。`);
  }
  mkdirSync(output, { recursive: true });
  process.stdout.write(execFileSync(python, [join(root, 'scripts/prepare-typst-fonts.py')], { cwd: root, encoding: 'utf8' }));
  const fontArgs = ['--ignore-system-fonts', '--font-path', join(output, 'typst-fonts')];
  const sources = [];
  const slugs = new Set();
  for (const entry of readdirSync(join(root, 'posts'), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
    if (entry.isFile() && entry.name.endsWith('.typ')) {
      throw new Error(`请将 posts/${entry.name} 放入分类文件夹 posts/<分类>/。`);
    }
    if (!entry.isDirectory()) continue;
    const category = entry.name;
    for (const file of readdirSync(join(root, 'posts', category), { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
      if (!file.isFile() || !file.name.endsWith('.typ')) continue;
      const name = join(category, file.name);
      const slug = file.name.slice(0, -4);
      if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
        throw new Error(`文章文件名请使用小写英文、数字和连字符：${name}`);
      }
      if (slugs.has(slug)) throw new Error(`文章文件名重复：${name}。不同分类中的文件名也必须唯一。`);
      slugs.add(slug);
      sources.push({ name, slug, category });
    }
  }
  const posts = sources.map(({ name, slug, category }) => {
    const input = join(root, 'posts', name);
    const destination = join(output, `${slug}.html`);
    typst(['compile', ...fontArgs, '--root', root, '--features', 'html', '--input', 'site=true', input, destination]);
    const metadata = JSON.parse(typst([
      'eval', ...fontArgs, '--root', root, '--features', 'html', '--target', 'html', '--in', input,
      'query(<blog-meta>).map(it => it.value)',
    ]));
    if (metadata.length !== 1) throw new Error(`${name} 必须使用一次 article 模板。`);
    const { title } = metadata[0];
    if (typeof title !== 'string' || !title.trim()) {
      throw new Error(`${name} 的 title 必须是非空字符串。`);
    }
    // Extract only the compiler's known standalone envelope, never parse Typst source.
    // Keep its MathML support CSS from <head>; dropping it breaks advanced equations.
    const html = readFileSync(destination, 'utf8');
    const body = html.match(/<body\b[^>]*>([\s\S]*)<\/body>\s*<\/html>\s*$/i)?.[1];
    const head = html.match(/<head\b[^>]*>([\s\S]*?)<\/head>/i)?.[1];
    if (body === undefined || head === undefined) throw new Error(`${name} 的 HTML 结构与预期不符。`);
    const styles = [...head.matchAll(/<style\b[^>]*>[\s\S]*?<\/style>/gi)].map(match => match[0]).join('\n');
    return { slug, title, category, body: namespaceSvgIds(body), styles };
  });
  try {
    const result = execFileSync(python,
      [join(root, 'scripts', 'build-fonts.py')], {
        cwd: root, input: JSON.stringify(posts), encoding: 'utf8', maxBuffer: 8 * 1024 * 1024,
      });
    process.stdout.write(result);
  } catch (error) {
    throw new Error(`网页字体生成失败。请按 README 安装 scripts/font-requirements.txt 中的依赖。\n${error.stderr || error.message}`);
  }
  // Publish the manifest atomically only after every article succeeds.
  const manifest = join(output, 'posts.json');
  const json = JSON.stringify(posts, null, 2) + '\n';
  let previous;
  try { previous = readFileSync(manifest, 'utf8'); } catch (error) { if (error.code !== 'ENOENT') throw error; }
  if (previous !== json) {
    writeFileSync(`${manifest}.tmp`, json);
    renameSync(`${manifest}.tmp`, manifest);
  }
  const current = new Set(posts.map(post => `${post.slug}.html`));
  for (const name of readdirSync(output)) {
    if (name.endsWith('.html') && !current.has(name)) unlinkSync(join(output, name));
  }
  console.log(`[typst] 已构建 ${posts.length} 篇文章（HTML 导出仍为实验功能）。`);
  return posts;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) buildPosts();
