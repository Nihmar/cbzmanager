<script lang="ts">
  import {
    pageDataUrl,
    applyBatchEdit,
    listEntries,
    readEntryBytes,
    mimeFromBytes,
  } from '../lib/api';
  import type { BatchEditParams, ColorAdjustParams, PageState } from '../lib/types';

  export let open = false;
  export let filePath = '';

  // Applied after a successful batch edit: replaces the working page list so
  // the StageBar can persist it with pageSave.
  export let onApply: (pages: PageState[]) => void = () => {};

  // Called when the dialog is dismissed (close button / backdrop click).
  export let onClose: () => void = () => {};

  // Colour-adjust defaults mirror rust_core batch_edit ColorAdjustParams.
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

  // Split cut lines (normalised 0-1 positions) + orientation, mirroring
  // Lazarus udlgbatchedit's direction radio.
  let newLine = '50';
  let cutLines: number[] = [];
  let horizontalLines = true;

  // Page-count header (GAPS 3.7): input page count comes from the archive entry
  // listing; output pieces = pages × (cutLines + 1) when any split lines exist.
  let pageCount = 0;

  $: pieceFactor = cutLines.length > 0 ? cutLines.length + 1 : 1;
  $: outputPages = pageCount * pieceFactor;
  $: applyHeader =
    outputPages === pageCount
      ? `Apply to ${pageCount} page(s)`
      : `Apply to ${pageCount} pages \u2192 ${outputPages} pieces`;

  // Live preview of the first page under the current transform (GAPS 3.6). The
  // archive bytes are fetched once per entry name; colour/resize changes are then
  // applied with cheap CSS so dragging sliders never re-reads the file.
  let previewUrl = '';
  let previewLoading = false;
  let previewName = '';
  let previewLoadedKey = -1;

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
  $: previewTransform = previewScale ? `scale(${previewScale})` : '';

  async function loadPreviewImage(name: string) {
    const key = ++previewLoadedKey;
    previewName = name;
    previewUrl = '';
    previewLoading = true;
    try {
      const { data } = await readEntryBytes(filePath, name);
      if (key !== previewLoadedKey) return; // stale fetch
      const mime = mimeFromBytes(data);
      if (previewUrl) URL.revokeObjectURL(previewUrl);
      previewUrl = URL.createObjectURL(new Blob([data as unknown as BlobPart], { type: mime }));
    } catch (e) {
      previewUrl = '';
    } finally {
      previewLoading = false;
    }
  }

  let loading = false;
  let error = '';
  let resultPages: PageState[] = [];

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

  // Re-fetch the preview when the dialog opens or the target file changes.
  let dirKey = '';
  $: if (filePath !== dirKey) {
    dirKey = filePath;
    syncFirstEntry();
  }

  async function syncFirstEntry() {
    previewName = '';
    pageCount = 0;
    if (!open || !filePath) return;
    try {
      const entries = await listEntries(filePath);
      pageCount = entries.length;
      if (entries[0]) {
        previewName = entries[0].name;
        loadPreviewImage(previewName);
      }
    } catch {
      pageCount = 0;
    }
  }

  function close() {
    onClose();
  }

  $: if (open) {
    resultPages = [];
    error = '';
    loading = false;
  }

  // Tear down the live preview when the dialog closes.
  $: if (!open) {
    previewUrl = '';
    previewLoading = false;
  }

  async function run() {
    if (!filePath || loading) return;
    loading = true;
    error = '';
    try {
      const pages = await applyBatchEdit(filePath, buildParams());
      resultPages = pages.slice(0, 48);
      onApply(pages);
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }
</script>

{#if open}
<div class="backdrop" on:click={close}>
  <div class="panel" role="dialog" aria-label="Batch edit" on:click|stopPropagation>
    <div class="head">
      <h2>Batch edit pages</h2>
      <div class="head-sub">
        <span class="dim">All pages in <code>{filePath}</code></span>
        <span class="apply-header">{applyHeader}</span>
      </div>
      <button class="icon-btn" aria-label="Close" on:click={close}>×</button>
    </div>

  <div class="grid">
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
        <label><input type="radio" name="cutdir" checked={horizontalLines} on:change={() => (horizontalLines = true)} disabled={loading} /> Horizontal</label>
        <label><input type="radio" name="cutdir" checked={!horizontalLines} on:change={() => (horizontalLines = false)} disabled={loading} /> Vertical</label>
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
      <span class="hint">{cutLines.length} line(s) → {cutLines.length + 1} piece(s) per page.</span>
    </fieldset>
  </div>

  <div class="preview-wrap">
    <div class="preview-head">Live preview</div>
    {#if previewLoading}
      <div class="preview-status">Reading first page…</div>
    {:else if previewUrl}
      <div class="preview-stage">
        <img
          class="preview-img"
          src={previewUrl}
          alt="First page (approximate preview)"
          style="transform:{previewTransform};filter:{previewFilter};"
        />
      </div>
    {:else}
      <div class="preview-status">No pages to preview.</div>
    {/if}
  </div>

  <button class="run-btn" on:click={run} disabled={loading}>
    {loading ? 'Applying…' : 'Apply to all pages'}
  </button>

  {#if error}
    <p class="err">{error}</p>
  {/if}

  {#if resultPages.length}
    <div class="summary">
      <span class="good">{resultPages.length} page(s) produced</span>
    </div>
    <div class="thumb-grid">
      {#each resultPages as page (page.name)}
        {#if page.data}
          <img src={pageDataUrl(page.data, page.name)} alt={page.name} loading="lazy" />
        {/if}
      {/each}
    </div>
  {/if}
  </div>
  </div>
{/if}

<style>
  .panel {
    border: 1px solid #ddd;
    border-radius: 6px;
    padding: 14px;
    background: #fff;
    box-shadow: 0 2px 10px rgba(0, 0, 0, 0.08);
    display: flex;
    flex-direction: column;
    gap: 12px;
  }

  .backdrop { position: fixed; inset: 0; background: rgba(0, 0, 0, 0.45); display: flex; align-items: center; justify-content: center; z-index: 1000; }
  .icon-btn { border: none; background: transparent; font-size: 20px; line-height: 1; cursor: pointer; color: #555; padding: 2px; }
  .head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; }
  .head h2 { margin: 0; font-size: 15px; }
  .hint { color: #888; font-size: 12px; }
  .dim { color: #888; font-size: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .code, code { background: #f0f0f0; padding: 1px 4px; border-radius: 3px; font-size: 12px; }

  .grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; }
  fieldset { border: 1px solid #e0e0e0; border-radius: 6px; padding: 8px 10px; margin: 0; display: flex; flex-direction: column; gap: 6px; }
  legend { font-size: 12px; font-weight: 600; color: #444; padding: 0 4px; }
  label { font-size: 12px; color: #333; display: flex; align-items: center; gap: 6px; }
  input[type="number"] { width: 56px; padding: 3px 5px; border: 1px solid #ccc; border-radius: 4px; font-size: 12px; }

  .chk { display: flex; gap: 10px; }
  .sliders { display: grid; grid-template-columns: 1fr 1fr; gap: 4px 8px; }

  .line-row { display: flex; align-items: center; gap: 6px; }
  .add-btn, .rm { font-size: 12px; padding: 3px 8px; border: 1px solid #ccc; border-radius: 4px; background: #fafafa; cursor: pointer; }
  .rm { padding: 1px 7px; }
  .lines { list-style: none; margin: 0; padding: 0; display: flex; flex-wrap: wrap; gap: 4px 8px; font-size: 12px; }
  .lines li { display: flex; align-items: center; gap: 3px; color: #555; }

  .head-sub {
    display: flex;
    align-items: baseline;
    gap: 10px;
    flex-wrap: wrap;
  }

  .apply-header {
    font-size: 12px;
    font-weight: 600;
    color: #2b6cb0;
    font-variant-numeric: tabular-nums;
  }

  .preview-wrap {
    display: flex;
    flex-direction: column;
    gap: 4px;
  }

  .preview-head {
    font-size: 12px;
    color: #888;
  }

  .preview-stage {
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 160px;
    background: #fafafa;
    border: 1px solid #eee;
    border-radius: 6px;
    padding: 8px;
  }

  .preview-img {
    max-width: 100%;
    max-height: 200px;
    display: block;
    border-radius: 3px;
  }

  .preview-status {
    color: #888;
    font-size: 12px;
    padding: 20px;
  }
  .run-btn:disabled { opacity: 0.7; }

  .summary { margin: 2px 0; font-size: 13px; }
  .good { color: #38a169; }

  .thumb-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(96px, 1fr)); gap: 6px; max-height: 220px; overflow-y: auto; }
  .thumb-grid img { width: 100%; height: auto; display: block; border-radius: 3px; border: 1px solid #eee; }

  .err { color: #c53030; font-size: 13px; margin: 6px 0; }
</style>
