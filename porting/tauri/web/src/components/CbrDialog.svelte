<script lang="ts">
  import BaseDialog from './BaseDialog.svelte';
  import { cbrToCbz } from '../lib/api';
  import type { CbrConversionResult } from '../lib/types';

  export let open: boolean = false;
  export let dirPath: string = '';
  export let deleteSource = false;
  export let threads = 0;

  let results: CbrConversionResult[] = [];
  let loading = false;
  let error = '';

  $: if (open) {
    results = [];
    loading = true;
    error = '';
  }

  async function run() {
    loading = true;
    error = '';
    try {
      results = await cbrToCbz(dirPath, deleteSource, threads > 0 ? threads : undefined);
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
  title="Convert CBR to CBZ"
  {open}
  cancelLabel=""
  onConfirm={run}
  onCancel={close}
  width="520px"
>
  <p class="hint">Convert RAR archives to CBZ in RAM. Source files are kept as a backup (<code>_OLD.cbz</code>) unless "Delete source" is set.</p>

  <div class="opts">
    <label><input type="checkbox" bind:checked={deleteSource} /> Delete source after conversion</label>
    <label>Threads
      <input type="number" min="0" max="4" bind:value={threads} />
    </label>
  </div>
  <div class="dir">{dirPath || '(no directory selected)'}</div>

  <button class="run-btn" on:click={run} disabled={loading}>
    {loading ? 'Converting…' : 'Convert'}
  </button>

  {#if error}
    <p class="err">{error}<br /><span class="dim">libarchive may not be installed.</span></p>
  {/if}

  {#if results.length > 0}
    <div class="summary">
      <span class="good">{results.filter((r) => r.ok).length} converted</span>
      <span class="bad">{results.filter((r) => !r.ok).length} failed</span>
    </div>
    <table class="table">
      <thead><tr><th>Source</th><th>Output</th><th>Status</th></tr></thead>
      <tbody>
        {#each results as r}
          <tr>
            <td class="file">{r.input}</td>
            <td class="out">{r.output || '—'}</td>
            <td class={r.ok ? 'good' : 'bad'}>{r.ok ? 'OK' : (r.error || 'Failed')}</td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}
</BaseDialog>

<style>
  .hint { margin: 0 0 12px; color: #666; font-size: 13px; }
  .hint code { background: #f0f0f0; padding: 1px 4px; border-radius: 3px; }
  .opts { display: flex; flex-direction: column; gap: 8px; margin-bottom: 12px; font-size: 13px; }
  .dir { color: #888; font-size: 12px; margin-bottom: 12px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .run-btn { padding: 6px 14px; border: 1px solid #2b6cb0; background: #2b6cb0; color: #fff; border-radius: 4px; cursor: pointer; }
  .run-btn:disabled { opacity: 0.7; }
  .summary { margin: 12px 0; font-size: 13px; display: flex; gap: 14px; }
  .good { color: #38a169; }
  .bad { color: #c53030; }
  .dim { color: #999; }
  .table { width: 100%; border-collapse: collapse; font-size: 12px; }
  .table th, .table td { text-align: left; padding: 4px 8px; border-bottom: 1px solid #eee; }
  .file { max-width: 220px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .err { color: #c53030; font-size: 13px; margin: 10px 0; line-height: 1.5; }
</style>
