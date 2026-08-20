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

export function onProgress(callback: (event: ProgressEvent) => void): () => void {
  const unlisten = listen<ProgressEvent>('progress', (event) => {
    callback(event.payload);
  });
  return () => unlisten.then((fn) => fn());
}

