<script lang="ts">
  import BaseDialog from './BaseDialog.svelte';
  import { validateDeep } from '../lib/api';
  import type { FileValidationResult, ImageCheck } from '../lib/types';

  export let open: boolean = false;
  export let dirPath: string = '';
  export let threads = 0;

  let results: FileValidationResult[] = [];
  let loading = false;
  let error = '';
  const expanded = new Set<number>();

  $: if (open) {
    results = [];
    loading = true;
    error = '';
    expanded.clear();
  }

  async function run() {
    loading = true;
    error = '';
    try {
      results = await validateDeep(dirPath, threads > 0 ? threads : undefined);
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }

  function toggle(idx: number) {
    if (expanded.has(idx)) expanded.delete(idx);
    else expanded.add(idx);
  }

  function close() {
    open = false;
  }
</script>

<BaseDialog
  title="Validate"
  {open}
  cancelLabel=""
  onConfirm={run}
  onCancel={close}
  width="640px"
>
  <p class="hint">Validate CBZ archives: open each file and confirm all images (including .webp) decode.</p>

  <div class="opts">
    <label>Threads
      <input type="number" min="0" max="8" bind:value={threads} />
    </label>
    <span class="dir">{dirPath || '(no directory selected)'}</span>
  </div>

  <button class="run-btn" on:click={run} disabled={loading}>
    {loading ? 'Validating…' : 'Validate'}
  </button>

  {#if error}
    <p class="err">{error}</p>
  {/if}

  {#if results.length > 0}
    <div class="summary">
      {results.filter((r) => r.valid).length} / {results.length} files valid ·
      {results.reduce((n, r) => n + r.image_count, 0)} images
    </div>

    <table class="table">
      <thead>
        <tr><th></th><th>File</th><th>Images</th><th>Status</th></tr>
      </thead>
      <tbody>
        {#each results as r, i}
          <tr>
            <td><button class="toggle" on:click={() => toggle(i)}>{expanded.has(i) ? '▾' : '▸'}</button></td>
            <td class="file">{r.file_name}</td>
            <td class="num">{r.image_count}</td>
            <td>
              {#if r.error_msg}
                <span class="bad">Archive error</span>
              {:else if r.valid}
                <span class="good">OK</span>
              {:else}
                <span class="bad">Invalid</span>
              {/if}
            </td>
          </tr>
          {#if expanded.has(i)}
            <tr>
              <td colspan={4} class="detail">
                {#if r.error_msg}
                  <div class="errmsg">{r.error_msg}</div>
                {:else if r.image_checks.length > 0}
                  {#each r.image_checks as c}
                    <div class="imgcheck" class:bad={!c.ok}>
                      <span>{c.filename}</span>
                      <span class={c.ok ? 'good' : 'bad'}>{c.ok ? 'OK' : 'FAIL'}</span>
                      {#if !c.ok && c.errors.length}
                        <div class="errors">{c.errors.join(' — ')}</div>
                      {/if}
                    </div>
                  {/each}
                {:else}
                  <div class="okmsg">No images to check.</div>
                {/if}
              </td>
            </tr>
          {/if}
        {/each}
      </tbody>
    </table>
  {/if}
</BaseDialog>

<style>
  .hint {
    margin: 0 0 12px;
    color: #666;
    font-size: 13px;
  }

  .opts {
    display: flex;
    align-items: center;
    gap: 16px;
    margin-bottom: 12px;
  }

  .opts label {
    display: flex;
    gap: 6px;
    font-size: 13px;
  }

  .opts input {
    width: 60px;
  }

  .dir {
    color: #888;
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .run-btn {
    padding: 6px 14px;
    border: 1px solid #2b6cb0;
    background: #2b6cb0;
    color: #fff;
    border-radius: 4px;
    cursor: pointer;
  }

  .run-btn:disabled { opacity: 0.7; }

  .summary {
    margin: 12px 0;
    font-size: 13px;
    color: #333;
  }

  .table {
    width: 100%;
    border-collapse: collapse;
    font-size: 13px;
  }

  .table th, .table td {
    border-bottom: 1px solid #eee;
    text-align: left;
    padding: 5px 8px;
  }

  .table th { color: #666; font-weight: 600; }
  .num { text-align: right; font-variant-numeric: tabular-nums; }
  .file { max-width: 320px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .toggle { border: none; background: transparent; cursor: pointer; padding: 0 4px; }

  .detail { padding: 8px; background: #fafafa; }
  .imgcheck { display: flex; gap: 10px; align-items: center; padding: 2px 0; }
  .errors, .errmsg { color: #c53030; font-size: 12px; }
  .okmsg { color: #38a169; }
  .good { color: #38a169; }
  .bad { color: #c53030; }
</style>
