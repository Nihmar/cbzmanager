<script lang="ts">
  import type { DirEntry } from '../lib/types';
  import { thumbnailSize } from '../stores/thumbnail';

  export let entries: DirEntry[] = [];
  export let selectedFile: string | null = null;
  export let loading = false;

  // Scale the browser thumbs with the shared zoom slider (Lazarus ZoomScroll
  // affects both panes). Base size 32×40 at default 128px resolution.
  $: s = Math.max(0.5, $thumbnailSize / 128);
  $: thumbW = Math.round(32 * s);
  $: thumbH = Math.round(40 * s);

  // Parent provides these callbacks; event names mirror Svelte convention.
  // Single-click selects a file, double-click enters a subdirectory (GAPS 3.11).
  export let onSelect: (entry: DirEntry) => void = () => {};
  export let onOpenSubdir: (entry: DirEntry) => void = () => {};
</script>

{#if loading}
  <div class="empty">Loading…</div>
{:else if entries.length === 0}
  <div class="empty">No CBZ/CBR files in this directory.</div>
{:else}
  <ul class="file-list">
    {#each entries as entry (entry.name)}
      <li
        class:selected={selectedFile === entry.name}
        class:dir={entry.is_dir}
        on:click={() => !entry.is_dir && onSelect(entry)}
        on:dblclick={() => entry.is_dir && onOpenSubdir(entry)}
        role="button"
        tabindex="0"
        on:keydown={(e) => e.key === 'Enter' && !entry.is_dir && onSelect(entry)}
        title={entry.is_dir ? `${entry.name} (folder)` : entry.name}
      >
        {#if entry.is_dir}
          <span class="dir-icon">📁</span>
        {:else if entry.thumbnail}
          <img src={entry.thumbnail} style="width:{thumbW}px;height:{thumbH}px;" class="thumb" loading="lazy" alt="" />}
        {/if}
        <span class="name">{entry.name}</span>
      </li>
    {/each}
  </ul>
{/if}

<style>
  .empty {
    padding: 20px 16px;
    color: #888;
    font-size: 13px;
    text-align: center;
  }

  .file-list {
    list-style: none;
    margin: 0;
    padding: 0;
    overflow-y: auto;
  }

  li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    cursor: pointer;
    font-size: 13px;
    border-bottom: 1px solid #eee;
    white-space: nowrap;
  }

  li:hover { background: #e8f0fe; }
  li.selected { background: #d2e3fc; font-weight: 500; }

  .thumb {
    width: 32px;
    height: 40px;
    object-fit: cover;
    border-radius: 2px;
    flex-shrink: 0;
  }

  li.dir { cursor: pointer; }

  .dir-icon {
    width: 32px;
    flex-shrink: 0;
    text-align: center;
    line-height: 40px;
    font-size: 15px;
  }

  .name {
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
