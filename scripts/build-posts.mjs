import { execFileSync } from 'node:child_process';
import { mkdirSync, readdirSync, readFileSync, renameSync, writeFileSync, unlinkSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { categories } from './categories.mjs';

export const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const output = join(root, '.generated');
const compiler = process.env.TYPST_BIN || 'typst';

function typst(args) {
  try {
    return execFileSync(compiler, args, { cwd: root, encoding: 'utf8', maxBuffer: 32 * 1024 * 1024 });
  } catch (error) {
    throw new Error(`Typst 编译失败：${error.stderr || error.message}`);
  }
}

export function buildPosts() {
  const version = typst(['--version']).trim();
  if (!/^typst 0\.15\.1\b/.test(version)) {
    throw new Error(`本项目验证并固定使用 Typst 0.15.1；当前为 ${version}。请安装匹配版本。`);
  }
  mkdirSync(output, { recursive: true });
  const posts = readdirSync(join(root, 'posts')).filter(name => name.endsWith('.typ')).sort().map(name => {
    const slug = name.slice(0, -4);
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug)) {
      throw new Error(`文章文件名请使用小写英文、数字和连字符：${name}`);
    }
    const input = join(root, 'posts', name);
    const destination = join(output, `${slug}.html`);
    typst(['compile', '--root', root, '--features', 'html', '--input', 'site=true', input, destination]);
    const metadata = JSON.parse(typst([
      'eval', '--root', root, '--features', 'html', '--target', 'html', '--in', input,
      'query(<blog-meta>).map(it => it.value)',
    ]));
    if (metadata.length !== 1) throw new Error(`${name} 必须使用一次 article 模板。`);
    const { title, date, description, category } = metadata[0];
    if (![title, date, description, category].every(value => typeof value === 'string' && value.trim())) {
      throw new Error(`${name} 的 title、date、description、category 必须是非空字符串。`);
    }
    if (!categories.includes(category)) {
      throw new Error(`${name} 的 category 必须是以下之一：${categories.join('、')}。`);
    }
    const parsedDate = new Date(`${date}T00:00:00Z`);
    if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || Number.isNaN(+parsedDate) || parsedDate.toISOString().slice(0, 10) !== date) {
      throw new Error(`${name} 的 date 必须是有效的 YYYY-MM-DD 日期。`);
    }
    // Extract only the compiler's known standalone envelope, never parse Typst source.
    // Keep its MathML support CSS from <head>; dropping it breaks advanced equations.
    const html = readFileSync(destination, 'utf8');
    const body = html.match(/<body\b[^>]*>([\s\S]*)<\/body>\s*<\/html>\s*$/i)?.[1];
    const head = html.match(/<head\b[^>]*>([\s\S]*?)<\/head>/i)?.[1];
    if (body === undefined || head === undefined) throw new Error(`${name} 的 HTML 结构与预期不符。`);
    const styles = [...head.matchAll(/<style\b[^>]*>[\s\S]*?<\/style>/gi)].map(match => match[0]).join('\n');
    return { slug, title, date, description, category, body, styles };
  });
  posts.sort((a, b) => b.date.localeCompare(a.date) || a.slug.localeCompare(b.slug));
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
