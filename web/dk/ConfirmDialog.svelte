<script>
  import { onMount } from 'svelte';
  import Icon from './Icon.svelte';
  import { t } from './api.mjs';
  export let label;
  export let onConfirm = () => {};
  export let onCancel = () => {};
  let dialog, cancelButton;
  onMount(() => { dialog.showModal(); cancelButton.focus(); return () => dialog.close(); });
</script>
<dialog bind:this={dialog} class="confirm-dialog" aria-labelledby="delete-type-title" aria-describedby="delete-type-description"
  on:cancel={event => { event.preventDefault(); onCancel(); }}>
  <div class="confirm-heading"><span class="danger-symbol"><Icon name="trash" /></span><h2 id="delete-type-title">{t('ui.deleteTypeTitle')}</h2></div>
  <p class="confirm-label">{label}</p>
  <p id="delete-type-description">{t('ui.deleteTypeHint')}</p>
  <div class="button-row"><button bind:this={cancelButton} on:click={onCancel}>{t('ui.cancel')}</button><button class="danger solid" on:click={onConfirm}><Icon name="trash" />{t('ui.confirmDeleteType')}</button></div>
</dialog>
