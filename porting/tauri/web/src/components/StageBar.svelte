<script lang="ts">
  import { hasChanges } from '../stores/pages';

  $: changes = $hasChanges;

  export let onSave: () => void = () => {};
  export let onRevert: () => void = () => {};
</script>

{#if changes}
  <div class="stagebar">
    <span class="dot">●</span>
    <span>Unsaved page changes</span>
    <span class="spacer"></span>
    <button class="btn" on:click={onRevert}>Revert</button>
    <button class="btn btn-primary" on:click={onSave}>Save changes</button>
  </div>
{/if}

<style>
  .stagebar {
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 6px 14px;
    background: #fff7e6;
    border-top: 1px solid #f0c36d;
    font-size: 13px;
    color: #7a5b00;
  }

  .dot {
    color: #f59e0b;
  }

  .spacer {
    flex: 1;
  }

  .btn {
    border: 1px solid #ccc;
    border-radius: 4px;
    background: #fafafa;
    padding: 4px 12px;
    cursor: pointer;
    font-size: 12px;
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
