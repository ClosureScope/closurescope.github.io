// Metadata only: article HTML, fonts and SVG stay in the existing pages.
export function createArchiveIndex(posts) {
  const columns = [], records = [], files = [], locations = [];
  const slugs = new Set();
  for (const post of posts) {
    if (!post.slug || !post.title || !post.category || slugs.has(post.slug)) {
      throw new Error('博客索引需要唯一 slug、标题和分类。');
    }
    slugs.add(post.slug);
    let lane = columns.indexOf(post.category);
    if (lane === -1) {
      lane = columns.length;
      columns.push(post.category);
      files.push([]);
    }
    const index = records.length;
    locations.push({ lane, row: 12 + files[lane].length, slot: index });
    files[lane].push(index);
    records.push({
      id: post.slug, code: index + 1, slug: post.slug,
      title: post.title, en: post.title,
      department: post.category, category: post.category,
      clearance: 'PUBLIC ARCHIVE', source: `/posts/${post.slug}/`,
    });
  }
  return { columns, records, files, locations };
}
