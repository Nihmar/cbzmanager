<script lang="ts">
  import './app.css';
  import type { DirEntry } from './lib/types';
  import { listDirectory, firstImage } from './lib/api';
  import { files, selectedFile, currentDirectory } from './stores/files';
  import { pages, hasChanges } from './stores/pages';
  import { onProgress } from './lib/api';

  let dirPath = '';
  let isLoaded = false;
  let logLines: string[] = [];

  function handleDrop(e: DragEvent) {
    e.preventDefault();
    const path = e.dataTransfer?.items[0]?.webkitGetAsEntry()?.path || '';
    if (path) loadDirectory(path);
  }

  function handleDirInput(e: Event) {
    const input = e.target as HTMLInputElement;
    if (input.files && input.files.length > 0) {
      // Use the first item's parent directory path
      loadDirectory(dirPath);
    }
  }

  async function loadDirectory(dir: string) {
    currentDirectory.set(dir);
    dirPath = dir;
    isLoaded = true;
    
    try {
      const entries = await listDirectory(dir);
      files.set(entries);
    } catch (err) {
      logLines = [...logLines, `Error loading directory: ${err}`];
    }
  }

  async function selectFile(entry: DirEntry) {
    selectedFile.set(entry.name);
    // Load pages when file is selected — in production this calls page_load
    pages.set([]);
    hasChanges.set(false);
  }

  onProgress((event) => {
    logLines = [...logLines, `[${event.phase}] ${event.message} (${event.percent}%)\n`];
  });
</script>

<div class="app">
  <header class="toolbar">
    <h1>CBZ Manager</h1>
    <input
      type="file"
      webkitdirectory
      class="dir-picker"
      oninput={handleDirInput}
    />
  </header>

  <main class="content" ondrop={handleDrop}>
    <!-- Left pane: File browser -->
    <div class="file-browser">
      {#if !isLoaded}
        <div class="empty-state">
          <p>Open a directory to browse CBZ files</p>
          <p class="hint">Drag &amp; drop or use the picker above</p>
        </div>
      {:else}
        <ul class="file-list">
          {#each $files as entry (entry.name)}
            <li
              class:selected={$selectedFile === entry.name}
              on:click={() => selectFile(entry)}
              title={entry.name}
            >
              {#if entry.thumbnail}
                <img src={entry.thumbnail} alt="" class="thumb" loading="lazy" />
              {/if}
              <span>{entry.name}</span>
            </li>
          {/each}
        </ul>
      {/if}
    </div>

    <!-- Right pane: Page preview -->
    <div class="page-preview">
      {#if selectedFile}
        <h2>{$selectedFile}</h2>
        {#if $pages.length > 0}
          <div class="page-grid">
            {#each $pages as page, i (i)}
              <div class="page-card" on:dblclick={() => {/* open page viewer */}}>
                <span class="page-name">{page.name}</span>
              </div>
            {/each}
          </div>
        {:else}
          <p class="empty-state">No pages loaded for this file</p>
        {/if}
      {:else}
        <div class="empty-state">
          <p>Select a CBZ file to preview its pages</p>
        </div>
      {/if}
    </div>
  </main>

  <!-- Job monitor -->
  {#if logLines.length > 0}
    <div class="job-monitor">
      <h3>Job Log</h3>
      <pre>{logLines.join('')}</pre>
    </div>
  {/if}
</div>

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
    gap: 12px;
    padding: 8px 16px;
    background: #f5f5f5;
    border-bottom: 1px solid #ddd;
  }

  .toolbar h1 {
    margin: 0;
    font-size: 16px;
  }

  .dir-picker {
    font-size: 12px;
  }

  .content {
    display: flex;
    flex: 1;
    overflow: hidden;
  }

  .file-browser {
    width: 300px;
    min-width: 200px;
    border-right: 1px solid #ddd;
    overflow-y: auto;
    background: #fafafa;
  }

  .file-list {
    list-style: none;
    margin: 0;
    padding: 0;
  }

  .file-list li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    cursor: pointer;
    font-size: 13px;
    border-bottom: 1px solid #eee;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .file-list li:hover {
    background: #e8f0fe;
  }

  .file-list li.selected {
    background: #d2e3fc;
    font-weight: 500;
  }

  .thumb {
    width: 32px;
    height: 40px;
    object-fit: cover;
    border-radius: 2px;
    flex-shrink: 0;
  }

  .page-preview {
    flex: 1;
    overflow-y: auto;
    padding: 16px;
  }

  .page-preview h2 {
    margin: 0 0 12px 0;
    font-size: 14px;
  }

  .page-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 8px;
  }

  .page-card {
    border: 1px solid #ddd;
    padding: 4px;
    cursor: pointer;
    text-align: center;
  }

  .page-name {
    font-size: 11px;
    word-break: break-all;
  }

  .empty-state {
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: #666;
    gap: 8px;
  }

  .hint {
    font-size: 12px;
    color: #999;
  }

  .job-monitor {
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    background: #f8f8f8;
    border-top: 1px solid #ddd;
    padding: 8px 16px;
    max-height: 200px;
    overflow-y: auto;
    font-size: 12px;
  }

  .job-monitor h3 {
    margin: 0 0 4px 0;
    font-size: 13px;
  }

  .job-monitor pre {
    margin: 0;
    white-space: pre-wrap;
    font-family: monospace;
  }
</style>
