import { invoke } from '@tauri-apps/api/core';
import { listen } from '@tauri-apps/api/event';
import type {
  DirEntry,
  PageState,
  ArchiveEntry,
  FirstImageResult,
  FileValidationResult,
  ProgressEvent,
  SaveChangesResult,
   ComicInfoResult,
   CbrConversionResult,
   MergeResult,
   ConvertWebpResult,
   BatchEditParams,
 } from './types';

// Tauri command names — must match Rust invoke_handler![] registrations
const CMD = {
  LIST_ENTRIES: 'list_entries',
  READ_ENTRY: 'read_entry',
  FIRST_IMAGE: 'first_image',
  LIST_DIRECTORY: 'list_directory',
  VALIDATE: 'cmd_validate',
  VALIDATE_DEEP: 'cmd_validate_deep',
  CONVERT_WEBP: 'cmd_convert_webp',
  MERGE: 'cmd_merge',
  CBR_TO_CBZ: 'cmd_cbr_to_cbz',
  SCAN_COMICINFO: 'cmd_scan_comicinfo',
  REMOVE_COMICINFO: 'cmd_remove_comicinfo',
   PAGE_LOAD: 'page_load',
   PAGE_SAVE: 'page_save',
   BATCH_EDIT: 'apply_batch_edit',
 };

export async function listDirectory(dirPath: string): Promise<DirEntry[]> {
  return invoke<DirEntry[]>(CMD.LIST_DIRECTORY, { dir_path: dirPath });
}

export async function listEntries(filePath: string): Promise<ArchiveEntry[]> {
  return invoke<ArchiveEntry[]>(CMD.LIST_ENTRIES, { file_path: filePath });
}

export async function readEntry(filePath: string, name: string): Promise<Uint8Array> {
  return invoke<Uint8Array>(CMD.READ_ENTRY, { file_path: filePath, name });
}

export async function firstImage(filePath: string): Promise<FirstImageResult> {
  return invoke<FirstImageResult>(CMD.FIRST_IMAGE, { file_path: filePath });
}

export async function validate(dirPath: string): Promise<FileValidationResult[]> {
  return invoke<FileValidationResult[]>(CMD.VALIDATE, { dir_path: dirPath });
}

export async function validateDeep(
  dirPath: string,
  threads?: number,
): Promise<FileValidationResult[]> {
  return invoke<FileValidationResult[]>(CMD.VALIDATE_DEEP, {
    dir_path: dirPath,
    threads,
  });
}

export async function convertWebp(
  dirPath: string,
  deleteSource: boolean,
  threads?: number,
): Promise<ConvertWebpResult> {
  return invoke<ConvertWebpResult>(CMD.CONVERT_WEBP, {
    dir_path: dirPath,
    delete_source: deleteSource,
    threads,
  });
}

export async function merge(
  dirPath: string,
  force: boolean,
  chapters?: string,
  chaptersPerVolume?: number,
  deleteSource: boolean = false,
): Promise<MergeResult> {
  return invoke<MergeResult>(CMD.MERGE, {
    dir_path: dirPath,
    force,
    chapters,
    chapters_per_volume: chaptersPerVolume,
    delete_source: deleteSource,
  });
}

export async function cbrToCbz(
  dirPath: string,
  deleteSource: boolean,
  threads?: number,
): Promise<CbrConversionResult[]> {
  return invoke<CbrConversionResult[]>(CMD.CBR_TO_CBZ, {
    dir_path: dirPath,
    delete_source: deleteSource,
    threads,
  });
}

export async function scanComicinfo(dirPath: string): Promise<ComicInfoResult[]> {
  return invoke<ComicInfoResult[]>(CMD.SCAN_COMICINFO, { dir_path: dirPath });
}

export async function removeComicinfo(
  dirPath: string,
  backup: boolean = false,
  threads?: number,
): Promise<ComicInfoResult[]> {
  return invoke<ComicInfoResult[]>(CMD.REMOVE_COMICINFO, {
    dir_path: dirPath,
    backup,
    threads,
  });
}

export async function pageLoad(filePath: string): Promise<PageState[]> {
  return invoke<PageState[]>(CMD.PAGE_LOAD, { file_path: filePath });
}

export async function pageSave(
  pages: PageState[],
  filePath: string,
): Promise<SaveChangesResult> {
  return invoke<SaveChangesResult>(CMD.PAGE_SAVE, { pages, file_path: filePath });
}

// Apply a batch edit (resize / colour adjust / split) to every page of a CBZ file.
export async function applyBatchEdit(
  filePath: string,
  params: BatchEditParams,
): Promise<PageState[]> {
  return invoke<PageState[]>(CMD.BATCH_EDIT, { file_path: filePath, params });
}

export function onProgress(callback: (event: ProgressEvent) => void): () => void {
  const unlisten = listen<ProgressEvent>('progress', (event) => {
    callback(event.payload);
  });
  return () => unlisten.then((fn) => fn());
}

// Detect image MIME type from magic bytes so pages can be rendered regardless of format.
export function mimeFromBytes(bytes: Uint8Array): string {
  const b = bytes.slice(0, 12);
  if (b.length >= 8 && b[0] === 0x89 && b[1] === 0x50 && b[2] === 0x4e && b[3] === 0x47) return 'image/png';
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return 'image/jpeg';
  if (b.length >= 12 && ((b[0] | b[1] | b[2] | b[3]) === 0 && b[7] === 0x57 && b[8] === 0x45 && b[9] === 0x42)) return 'image/webp';
  if (b.length >= 4 && b[0] === 0x42 && b[1] === 0x4d) return 'image/bmp';
  if ((b[0] | b[1] | b[2] | b[3]) === 0 && b[8] === 0x47 && b[9] === 0x49 && b[10] === 0x46) return 'image/gif';
  return 'image/png';
}

export async function readEntryBytes(
  filePath: string,
  name: string,
): Promise<{ data: Uint8Array }> {
  const bytes = await invoke<Uint8Array>(CMD.READ_ENTRY, { file_path: filePath, name });
  return { data: bytes };
}

function extToMime(name: string): string {
  const ext = name.split('.').pop()?.toLowerCase() ?? '';
  switch (ext) {
    case 'jpg':
    case 'jpeg': return 'image/jpeg';
    case 'webp': return 'image/webp';
    case 'bmp': return 'image/bmp';
    case 'gif': return 'image/gif';
    case 'tiff':
    case 'tif': return 'image/png';
    default: return 'image/png';
  }
}

// Render a stored base64 page as an <img> data URL (display only).
export function pageDataUrl(b64: string, name: string): string {
  return `data:${extToMime(name)};base64,${b64}`;
}

