<script lang="ts">
  import { pageDataUrl } from '../lib/api';
  import type { PageState } from '../lib/types';

  export let pages: PageState[] = [];
  export let fileName: string | null = null;
  export let filePath: string = '';
  export let loading = false;

  export let onOpenViewer: (index: number) => void = () => {};
  export let onHighlight: (index: number) => void = () => {};
</script>

{#if !fileName}
  <div class="empty">Select a CBZ file to preview its pages.</div>
{:else if loading}
  <div class="empty">Loading pages…</div>
{:else if pages.length === 0}
  <div class="empty">No pages loaded for this file.</div>
{:else}
  <div class="page-grid">
    {#each pages as page, i (i)}
      {#if !page.gone}
        <div
          class="page-card"
          on:pointerdown={() => onHighlight(i)}
          on:dblclick={() => onOpenViewer(i)}
          role="button"
          tabindex="0"
          on:keydown={(e) => e.key === 'Enter' && onOpenViewer(i)}
        >
          {#if page.data}
            <img src={pageDataUrl(page.data, page.name)} alt={page.name} loading="lazy" />
          {/if}
          <div class="caption">{page.name}</div>
        </div>
      {/if}
    {/each}
  </div>
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
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 10px;
    padding-bottom: 40px;
  }

  .page-card {
    border: 1px solid #ddd;
    border-radius: 4px;
    padding: 4px;
    cursor: pointer;
    text-align: center;
    background: #fff;
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
</style>
