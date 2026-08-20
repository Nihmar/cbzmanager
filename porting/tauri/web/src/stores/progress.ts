import { writable } from 'svelte/store';
import type { ProgressEvent } from '../lib/types';

export interface JobState {
  active: boolean;
  percent: number;
  message: string;
  phase: string;
  log: string[];
}

const initialState: JobState = {
  active: false,
  percent: 0,
  message: '',
  phase: '',
  log: [],
};

export const job = writable<JobState>(initialState);
