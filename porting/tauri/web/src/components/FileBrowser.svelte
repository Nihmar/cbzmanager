<script lang="ts">
  import type { DirEntry } from '../lib/types';

  export let entries: DirEntry[] = [];
  export let selectedFile: string | null = null;
  export let loading = false;

  // Parent provides this callback; event name mirrors Svelte convention.
  export let onSelect: (entry: DirEntry) => void = () => {};
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
        on:click={() => onSelect(entry)}
        role="button"
        tabindex="0"
        on:keydown={(e) => e.key === 'Enter' && onSelect(entry)}
        title={entry.name}
      >
        {#if entry.thumbnail}
          <img src={entry.thumbnail} alt="" class="thumb" loading="lazy" />
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

  .name {
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
