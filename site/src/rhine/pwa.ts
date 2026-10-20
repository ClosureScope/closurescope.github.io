// Do not install the reference service worker over generated blog pages.
// Offline caching is outside this first integration.
export const pwaSettingsMarkup = () => '';
export async function initPwa(_notify: (message: string) => void) {}
