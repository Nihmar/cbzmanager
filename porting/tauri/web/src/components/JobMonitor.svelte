<script lang="ts">
  import { onMount } from 'svelte';
  import { job } from '../stores/progress';
  import { onProgress } from '../lib/api';

  let expanded = true;
  let elapsed = 0;
  let timer: ReturnType<typeof setInterval> | undefined = undefined;

  $: active = $job.active;

  function update(event: { percent: number; message: string; phase: string }) {
    job.update((s) => ({
      ...s,
      active: true,
      percent: event.percent,
      message: event.message,
      phase: event.phase,
      log: [...s.log, `[${event.phase}] ${event.message} (${event.percent}%).`],
    }));
    expanded = true;
  }

  onMount(() => onProgress(update));

  $: if (active) {
    if (!timer) timer = setInterval(() => (elapsed += 1), 1000);
  } else if (timer) {
    clearInterval(timer);
    timer = undefined;
  }

  // Reset the elapsed counter whenever a fresh job starts.
  $: if (active && $job.percent === 0) elapsed = 0;

  function clearLog() {
    job.update((s) => ({ ...s, log: [] }));
  }

  function formatTime(secs: number): string {
    const m = Math.floor(secs / 60);
    const s = secs % 60;
    return `${m}:${String(s).padStart(2, '0')}`;
  }
</script>

{#if active || $job.log.length > 0}
  <div class="monitor" class:expanded>
    <div class="head" on:click={() => (expanded = !expanded)}>
      <span class="status">{active ? '●' : '‸'}</span>
      <span class="label">Job Monitor</span>
      <span class="spacer"></span>
      {#if active}
        <span class="elapsed">{formatTime(elapsed)}</span>
      {/if}
      <button class="icon-btn" on:click|stopPropagation={clearLog}>✕</button>
    </div>

    {#if active}
      <div class="bar-track">
        <div class="bar-fill" style="width: {$job.percent}%"></div>
      </div>
      <div class="msg">{$job.message || 'Working…'}</div>
    {:else if $job.log.length > 0}
      <div class="msg done">Job complete.</div>
    {/if}

    {#if expanded && $job.log.length > 0}
      <pre class="log">{$job.log.join('\n')}</pre>
    {/if}
  </div>
{/if}

<style>
  .monitor {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    background: #1f2937;
    color: #e5e7eb;
    font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
    font-size: 12px;
    box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.25);
    z-index: 900;
    overflow: hidden;
  }

  .monitor.expanded {
    max-height: 180px;
    display: flex;
    flex-direction: column;
  }

  .head {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 6px 12px;
    background: #111827;
    cursor: pointer;
    user-select: none;
  }

  .status {
    color: #34d399;
  }

  .label {
    font-weight: 600;
  }

  .spacer {
    flex: 1;
  }

  .elapsed {
    color: #9ca3af;
  }

  .icon-btn {
    border: none;
    background: transparent;
    color: #9ca3af;
    cursor: pointer;
    font-size: 12px;
  }

  .bar-track {
    height: 4px;
    background: #374151;
  }

  .bar-fill {
    height: 100%;
    background: #3b82f6;
    transition: width 0.2s linear;
  }

  .msg {
    padding: 4px 12px;
    color: #d1d5db;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .msg.done {
    color: #34d399;
  }

  .log {
    margin: 0;
    padding: 6px 12px;
    max-height: 110px;
    overflow-y: auto;
    line-height: 1.4;
    color: #9ca3af;
    white-space: pre-wrap;
  }
</style>
