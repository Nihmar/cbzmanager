<script lang="ts">
  import type { DirEntry, FileMenuAction } from '../lib/types';
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

  // Right-click a row to open the file context menu (GAPS 3.2). Actions map to the
  // Lazarus PMFiles popup subset backed by operations available without new APIs.
  export let onAction: (action: FileMenuAction, entry: DirEntry) => void = () => {};

  // Context menu state + position (same shape as PagePreview's menu).
  let menuActive = false;
  let menuX = 0;
  let menuY = 0;

  function closeMenu() {
    menuActive = false;
  }

  let menuEntry: DirEntry | null = null;

  // GAPS 3.2: ordered FileBrowser context-menu items (Lazarus PMFiles subset).
  const MENU_ITEMS: { action: FileMenuAction; label: string; sepBefore?: boolean }[] = [
    { action: 'open', label: 'Open file' },
    { action: 'comicinfo', label: 'Manage ComicInfo.xml…' },
    { action: 'validate', label: 'Validate', sepBefore: true },
    { action: 'convert', label: 'Convert to WebP…', sepBefore: true },
    { action: 'merge', label: 'Merge into volumes…', sepBefore: true },
  ];

  function onContextMenu(event: MouseEvent, entry: DirEntry) {
    event.preventDefault();
    menuX = event.clientX;
    menuY = event.clientY;
    menuActive = true;
    menuEntry = entry;
  }

  function pick(action: FileMenuAction) {
    // Close eagerly so the parent's dialog/transition can take focus back.
    closeMenu();
    if (menuEntry) onAction(action, menuEntry);
  }
</script>

<svelte:window on:click={closeMenu} />

{#if loading}
  <div class="empty">Loading…</div>
{:else if entries.length === 0}
  <div class="empty">No CBZ/CBR files in this directory.</div>
{:else}
  <div class="pane-wrap">
    {#if menuActive}
      <div class="menu" role="menu" style="left:{menuX}px;top:{menuY}px;">
        {#each MENU_ITEMS as item}
          {#if item.sepBefore}<span class="sep"></span>{/if}
          <button type="button" class="item" on:click={() => pick(item.action)} aria-label={item.label}>{item.label}</button>
        {/each}
      </div>
    {/if}
    <ul class="file-list">
      {#each entries as entry (entry.name)}
        <li
          class:selected={selectedFile === entry.name}
          class:dir={entry.is_dir}
          on:click={() => !entry.is_dir && onSelect(entry)}
          on:dblclick={() => entry.is_dir && onOpenSubdir(entry)}
          on:contextmenu={(e) => onContextMenu(e, entry)}
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
  </div>
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

  .pane-wrap { position: relative; }

  .menu {
    position: absolute;
    z-index: 600;
    min-width: 190px;
    background: #fff;
    border: 1px solid #d8d8d8;
    border-radius: 5px;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.18);
    padding: 4px 0;
  }

  .menu .item {
    display: block;
    width: 100%;
    text-align: left;
    border: none;
    background: transparent;
    padding: 7px 14px;
    font-size: 13px;
    color: #222;
    cursor: pointer;
    white-space: nowrap;
  }

  .menu .item:hover { background: #e8f0fe; }
  .menu .sep { height: 0; border-top: 1px solid #e5e5e5; margin: 4px 0; }

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
