<script lang="ts">
  import { pages as pagesStore, hasChanges } from '../stores/pages';
  import { thumbnailSize } from '../stores/thumbnail';
  import {
    pageDataUrl,
    pageMoveUp,
    pageMoveDown,
    pageMoveToStart,
    pageMoveToEnd,
    pageDragDrop,
  } from '../lib/api';
  import type { PageState } from '../lib/types';

  export let pages: PageState[] = [];
  export let fileName: string | null = null;
  export let filePath: string = '';
  export let loading = false;

  export let onOpenViewer: (index: number) => void = () => {};
  export let onHighlight: (index: number) => void = () => {};

  // Only visible (non-deleted) pages are reorderable. Each entry carries the
  // global array index (for viewer/open) and its zero-based visible slot index
  // (what the page-model commands operate on).
  interface Slot {
    page: PageState;
    globalIndex: number;
  }

  $: slots = pages
    .map((page, globalIndex): Slot => ({ page, globalIndex }))
    .filter(({ page }) => !page.gone);

  // Card width driven by the shared zoom slider (clamped like Lazarus thumb range).
  $: cardW = Math.max(80, Math.min($thumbnailSize, 260));

  // Context menu (right-click) state.
  let menuIndex = -1;
  let menuX = 0;
  let menuY = 0;
  let draggingIndex = -1;

  function closeMenu() {
    menuIndex = -1;
  }

  async function runMove(fn: (pages: PageState[]) => Promise<PageState[]>, slot: number) {
    const next = await fn(pages);
    pagesStore.set(next);
    hasChanges.set(true);
    closeMenu();
  }

  function onContextMenu(event: MouseEvent, globalIndex: number, slot: number) {
    event.preventDefault();
    menuIndex = globalIndex;
    menuX = event.clientX;
    menuY = event.clientY;
  }

  async function onDropOverPage(e: DragEvent, slot: number) {
    e.preventDefault();
    if (draggingIndex >= 0 && draggingIndex !== slot) {
      const reordered = await pageDragDrop(pages, draggingIndex, slot);
      pagesStore.set(reordered);
      hasChanges.set(true);
    }
  }

  async function onDropPage(e: DragEvent, slot: number) {
    e.preventDefault();
    await onDropOverPage(e, slot);
    draggingIndex = -1;
  }

  function onDragStart(index: number) {
    draggingIndex = index;
  }
</script>

<svelte:window on:click={closeMenu} />

{#if !fileName}
  <div class="empty">Select a CBZ file to preview its pages.</div>
{:else if loading}
  <div class="empty">Loading pages…</div>
{:else if slots.length === 0}
  <div class="empty">{pages.length === 0 ? 'No pages loaded for this file.' : 'All pages deleted (mark with Del).'}</div>
{:else}
  <div class="page-grid">
    {#each slots as { page, globalIndex }, slot (globalIndex)}
      {#if !page.gone}
        <div
          class="page-card"
          style="width:{cardW}px;"
          draggable="true"
          on:dragstart={() => onDragStart(slot)}
          on:dragover={(e) => onDropOverPage(e, slot)}
          on:drop={(e) => onDropPage(e, slot)}
          on:dragleave={() => (draggingIndex = -1)}
          on:pointerdown={() => onHighlight(globalIndex)}
          on:dblclick={() => onOpenViewer(globalIndex)}
          on:contextmenu={(e) => onContextMenu(e, globalIndex, slot)}
          role="button"
          tabindex="0"
          on:keydown={(e) => e.key === 'Enter' && onOpenViewer(globalIndex)}
          title={page.name}
        >
          {#if page.data}
            <img src={pageDataUrl(page.data, page.name)} alt={page.name} loading="lazy" />
          {/if}
          <div class="caption">{page.name}</div>
        </div>
      {/if}
    {/each}
  </div>

  {#if menuIndex >= 0}
    <div class="menu" role="menu" style="left:{menuX}px;top:{menuY}px;">
      <button type="button" on:click={() => runMove((p) => pageMoveUp(p, menuIndex), menuIndex)} aria-label="Move up">↑ Move up</button>
      <button type="button" on:click={() => runMove((p) => pageMoveDown(p, menuIndex), menuIndex)} aria-label="Move down">↓ Move down</button>
      <span class="sep"></span>
      <button type="button" on:click={() => runMove((p) => pageMoveToStart(p, menuIndex), menuIndex)} aria-label="Move to top">↑↑ Move to top</button>
      <button type="button" on:click={() => runMove((p) => pageMoveToEnd(p, menuIndex), menuIndex)} aria-label="Move to bottom">↓↓ Move to bottom</button>
    </div>
  {/if}
{/if}

<style>
  .empty {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: #888;
    font-size: 14px;
  }

  .page-grid {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    padding: 10px;
    align-content: flex-start;
  }

  .page-card {
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 4px;
    cursor: pointer;
    text-align: center;
    background: #fff;
    user-select: none;
  }

  .page-card:hover { border-color: #2b6cb0; box-shadow: 0 1px 6px rgba(43, 108, 176, 0.2); }

  .page-card img {
    width: 100%;
    height: auto;
    display: block;
    border-radius: 2px;
  }

  .caption {
    font-size: 10px;
    color: #666;
    margin-top: 3px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .menu {
    position: fixed;
    z-index: 1200;
    background: #fff;
    border: 1px solid #ddd;
    border-radius: 6px;
    box-shadow: 0 3px 12px rgba(0, 0, 0, 0.18);
    padding: 4px;
    min-width: 150px;
    font-size: 13px;
  }

  .menu button {
    display: block;
    width: 100%;
    text-align: left;
    border: none;
    background: transparent;
    padding: 6px 8px;
    cursor: pointer;
    border-radius: 4px;
    color: #333;
  }

  .menu button:hover { background: #eef5ff; }

  .sep { height: 1px; background: #e0e0e0; margin: 3px 2px; }
</style>
