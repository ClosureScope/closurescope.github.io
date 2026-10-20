import { createArchiveIndex } from '../../../scripts/archive-index.mjs';

export interface ArchiveRecord {
  id: string;
  code: number;
  slug: string;
  title: string;
  en: string;
  department: string;
  category: string;
  clearance: string;
  source: string;
}

const content = createArchiveIndex(JSON.parse(document.querySelector('#blog-index')!.textContent!));
export const records: ArchiveRecord[] = content.records;
export const archiveColumns: string[] = content.columns;
export const categories = ['全部档案', ...archiveColumns];

// Identity is independent of the rendering pool and its fixed capacity.
let rowOrigin = 0;
export const archiveRowOrigin = () => rowOrigin;
export const rebaseArchiveRows = (shift: number) => { rowOrigin += shift; };
export const resetArchiveRows = () => { rowOrigin = 0; };
export const columnFiles = (lane: number): number[] => content.files[lane] ?? [];
export function fileLocation(index: number) {
  const location = content.locations[index];
  return { ...location, row: location.row - rowOrigin };
}
// The authored opening extracts the central physical lane (2). Keep that
// composition while the UI numbers real categories from zero.
export function sceneLocation(index: number) {
  const location = fileLocation(index);
  return { ...location, lane: location.lane + 2 };
}
// Legacy name retained for the upstream scene; slots now identify records.
export const fileAtSlot = (slot: number) => slot;
