<script lang="ts">
  import { onMount } from 'svelte';
  import BaseDialog from './BaseDialog.svelte';
  import { readEntryBytes, mimeFromBytes } from '../lib/api';

  export let open: boolean = false;
  export let filePath: string = '';
  export let pageNames: string[] = [];
  export let startIndex = 0;

  let stage: HTMLDivElement;
  let imgEl: HTMLImageElement | null = null;
  let src: string | null = null;
  let loading = false;
  let error = '';
  let idx = startIndex;
  let scale = 1;
  let panX = 0;
  let panY = 0;
  let dragging = false;
  let dragStartX = 0;
  let dragStartY = 0;

  onMount(() => {
    if (!stage) return;
    stage.addEventListener('wheel', onWheelNative, { passive: false });
    return () => stage.removeEventListener('wheel', onWheelNative);
  });

  // Zoom model parity with Lazarus udlgpageview + uimgutil.CenterAnchorScrollPos
  // (GAPS 6.2):
  //   - Ctrl+wheel : zoom anchored under the cursor, scale clamp 1.0-5.0
  //   - plain wheel: vertical pan (top-to-bottom)
  //   - Shift+wheel: horizontal pan
  function onWheelNative(event: WheelEvent) {
    event.preventDefault();
    const step = sign(event.deltaY);

    if (event.ctrlKey) {
      if (!imgEl || !stage) return;
      const factor = step > 0 ? 1.1 : 1 / 1.1;
      const newScale = Math.min(5, Math.max(1, scale * factor));
      if (newScale === scale) return; // no-op at clamp boundary

      // Cursor offset from stage centre (CSS px).
      const rect = stage.getBoundingClientRect();
      const cx = event.clientX - rect.left - rect.width / 2;
      const cy = event.clientY - rect.top - rect.height / 2;
      // Rendered image size at the CURRENT scale.
      const curW = imgEl.offsetWidth;
      const curH = imgEl.offsetHeight;
      if (curW <= 0 || curH <= 0) { scale = newScale; return; }

      // Keep the image point under the cursor fixed: its normalised position is
      // (cx - panX) / curW, which after zooming maps to a new centre offset.
      const ratio = newScale / scale;
      panX = cx - (cx - panX) * ratio;
      panY = cy - (cy - panY) * ratio;
      scale = newScale;
    } else if (event.shiftKey) {
      // Horizontal pan.
      panX -= step * 40;
    } else {
      // Vertical pan (scroll down scrolls the page upward).
      panY += step * 40;
    }
  }

  function sign(v: number): number {
    return v < 0 ? -1 : 1;
  }

  $: if (open) {
    idx = startIndex;
    scale = 1;
    panX = 0;
    panY = 0;
    loadCurrent();
  }

  async function loadCurrent() {
    const name = pageNames[idx];
    if (!name || !filePath) return;
    loading = true;
    error = '';
    src = null;
    scale = 1;
    panX = 0;
    panY = 0;
    try {
      const { data } = await readEntryBytes(filePath, name);
      const mime = mimeFromBytes(data);
      if (src) URL.revokeObjectURL(src);
      src = URL.createObjectURL(new Blob([data as unknown as BlobPart], { type: mime }));
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }

  function prev() {
    if (idx > 0) { idx--; loadCurrent(); }
  }

  function next() {
    if (idx < pageNames.length - 1) { idx++; loadCurrent(); }
  }

  function close() {
    open = false;
  }

  function onPointerDown(event: PointerEvent) {
    dragging = true;
    dragStartX = event.clientX - panX;
    dragStartY = event.clientY - panY;
  }

  function onPointerMove(event: PointerEvent) {
    if (!dragging) return;
    panX = event.clientX - dragStartX;
    panY = event.clientY - dragStartY;
  }

  function onPointerUp() {
    dragging = false;
  }

  function windowKeydown(event: KeyboardEvent) {
    if (!open) return;
    if (event.key === 'Escape') close();
    else if (event.key === 'ArrowRight') next();
    else if (event.key === 'ArrowLeft') prev();
  }
</script>

<svelte:window on:keydown={windowKeydown} />

{#if open}
  <div class="backdrop" on:click={close}>
    <div class="viewer" on:click|stopPropagation>

      {#if pageNames.length > 1}
        <button class="nav prev" on:click={prev} aria-label="Previous page">‹</button>
        <button class="nav next" on:click={next} aria-label="Next page">›</button>
      {/if}

      <div class="stage" bind:this={stage}
           on:pointerdown={onPointerDown} on:pointermove={onPointerMove} on:pointerup={onPointerUp} on:pointercancel={onPointerUp}>
        {#if loading}
          <div class="loading">Loading full resolution…</div>
        {:else if error}
          <div class="err">{error}</div>
        {:else if src}
          <img class="page" bind:this={imgEl} src={src} alt={pageNames[idx]} style="transform: scale({scale}) translate({panX / scale}px, {panY / scale}px);" draggable="false" />
          <div class="idx">{idx + 1} / {pageNames.length}</div>
        {/if}
      </div>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.9);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1100;
    color: #ddd;
    font-size: 14px;
  }

  .viewer {
    position: relative;
    max-width: 92vw;
    max-height: 92vh;
    cursor: grab;
    user-select: none;
  }

  .viewer:active { cursor: grabbing; }

  .stage {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 300px;
    min-height: 200px;
  }

  .page {
    max-width: 92vw;
    max-height: 92vh;
    object-fit: contain;
  }

  .loading, .err { padding: 40px; }
  .err { color: #fc8181; }

  .idx {
    position: absolute;
    bottom: 10px;
    left: 50%;
    transform: translateX(-50%);
    background: rgba(0, 0, 0, 0.6);
    padding: 3px 10px;
    border-radius: 12px;
    font-size: 12px;
  }

  .nav {
    position: fixed;
    top: 50%;
    transform: translateY(-50%);
    background: rgba(0, 0, 0, 0.4);
    color: #fff;
    border: none;
    font-size: 36px;
    width: 48px;
    height: 48px;
    border-radius: 50%;
    cursor: pointer;
  }

  .nav.prev { left: 16px; }
  .nav.next { right: 16px; }
  .nav:hover { background: rgba(255, 255, 255, 0.2); }
</style>
