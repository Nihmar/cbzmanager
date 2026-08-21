<script lang="ts">
  import BaseDialog from './BaseDialog.svelte';
  import { scanComicinfo, removeComicinfo, readEntry } from '../lib/api';
  import type { ComicInfoResult } from '../lib/types';

  export let open: boolean = false;
  export let dirPath: string = '';

  let results: ComicInfoResult[] = [];
  let loading = false;
  let error = '';
  let threads = 0;
  let backup = true;

  let viewingName = '';
  let viewingXml = '';
  let viewingError = '';

  $: if (open) {
    results = [];
    viewingName = '';
    viewingXml = '';
    viewingError = '';
    loading = true;
    error = '';
  }

  async function scan() {
    loading = true;
    error = '';
    try {
      results = await scanComicinfo(dirPath);
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }

  async function remove() {
    loading = true;
    error = '';
    try {
      results = await removeComicinfo(dirPath, backup, threads > 0 ? threads : undefined);
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }

  async function view(name: string) {
    viewingName = name;
    viewingXml = '';
    viewingError = '';
    try {
      const xmlPath = `${dirPath}/${name}`;
      const bytes = await readEntry(xmlPath, 'ComicInfo.xml');
      viewingXml = new TextDecoder('utf-8').decode(bytes);
    } catch (e) {
      viewingError = String(e);
    }
  }

  function close() {
    open = false;
  }
</script>

<BaseDialog
  title="ComicInfo.xml"
  {open}
  cancelLabel=""
  onConfirm={scan}
  onCancel={close}
  width="560px"
>
  <p class="hint">Scan a directory for ComicInfo.xml, view its contents, or strip it from every archive (optionally backing up each file first).</p>

  {#if dirPath}
    <div class="dir">{dirPath}</div>
  {/if}

  <div class="opts">
    <label><input type="checkbox" bind:checked={backup} /> Back up archives (as _OLD.cbz) before removing</label>
    <label>Threads
      <input type="number" min="0" max="4" bind:value={threads} />
    </label>
  </div>

  <div class="btns">
    <button class="run-btn" on:click={scan} disabled={loading}>Scan</button>
    <button class="run-btn" on:click={remove} disabled={loading || results.length === 0}>Remove all</button>
  </div>

  {#if error}
    <p class="err">{error}</p>
  {/if}

  {#if results.length > 0}
    <table class="table">
      <thead><tr><th>File</th><th>Status</th><th></th></tr></thead>
      <tbody>
        {#each results as r}
          <tr>
            <td class="file">{r.file_name}</td>
            <td class={r.found ? 'good' : 'dim'}>{r.found ? 'Present' : 'Absent'}</td>
            <td class="act">
              <button class="link" on:click={() => view(r.file_name)}>View</button>
            </td>
          </tr>
        {/each}
      </tbody>
    </table>
  {/if}

  {#if viewingName}
    <div class="view">
      <div class="view-head">ComicInfo.xml in {viewingName}</div>
      {#if viewingError}
        <p class="err">{viewingError}</p>
      {:else}
        <pre class="xml">{viewingXml}</pre>
      {/if}
    </div>
  {/if}
</BaseDialog>

<style>
  .hint { margin: 0 0 12px; color: #666; font-size: 13px; }
  .dir { color: #888; font-size: 12px; margin-bottom: 10px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .opts { display: flex; flex-direction: column; gap: 8px; font-size: 13px; margin-bottom: 12px; }
  .btns { display: flex; gap: 8px; }
  .run-btn { padding: 6px 14px; border: 1px solid #2b6cb0; background: #2b6cb0; color: #fff; border-radius: 4px; cursor: pointer; }
  .run-btn:disabled { opacity: 0.7; }
  .table { width: 100%; border-collapse: collapse; font-size: 13px; margin-top: 10px; }
  .table th, .table td { text-align: left; padding: 4px 8px; border-bottom: 1px solid #eee; }
  .file { max-width: 260px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .act { text-align: right; }
  .link { border: none; background: transparent; color: #2b6cb0; cursor: pointer; padding: 0; font-size: 12px; }
  .err { color: #c53030; font-size: 13px; margin: 10px 0; }
  .good { color: #38a169; }
  .dim { color: #999; }
  .view { margin-top: 16px; border-top: 1px solid #eee; padding-top: 10px; }
  .view-head { font-size: 12px; color: #666; margin-bottom: 6px; }
  .xml { margin: 0; padding: 8px; background: #fafafa; border: 1px solid #eee; border-radius: 4px; overflow-x: auto; font-size: 11px; white-space: pre-wrap; max-height: 240px; overflow-y: auto; }
</style>
