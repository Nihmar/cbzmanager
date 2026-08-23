<script lang="ts">
  import { pageEditSingle, readEntryBytes, mimeFromBytes } from '../lib/api';
  import type { BatchEditParams, ColorAdjustParams, PageState } from '../lib/types';

  // GAPS 2.8 + 3.8: single-page editor modal opened from the floating PageViewer
  // "Edit" button (Lazarus main.pas:1261-1270 opens TdlgPageEditor). Operates on
  // one page via the in-memory working list and stages the edited piece back
  // through onApply so StageBar persists it with pageSave.

  export let open = false;
  export let filePath = '';
  /** Current working page list (snapshotted from the store at open time). */
  export let pages: PageState[] = [];
  export let index = 0;

  // Dismissed without applying — keep the viewer open for further edits.
  export let onClose: () => void = () => {};
  // Applied result replaces the working page list so StageBar can persist it.
  export let onApply: (pages: PageState[]) => void = () => {};

  let width = '760px';

  // Colour-adjust defaults mirror rust_core::batch_edit ColorAdjustParams.
  let grayscale = false;
  let sepia = false;
  let invert = false;
  let redGain = 1.0;
  let greenGain = 1.0;
  let blueGain = 1.0;
  let saturation = 1.0;
  let contrast = 1.0;
  let brightness = 1.0;
  let gamma = 1.0;

  // Resize percentage: 0 means "no resize".
  let resizePercent = 0;

  let newLine = '50';
  let cutLines: number[] = [];
  let horizontalLines = true;

  function resetControls() {
    grayscale = false;
    sepia = false;
    invert = false;
    redGain = 1.0;
    greenGain = 1.0;
    blueGain = 1.0;
    saturation = 1.0;
    contrast = 1.0;
    brightness = 1.0;
    gamma = 1.0;
    resizePercent = 0;
    newLine = '50';
    cutLines = [];
    horizontalLines = true;
  }

  // Preview target: the page at `index` (its on-screen name is just a label).
  $: canEditTarget = open && index >= 0 && index < pages.length;
  $: targetName = canEditTarget ? pages[index].name : '';

  // Live preview of the current transform (GAPS 3.6 intent, per-page variant). The
  // archive bytes are fetched once; colour/resize changes are applied with cheap CSS
  // so dragging sliders never re-reads the file.
  let previewUrl = '';
  let previewLoading = false;
  let previewError = '';
  let loadSeq = 0;

  $: previewFilter = [
    grayscale ? 'grayscale(1)' : '',
    sepia ? 'sepia(1)' : '',
    invert ? 'invert(1)' : '',
    saturation !== 1 ? `saturation(${saturation})` : '',
    contrast !== 1 ? `contrast(${contrast})` : '',
    brightness !== 1 ? `brightness(${brightness})` : '',
  ]
    .filter((t) => t.length > 0)
    .join(' ');

  $: previewScale = resizePercent === 0 || resizePercent === 100 ? undefined : `${resizePercent / 100}`;
  $: previewStyle =
    `scale(${previewScale})` + (previewScale ? ' ' : '') + `filter:${previewFilter};`;

  function colorAdjust(): ColorAdjustParams {
    return {
      grayscale,
      sepia,
      invert,
      red_gain: redGain,
      green_gain: greenGain,
      blue_gain: blueGain,
      saturation,
      contrast,
      brightness,
      gamma,
    };
  }

  function buildParams(): BatchEditParams {
    return {
      resize_percent: resizePercent,
      color_adjust: colorAdjust(),
      cut_lines: cutLines,
      horizontal_lines: horizontalLines,
    };
  }

  async function loadTarget() {
    const myKey = ++loadSeq;
    previewLoading = true;
    previewError = '';
    previewUrl = '';
    if (!canEditTarget || !filePath) return;
    try {
      const { data } = await readEntryBytes(filePath, targetName);
      if (myKey !== loadSeq) return; // stale fetch
      const mime = mimeFromBytes(data);
      if (previewUrl) URL.revokeObjectURL(previewUrl);
      previewUrl = URL.createObjectURL(new Blob([data as unknown as BlobPart], { type: mime }));
    } catch (e) {
      previewError = String(e);
    } finally {
      previewLoading = false;
    }
  }

  let loading = false;
  let error = '';

  // Reload the preview when the dialog opens or the target page changes.
  $: if (canEditTarget) {
    resetControls();
    loadSeq += 1;
    loadTarget();
  }

  // Tear down the live preview when the dialog closes.
  $: if (!open) {
    previewUrl = '';
    previewLoading = false;
    error = '';
  }

  function close() {
    onClose();
  }

  async function run() {
    if (!canEditTarget || loading || !filePath) return;
    loading = true;
    error = '';
    try {
      const result = await pageEditSingle(pages, index, buildParams());
      onApply(result);
      close();
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }

  function addLine() {
    const n = parseFloat(newLine);
    if (Number.isNaN(n) || n < 0 || n > 1) return;
    if (!cutLines.includes(n)) {
      cutLines = [...cutLines, n].sort((a, b) => a - b);
    }
    newLine = '50';
  }

  function removeLine(i: number) {
    cutLines = cutLines.filter((_, idx) => idx !== i);
  }

  function onKeydown(event: KeyboardEvent) {
    if (open && event.key === 'Escape') close();
  }
</script>

<svelte:window on:keydown={onKeydown} />

{#if open}
  <div class="backdrop" on:click={close}>
    <div
      class="dialog"
      role="dialog"
      aria-modal="true"
      aria-label="Edit page"
      on:click|stopPropagation
      style="width:{width}px;"
    >
      <header class="titlebar">
        <span>Edit page · {canEditTarget ? targetName : '(none selected)'}</span>
        <button class="icon-btn" aria-label="Close" on:click={close}>×</button>
      </header>

      <div class="body">
        <div class="layout">
          <div class="preview-stage">
            {#if previewLoading}
              <div class="status">Reading page…</div>
            {:else if previewError}
              <div class="status err">{previewError}</div>
            {:else if previewUrl}
              <img
                class="preview-img"
                src={previewUrl}
                alt={targetName}
                style="transform:scale({previewScale});filter:{previewFilter};"
              />
            {:else}
              <div class="status">No page to preview.</div>
            {/if}
          </div>

          <div class="controls">
            <fieldset>
              <legend>Resize</legend>
              <label>Scale (%)
                <input type="number" min="0" max="200" bind:value={resizePercent} disabled={loading} />
              </label>
              <span class="hint">0 keeps original size.</span>
            </fieldset>

            <fieldset>
              <legend>Colours</legend>
              <div class="chk">
                <label><input type="checkbox" bind:checked={grayscale} disabled={loading} /> Grayscale</label>
                <label><input type="checkbox" bind:checked={sepia} disabled={loading} /> Sepia</label>
                <label><input type="checkbox" bind:checked={invert} disabled={loading} /> Invert</label>
              </div>
              <div class="sliders">
                <label>R <input type="number" min="0" step="0.1" bind:value={redGain} /></label>
                <label>G <input type="number" min="0" step="0.1" bind:value={greenGain} /></label>
                <label>B <input type="number" min="0" step="0.1" bind:value={blueGain} /></label>
                <label>Saturation <input type="number" min="0" step="0.1" bind:value={saturation} /></label>
                <label>Contrast <input type="number" min="0" step="0.1" bind:value={contrast} /></label>
                <label>Brightness <input type="number" min="0" step="0.1" bind:value={brightness} /></label>
                <label>Gamma <input type="number" min="0" step="0.1" bind:value={gamma} /></label>
              </div>
            </fieldset>

            <fieldset>
              <legend>Split (cut lines)</legend>
              <div class="chk" role="radiogroup" aria-label="Cut direction">
                <label><input type="radio" name="cutedir" checked={horizontalLines} on:change={() => (horizontalLines = true)} disabled={loading} /> Horizontal</label>
                <label><input type="radio" name="cutedir" checked={!horizontalLines} on:change={() => (horizontalLines = false)} disabled={loading} /> Vertical</label>
              </div>
              <div class="line-row">
                <input type="number" min="0" max="100" step="1" bind:value={newLine} placeholder="50%" disabled={loading} />
                <button type="button" class="add-btn" on:click={addLine} disabled={loading}>Add line</button>
              </div>
              {#if cutLines.length}
                <ul class="lines">
                  {#each cutLines as n, i}
                    <li>{Math.round(n * 100)}% <button type="button" class="rm" on:click={() => removeLine(i)}>✕</button></li>
                  {/each}
                </ul>
              {/if}
              <span class="hint">{cutLines.length} line(s) → {cutLines.length + 1} piece(s).</span>
            </fieldset>
          </div>
        </div>

        {#if error}
          <p class="err">{error}</p>
        {/if}
      </div>

      <footer class="actions">
        <button type="button" class="btn" on:click={close} disabled={loading}>Cancel</button>
        <button type="button" class="btn btn-primary" on:click={run} disabled={loading || !canEditTarget}>
          {loading ? 'Applying…' : 'Apply'}
        </button>
      </footer>
    </div>
  </div>
{/if}

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.45);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 1200; /* above PageViewer's overlay (z-index 1100) */
  }

  .dialog {
    width: var(--dlg-width, 760px);
    max-width: calc(100vw - 32px);
    max-height: calc(100vh - 48px);
    display: flex;
    flex-direction: column;
    background: #fff;
    border-radius: 6px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.35);
    overflow: hidden;
  }

  .titlebar {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 8px 12px;
    background: #f0f0f0;
    border-bottom: 1px solid #ddd;
    font-size: 14px;
    font-weight: 600;
  }

  .icon-btn {
    border: none;
    background: transparent;
    font-size: 18px;
    line-height: 1;
    cursor: pointer;
    padding: 0 4px;
    color: #555;
  }

  .body {
    padding: 12px;
    overflow-y: auto;
  }

  .layout {
    display: grid;
    grid-template-columns: minmax(260px, 1fr) auto;
    gap: 16px;
    align-items: start;
  }

  .preview-stage {
    display: flex;
    align-items: center;
    justify-content: center;
    min-height: 240px;
    background: #fafafa;
    border: 1px solid #eee;
    border-radius: 6px;
    padding: 8px;
  }

  .preview-img {
    max-width: 100%;
    max-height: 320px;
    display: block;
    border-radius: 3px;
    transform-origin: center center;
  }

  .status {
    color: #888;
    font-size: 12px;
    padding: 20px;
  }

  .controls {
    display: flex;
    flex-direction: column;
    gap: 10px;
    min-width: 240px;
  }

  fieldset {
    border: 1px solid #e0e0e0;
    border-radius: 6px;
    padding: 8px 10px;
    margin: 0;
    display: flex;
    flex-direction: column;
    gap: 6px;
  }

  legend {
    font-size: 12px;
    font-weight: 600;
    color: #444;
    padding: 0 4px;
  }

  label {
    font-size: 12px;
    color: #333;
    display: flex;
    align-items: center;
    gap: 6px;
  }

  input[type="number"] {
    width: 56px;
    padding: 3px 5px;
    border: 1px solid #ccc;
    border-radius: 4px;
    font-size: 12px;
  }

  .chk { display: flex; gap: 10px; }
  .sliders { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 8px; }

  .line-row { display: flex; align-items: center; gap: 6px; }
  .add-btn,
  .rm {
    font-size: 12px;
    padding: 3px 8px;
    border: 1px solid #ccc;
    border-radius: 4px;
    background: #fafafa;
    cursor: pointer;
  }
  .rm { padding: 1px 7px; }

  .lines {
    list-style: none;
    margin: 0;
    padding: 0;
    display: flex;
    flex-wrap: wrap;
    gap: 4px 8px;
    font-size: 12px;
  }
  .lines li {
    display: flex;
    align-items: center;
    gap: 3px;
    color: #555;
  }

  .hint { color: #888; font-size: 12px; }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    padding: 10px 12px;
    border-top: 1px solid #eee;
    background: #fbfbfb;
  }

  .btn {
    padding: 6px 14px;
    border: 1px solid #ccc;
    border-radius: 5px;
    background: #fff;
    font-size: 13px;
    cursor: pointer;
  }
  .btn:hover { background: #f4f4f4; }
  .btn-primary {
    border-color: #2b6cb0;
    background: #2b6cb0;
    color: #fff;
  }
  .btn-primary:hover { background: #2c5282; }
  .btn[disabled] { opacity: 0.6; cursor: default; }

  .err { color: #c53030; font-size: 13px; margin: 6px 0 0; }
</style>
