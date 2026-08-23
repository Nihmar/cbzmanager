import { writable } from 'svelte/store';

/**
 * Shared thumbnail resolution (px), mirrored against Lazarus main.pas ZoomScroll
 * (Min=48, Max=320, Default=128). Both the file browser and the page preview grid
 * read this store so dragging the zoom slider resizes every thumbnail at once.
 */
export const thumbnailSize = writable<number>(128);
