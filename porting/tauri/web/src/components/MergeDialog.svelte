<script lang="ts">
  import BaseDialog from './BaseDialog.svelte';
  import { merge } from '../lib/api';
  import type { MergeResult, MergeVolume } from '../lib/types';

  export let open: boolean = false;
  export let dirPath: string = '';

  let mode: 'auto' | 'chapters' | 'pervolume' = 'auto';
  let chapters = '';
  let perVolume = 0;
  let force = false;
  let deleteSource = false;

  let result: MergeResult | null = null;
  let loading = false;
  let error = '';

  $: if (open) {
    result = null;
    loading = true;
    error = '';
  }

  async function run() {
    loading = true;
    error = '';
    try {
      const cpv = mode === 'pervolume' && perVolume > 0 ? perVolume : undefined;
      result = await merge(dirPath, force, mode === 'chapters' ? chapters : undefined, cpv, deleteSource);
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }

  function close() {
    open = false;
  }
</script>

<BaseDialog
  title="Merge Chapters into Volumes"
  {open}
  cancelLabel=""
  onConfirm={run}
  onCancel={close}
  width="560px"
>
  <p class="hint">Merge chapter archives (<code>Series - NNNN.cbz</code>) into volumes (<code>Series VNNN.cbz</code>). Non-image entries are dropped.</p>

  {#if dirPath}
    <div class="dir">{dirPath}</div>
  {/if}

  <div class="modes">
    <label><input type="radio" name="m" bind:group={mode} value="auto" /> Auto (default CPV)</label>
    <label><input type="radio" name="m" bind:group={mode} value="chapters" /> Merge specific chapters</label>
    <label><input type="radio" name="m" bind:group={mode} value="pervolume" /> Chapters per volume</label>
  </div>

  {#if mode === 'chapters'}
    <label class="field">Chapters to merge (comma-separated)
      <input bind:value={chapters} placeholder="e.g. 1,2,3,4" />
    </label>
  {/if}
  {#if mode === 'pervolume'}
    <label class="field">Chapters per volume
      <input type="number" min="1" bind:value={perVolume} />
    </label>
  {/if}

  <div class="opts">
    <label><input type="checkbox" bind:checked={force} /> Force (merge into fewer volumes)</label>
    <label><input type="checkbox" bind:checked={deleteSource} /> Delete source after merge</label>
  </div>

  <button class="run-btn" on:click={run} disabled={loading}>
    {loading ? 'Merging…' : 'Merge'}
  </button>

  {#if error}
    <p class="err">{error}</p>
  {/if}

  {#if result}
    <div class="summary">
      <span class="good">{result.volumes_created.length} volumes</span>
      <span class="dim">{result.total_pages} pages transferred</span>
    </div>
    <table class="table">
      <thead><tr><th>Volume</th><th>Output</th><th>Chapters</th></tr></thead>
      <tbody>
        {#each result.volumes_created as v}
          <tr>
            <td class="vol">{v.title}</td>
            <td class="out" title={v.output_path}>{v.output_path.split('/').pop() || v.output_path}</td>
            <td class="ch">{v.chapters.length}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</BaseDialog>

<style>
  .hint { margin: 0 0 12px; color: #666; font-size: 13px; }
  .hint code { background: #f0f0f0; padding: 1px 4px; border-radius: 3px; }
  .dir { color: #888; font-size: 12px; margin-bottom: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .modes { display: flex; flex-direction: column; gap: 6px; font-size: 13px; margin-bottom: 10px; }
  .field { display: flex; flex-direction: column; gap: 4px; font-size: 13px; margin-bottom: 10px; }
  .field input { width: 100%; box-sizing: border-box; }
  .opts { display: flex; flex-direction: column; gap: 6px; font-size: 13px; margin-bottom: 12px; }
  .run-btn { padding: 6px 14px; border: 1px solid #2b6cb0; background: #2b6cb0; color: #fff; border-radius: 4px; cursor: pointer; }
  .run-btn:disabled { opacity: 0.7; }
  .summary { margin: 12px 0; font-size: 13px; display: flex; gap: 14px; }
  .good { color: #38a169; }
  .dim { color: #999; }
  .table { width: 100%; border-collapse: collapse; font-size: 12px; }
  .table th, .table td { text-align: left; padding: 4px 8px; border-bottom: 1px solid #eee; }
  .vol { font-weight: 600; }
  .out { max-width: 200px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: #38a169; }
  .ch { text-align: right; }
  .err { color: #c53030; font-size: 13px; margin: 10px 0; }
</style>
