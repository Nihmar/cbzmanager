<script lang="ts">
  import './app.css';
  import type { DirEntry, PageState } from './lib/types';
  import { listDirectory, firstImage, pageLoad, pageSave } from './lib/api';
  import { files, selectedFile, currentDirectory } from './stores/files';
  import { pages as pagesStore, hasChanges } from './stores/pages';
  import { thumbnailSize } from './stores/thumbnail';

  import FileBrowser from './components/FileBrowser.svelte';
  import PagePreview from './components/PagePreview.svelte';
  import StageBar from './components/StageBar.svelte';
  import JobMonitor from './components/JobMonitor.svelte';
  import ValidateDialog from './components/ValidateDialog.svelte';
  import ConvertDialog from './components/ConvertDialog.svelte';
  import BatchEdit from './components/BatchEdit.svelte';
  import CbrDialog from './components/CbrDialog.svelte';
  import MergeDialog from './components/MergeDialog.svelte';
  import ComicInfoDialog from './components/ComicInfoDialog.svelte';
  import PageViewer from './components/PageViewer.svelte';

  let dirText = '';
  let listing = false;
  let loadingPages = false;

  // Subdirectory navigation (GAPS 3.11): ordered breadcrumb trail of full paths,
  // plus an in-memory cache so jumping back restores the cached listing instantly.
  let history: string[] = [];
  const dirCache = new Map<string, DirEntry[]>();

  function basename(path: string): string {
    if (!path) return '';
    const clean = path.endsWith('/') ? path.slice(0, -1) : path;
    const parts = clean.split('/').filter((p) => p.length > 0);
    return parts.length ? parts[parts.length - 1] : clean;
  }

  function listInto(path: string) {
    const cached = dirCache.get(path);
    if (cached) { files.set(cached); return; }
    files.set([]);
    listing = true;
    listDirectory(path)
      .then((entries) => {
        dirCache.set(path, entries);
        files.set(entries);
      })
      .catch(() => {})
      .finally(() => (listing = false));
  }

  function openDirectory() {
    const dir = $currentDirectory.trim() || dirText.trim();
    if (!dir) return;
    currentDirectory.set(dir);
    history = [dir];
    dirCache.clear();
    listInto(dir);
  }

  function enterSubdir(entry: DirEntry) {
    const child = `${$currentDirectory}/${entry.name}`;
    history = [...history, child];
    currentDirectory.set(child);
    dirCache.delete(child);
    listInto(child);
  }

  function jumpToLevel(i: number) {
    history = history.slice(0, i + 1);
    const target = history[i];
    if (!target) return;
    currentDirectory.set(target);
    dirCache.delete(target);
    listInto(target);
  }
  let viewerOpen = false;
  let viewerIndex = 0;

  let showValidate = false;
  let showConvert = false;
  let showCbr = false;
  let showMerge = false;
  let showComicinfo = false;
  let showBatch = false;

  // Track the page the user is hovering/clicking so Space can open it.
  let highlighted = 0;

  async function selectFile(entry: DirEntry) {
    selectedFile.set(entry.name);
    loadingPages = true;
    pagesStore.set([]);
    hasChanges.set(false);
    highlighted = 0;
    try {
      const dir = $currentDirectory;
      const filePath = `${dir}/${entry.name}`;
      const pageStates = await pageLoad(filePath);
      if (entry.thumbnail && pageStates.length > 0) {
        pageStates[0] = { ...pageStates[0], data: entry.thumbnail };
      }
      pagesStore.set(pageStates);
    } catch (err) {
      console.error(err);
    } finally {
      loadingPages = false;
    }
  }

  function currentFilePath(): string {
    const dir = $currentDirectory;
    const name = $selectedFile;
    return name ? `${dir}/${name}` : '';
  }

  function openViewerAt(index: number) {
    viewerIndex = index;
    viewerOpen = true;
  }

  function onBatchApply(pages: PageState[]) {
    pagesStore.set(pages);
    hasChanges.set(true);
  }

  async function saveChanges() {
    const filePath = currentFilePath();
    if (!filePath) return;
    try {
      await pageSave($pagesStore, filePath);
      hasChanges.set(false);
    } catch (err) {
      console.error(err);
    }
  }

  function revertChanges() {
    // Reload from disk to discard unsaved edits.
    const entry = { name: $selectedFile, is_dir: false, ext: '' } as DirEntry;
    if (entry.name) selectFile(entry);
  }

  function onKeydown(event: KeyboardEvent) {
    // Keyboard parity with the Lazarus main form (main.pas FormKeyDown):
    // F4 preview toggle (no preview pane here — deferred), F5 reload,
    // F8 validate, Ctrl+S save staged changes, Del mark page gone,
    // Ctrl+A select all (no multi-select model yet — deferred).
    if (event.key === 'F5') {
      event.preventDefault();
      revertChanges();
    } else if (event.key === 'F8' && $currentDirectory) {
      event.preventDefault();
      showValidate = true;
    } else if ((event.ctrlKey || event.metaKey) && event.key === 's' && $hasChanges) {
      event.preventDefault();
      saveChanges();
    } else if (event.key === 'Delete' && $pagesStore.length > 0) {
      event.preventDefault();
      const pages = $pagesStore.map((p, i) => (i === highlighted ? { ...p, gone: true } : p));
      pagesStore.set(pages);
      hasChanges.set(true);
    } else if (event.key === ' ' && $selectedFile && !viewerOpen) {
      event.preventDefault();
      openViewerAt(highlighted);
    }
  }
</script>

<svelte:window on:keydown={onKeydown} />

<div class="app">
  <header class="toolbar">
    <h1>CBZ Manager</h1>
    <input
      type="text"
      class="dir-input"
      bind:value={dirText}
      placeholder="Directory path (e.g. /home/user/comics)"
      on:keydown={(e) => e.key === 'Enter' && openDirectory()}
    />
    <button class="btn" on:click={openDirectory}>Open directory</button>

    <span class="spacer"></span>

    <button class="btn" on:click={() => (showValidate = true)}>Validate</button>
    <button class="btn" on:click={() => (showConvert = true)}>Convert to WebP</button>
    <button class="btn" on:click={() => (showCbr = true)}>CBR → CBZ</button>
    <button class="btn" on:click={() => (showMerge = true)}>Merge</button>
    <button class="btn" on:click={() => (showComicinfo = true)}>ComicInfo</button>

    <span class="zoom-group">
      <label for="zoom">Zoom</label>
      <input
        id="zoom"
        type="range"
        min="48"
        max="320"
        step="16"
        value={$thumbnailSize}
        on:input={(e) => thumbnailSize.set(Number(e.currentTarget.value))}
      />
      <span class="zoom-val">{Math.round($thumbnailSize)}px</span>
    </span>
  </header>

  <main class="content">
    <div class="file-browser-pane">
      {#if history.length}
        <nav class="breadcrumb" aria-label="Navigation path">
          {#each history as level, i (level)}
            <button
              type="button"
              class="crumb{i === history.length - 1 ? ' current' : ''}"
              on:click={() => jumpToLevel(i)}
            >{basename(level)}</button>{#if i !== history.length - 1}<span class="sep">/</span>{/if}
          {/each}
        </nav>
      {/if}
      <FileBrowser
        entries={$files}
        selectedFile={$selectedFile}
        loading={listing}
        onSelect={selectFile}
        onOpenSubdir={enterSubdir}
      />
    </div>

    <div class="preview-pane">
      <PagePreview
        pages={$pagesStore}
        fileName={$selectedFile}
        filePath={currentFilePath()}
        loading={loadingPages}
        onOpenViewer={openViewerAt}
        onHighlight={(i) => (highlighted = i)}
      />
      <div class="edit-bar">
        <button class="btn" on:click={() => (showBatch = true)} disabled={!$selectedFile}>Apply batch edit…</button>
      </div>
      <StageBar onSave={saveChanges} onRevert={revertChanges} />
    </div>
  </main>

  <ValidateDialog open={showValidate} dirPath={$currentDirectory} />
  <ConvertDialog open={showConvert} dirPath={$currentDirectory} />
  <CbrDialog open={showCbr} dirPath={$currentDirectory} />
  <MergeDialog open={showMerge} dirPath={$currentDirectory} />
  <ComicInfoDialog open={showComicinfo} dirPath={$currentDirectory} />

  <BatchEdit open={showBatch} filePath={currentFilePath()} onApply={onBatchApply} onClose={() => (showBatch = false)} />

  <PageViewer
    open={viewerOpen}
    filePath={currentFilePath()}
    pageNames={$pagesStore.filter((p) => !p.gone).map((p) => p.name)}
    startIndex={viewerIndex}
  />
</div>

<JobMonitor />

<style>
  .app {
    display: flex;
    flex-direction: column;
    height: 100vh;
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
  }

  .toolbar {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    background: #f5f5f5;
    border-bottom: 1px solid #ddd;
  }

  .toolbar h1 { margin: 0; font-size: 16px; }

  .dir-input { width: 360px; padding: 5px 8px; border: 1px solid #ccc; border-radius: 4px; font-size: 13px; }

  .spacer { flex: 1; }

  .zoom-group {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 12px;
    color: #555;
  }

  .zoom-group input[type="range"] { width: 130px; }

  .zoom-val {
    min-width: 34px;
    text-align: right;
    font-variant-numeric: tabular-nums;
    color: #888;
  }

  .content { display: flex; flex: 1; overflow: hidden; }

  .file-browser-pane {
    width: 280px;
    min-width: 200px;
    border-right: 1px solid #ddd;
    overflow: hidden;
    background: #fafafa;
  }

  .file-browser-pane {
    width: 280px;
    min-width: 200px;
    border-right: 1px solid #ddd;
    overflow: hidden;
    background: #fafafa;
    display: flex;
    flex-direction: column;
  }

  .breadcrumb {
    display: flex;
    align-items: center;
    flex-wrap: wrap;
    gap: 2px;
    padding: 6px 8px;
    font-size: 12px;
    border-bottom: 1px solid #eee;
    background: #f0f0f0;
    min-height: 26px;
  }

  .crumb {
    border: none;
    background: transparent;
    color: #2b6cb0;
    cursor: pointer;
    padding: 1px 4px;
    border-radius: 3px;
    font-size: 12px;
  }

  .crumb:hover { background: #e2e8f0; }

  .crumb.current {
    color: #444;
    cursor: default;
    font-weight: 600;
    background: transparent;
  }

  .sep { color: #bbb; user-select: none; }

  .preview-pane {
    flex: 1;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .edit-bar {
    display: flex;
    justify-content: flex-end;
    padding: 4px 8px 0;
  }

  .btn {
    padding: 5px 12px;
    border: 1px solid #ccc;
    border-radius: 4px;
    background: #fafafa;
    font-size: 13px;
    cursor: pointer;
  }

  .btn:hover { background: #eee; }
</style>
