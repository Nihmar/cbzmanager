/// <reference types="vite/client" />

declare module '*.svelte' {
  import type { SvelteComponentTyped } from 'svelte';
  const component: typeof SvelteComponentTyped;
  export default component;
}

interface FileSystemEntry {
  path?: string;
}

declare namespace svelteHTML {
  interface HTMLAttributes {
    webkitdirectory?: boolean | string;
    ondrop?: (event: any) => void;
    oninput?: (event: Event) => void;
  }
}
