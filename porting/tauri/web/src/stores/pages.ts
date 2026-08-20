import { writable } from 'svelte/store';
import type { PageState } from '../lib/types';

/** Current page list for the selected file */
export const pages = writable<PageState[]>([]);

/** Whether there are pending unsaved changes */
export const hasChanges = writable(false);
