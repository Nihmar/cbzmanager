import { writable } from 'svelte/store';

export interface AppSettings {
  maxWebpThreads: number;
  validateThreads: number;
}

export const settings = writable<AppSettings>({
  maxWebpThreads: 0,
  validateThreads: 0,
});
