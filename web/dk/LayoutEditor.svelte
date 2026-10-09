<script>
  import Document from './Document.svelte';
  import { layoutFor, sanitizeBox } from './layout.mjs';
  import { t } from './api.mjs';
  export let doc;
  export let preview;
  export let locale;
  export let onChange = () => {};
  let editing = false, selected = 'stamp';
  $: positions = layoutFor(preview);
  $: if (!positions[selected]) selected = 'stamp';
  $: position = positions[selected] || positions.stamp;
  function title(key) {
    if (key.startsWith('field:')) return doc.fields.find(field => field.key === key.slice(6))?.label || key;
    return preview.labels[key] || t('ui.element'+key[0].toUpperCase()+key.slice(1));
  }
  function set(key,value) {
    const format = doc.format === 'a4' ? 'a4' : 'card';
    doc.layout = { ...(doc.layout || {}), [format]: { ...(doc.layout?.[format] || {}), [key]:sanitizeBox(value,positions[key]) } };
    onChange(doc);
  }
  function update(key,value) { set(selected,{...position,[key]:value}); }
  function reset() {
    const format = doc.format === 'a4' ? 'a4' : 'card';
    doc.layout = { ...(doc.layout || {}), [format]: {} }; onChange(doc);
  }
</script>

<label class="check"><input type="checkbox" bind:checked={editing} />{t('ui.editLayout')}</label>
<Document document={preview} {locale} {editing} assetWarnings={true} selectedElement={selected}
  onSelect={key => selected = key} onMove={set} />
{#if editing}
  <div class="layout-controls">
    <p class="muted">{t('ui.layoutHint')}</p>
    <label>{t('ui.layoutElement')}<select aria-label={t('ui.layoutElement')} bind:value={selected}>
      {#each Object.keys(positions) as key}<option value={key}>{title(key)}</option>{/each}
    </select></label>
    <div class="field-grid">
      {#each [['x','positionX'],['y','positionY'],['width','elementWidth'],['fontSize','elementFont']] as [key,label]}
        <label>{t('ui.'+label)}<input aria-label={t('ui.'+label)} type="number" step="0.1"
          min={key === 'fontSize' ? .5 : key === 'width' ? 1 : 0} max={key === 'fontSize' ? 8 : key === 'width' ? 100-position.x : 98}
          value={position[key]} on:input={event => update(key,Number(event.currentTarget.value))} /></label>
      {/each}
    </div>
    <label>{t('ui.textAlign')}<select value={position.align} on:change={event => update('align',event.currentTarget.value)}>
      {#each ['left','center','right'] as key}<option value={key}>{t('ui.align'+key[0].toUpperCase()+key.slice(1))}</option>{/each}
    </select></label>
    <label class="check"><input type="checkbox" checked={position.hidden} on:change={event => update('hidden',event.currentTarget.checked)} />{t('ui.hideElement')}</label>
    <button on:click={reset}>{t('ui.resetLayout')}</button>
  </div>
{/if}
