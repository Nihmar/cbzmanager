<script lang="ts">
  import BaseDialog from './BaseDialog.svelte';
  import { convertWebp } from '../lib/api';
  import type { ConvertWebpResult } from '../lib/types';

  export let open: boolean = false;
  export let dirPath: string = '';
  export let deleteSource = false;
  export let threads = 0;

  let result: ConvertWebpResult | null = null;
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
      result = await convertWebp(dirPath, deleteSource, threads > 0 ? threads : undefined);
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
  title="Convert to WebP"
  {open}
  cancelLabel=""
  onConfirm={run}
  onCancel={close}
  width="480px"
>
  <p class="hint">Re-convert images to WebP (quality 75) only when smaller. ComicInfo.xml is stripped and pages are renumbered. Existing archives are backed up as <code>_OLD.cbz</code> unless "Delete source" is set.</p>

  <div class="opts">
    <label><input type="checkbox" bind:checked={deleteSource} /> Delete source after conversion</label>
    <label>Threads
      <input type="number" min="0" max="8" bind:value={threads} />
    </label>
  </div>
  <div class="dir">{dirPath || '(no directory selected)'}</div>

  <button class="run-btn" on:click={run} disabled={loading}>
    {loading ? 'Converting…' : 'Convert'}
  </button>

  {#if error}
    <p class="err">{error}</p>
  {/if}

  {#if result}
    <div class="summary">
      <span class="good">{result.converted.length} converted</span>
      <span class="dim">{result.skipped.length} skipped (already WebP or smaller)</span>
    </div>
    {#if result.converted.length}
      <ul class="list">
        {#each result.converted as name}
          <li>{name}</li>
        {/each}
      </ul>
    {/if}
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
  .dim { color: #999; }
  .list { list-style: none; margin: 0; padding: 0; max-height: 200px; overflow-y: auto; font-size: 12px; }
  .list li { padding: 2px 0; color: #38a169; }
  .err { color: #c53030; font-size: 13px; margin: 10px 0; }
</style>
