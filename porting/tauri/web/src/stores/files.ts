import { writable } from 'svelte/store';
import type { DirEntry } from '../lib/types';

/** File browser state — directory listing with thumbnails */
export const files = writable<DirEntry[]>([]);
export const selectedFile = writable<string | null>(null);

/** Current directory being browsed */
export let currentDirectory = writable<string>('');
