<script lang="ts">
  export let title: string = '';
  export let open: boolean = false;
  export let confirmLabel: string = 'OK';
  export let cancelLabel: string = 'Cancel';
  export let cancelVisible: boolean = true;
  export let width: string = '640px';

  // Confirm actions are exposed as callbacks so the parent can gate them on its own state.
  export let onConfirm: (() => void) | undefined = undefined;
  export let onCancel: () => void = () => {};

  function close() {
    if (onCancel) onCancel();
  }

  async function confirm() {
    if (onConfirm) {
      await onConfirm();
    }
  }

  function onKeydown(event: KeyboardEvent) {
    if (!open) return;
    if (event.key === 'Escape') close();
  }
</script>

<svelte:window on:keydown={onKeydown} />

{#if open}
  <div class="backdrop" on:click={close}>
      <div class="dialog" style="width: {width};" role="dialog" aria-modal="true" aria-label={title} on:click|stopPropagation>
      <header class="titlebar">
        <span>{title}</span>
        <button class="icon-btn" aria-label="Close" on:click={close}>×</button>
      </header>

      <div class="body"><slot /></div>

      {#if confirmLabel || cancelVisible}
        <footer class="actions">
          {#if cancelVisible}
            <button class="btn" on:click={close}>{cancelLabel}</button>
          {/if}
          {#if confirmLabel}
            <button class="btn btn-primary" on:click={confirm}>{confirmLabel}</button>
          {/if}
        </footer>
      {/if}
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
    z-index: 1000;
  }

  .dialog {
    width: var(--dlg-width, 640px);
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
    padding: 14px 16px;
    overflow-y: auto;
    flex: 1;
  }

  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    padding: 10px 16px;
    border-top: 1px solid #eee;
  }

  .btn {
    padding: 6px 14px;
    border: 1px solid #ccc;
    border-radius: 4px;
    background: #fafafa;
    cursor: pointer;
    font-size: 13px;
  }

  .btn:hover {
    background: #eee;
  }

  .btn-primary {
    background: #2b6cb0;
    border-color: #2b6cb0;
    color: #fff;
  }

  .btn-primary:hover {
    background: #24558c;
  }
</style>
