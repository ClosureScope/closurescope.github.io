/** Separate the reference assets from the blog's established fonts. */
export const assetUrl = (path: string) => `${import.meta.env.BASE_URL}rhine/${path.replace(/^\//, '')}`;
