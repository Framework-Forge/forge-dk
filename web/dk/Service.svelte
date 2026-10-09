<script>
  import { onDestroy } from 'svelte';
  import Document from './Document.svelte';
  import { previewDocument, formatDateInput } from './model.mjs';
  import { nui, t, errorText } from './api.mjs';
  export let data;
  export let notify = () => {};
  let selected = data.services[0]?.definition.key || '', inputs = {}, subject = '', image = '', busy = false;
  let quote = null, quoteGeneration = 0, debounce;
  onDestroy(() => { clearTimeout(debounce); quoteGeneration++; });
  $: entry = data.services.find(service => service.definition.key === selected);
  $: definition = entry?.definition;
  $: basePreview = definition ? previewDocument(definition, data.general, data.identity, data.mode === 'forgery') : null;
  $: preview = basePreview ? { ...basePreview, identity: { ...basePreview.identity, ...(data.mode === 'forgery' ? inputs : {}) },
    photo: image, fields: (basePreview.fields || []).map(field => ({ ...field, value: inputs[field.key] ?? field.value })) } : null;
  $: if (selected) scheduleQuote(selected, subject);
  function scheduleQuote(key, subjectKey) {
    clearTimeout(debounce);
    quote = null;
    const generation = ++quoteGeneration;
    debounce = setTimeout(async () => {
      const result = await nui('quote', { nonce: data.nonce, typeKey: key, subjectKey });
      if (generation !== quoteGeneration) return;
      if (result.ok) quote = result.data;
      else if (entry?.allowed && (definition.subject === 'person' || subjectKey)) notify(errorText(result.error), true);
    }, 500);
  }
  function choose(key) { selected = key; inputs = {}; subject = ''; image = ''; }
  function dateInput(event, key) {
    inputs[key] = formatDateInput(event.currentTarget.value);
    event.currentTarget.value = inputs[key]; inputs = { ...inputs };
  }
  async function photo() {
    busy = true;
    const result = await nui('photo', { nonce: data.nonce });
    busy = false;
    if (result.ok) { image = result.data; notify(t('ui.photoReady')); } else notify(errorText(result.error), true);
  }
  async function issue(account) {
    if (!quote) return;
    busy = true;
    const result = await nui('issue', { nonce: data.nonce, typeKey: selected, fields: inputs, subjectKey: subject,
      expectedFee: quote.fee, account });
    busy = false;
    if (result.ok) { notify(t('ui.issued')); scheduleQuote(selected, subject); }
    else { notify(errorText(result.error), true); if (result.error === 'quote_changed') scheduleQuote(selected, subject); }
  }
</script>

<div class="service-layout">
  <aside class="service-menu"><span class="eyebrow">{t('ui.choose')}</span>
    {#each data.services as service}<button class:active={selected === service.definition.key} on:click={() => choose(service.definition.key)}>
      <span class="service-icon">{service.definition.format === 'a4' ? '▤' : '▱'}</span>
      <span><strong>{service.definition.label}</strong><small>{service.allowed ? t('ui.authorized') : t('ui.locked')}</small></span>
    </button>{:else}<p>{t('ui.noServices')}</p>{/each}
  </aside>
  {#if definition}<div class="service-form">
    <div class="section-title"><h2>{definition.label}</h2><span class:warning={!entry.allowed} class="badge">{data.mode === 'forgery' ? t('ui.forgery') : entry.allowed ? t('ui.authorized') : t('ui.locked')}</span></div>
    {#if !entry.allowed}<p class="warning-text">{t('error.authorization_required')}</p>{/if}
    {#if definition.subject !== 'person'}<label>{t('ui.subjectKey')}<input bind:value={subject} /></label>{/if}
    {#if data.mode === 'forgery'}<div class="field-grid">
      {#each Object.keys(definition.forgeableIdentity || {}) as key}
        {#if definition.forgeableIdentity[key]}<label>{data.general.labels[key]}
          {#if key === 'dob'}<input placeholder={formatDateInput(data.identity[key]) || 'DD/MM/YYYY'} value={inputs[key] || ''} inputmode="numeric" maxlength="10" on:input={event => dateInput(event, key)} />
          {:else}<input placeholder={data.identity[key]} bind:value={inputs[key]} />{/if}
        </label>{/if}
      {/each}
    </div>{/if}
    <div class="field-grid">
      {#each definition.fields as field}
        {#if (data.mode === 'forgery' && field.forgeable) || (data.mode !== 'forgery' && field.source === 'input')}
          <label class:wide={field.type === 'textarea'}>{field.label}{field.required ? ' *' : ''}
            {#if field.type === 'textarea'}<textarea rows="3" bind:value={inputs[field.key]} placeholder={field.default}></textarea>
            {:else if field.type === 'date'}<input value={inputs[field.key] || ''} inputmode="numeric" maxlength="10" placeholder={formatDateInput(field.default) || 'DD/MM/YYYY'} on:input={event => dateInput(event, field.key)} />
            {:else}<input type={field.type === 'number' ? 'number' : 'text'} bind:value={inputs[field.key]} placeholder={field.default} />{/if}
          </label>
        {/if}
      {/each}
    </div>
    <div class="photo-control"><div class="portrait-mini">{#if image}<img src={image} alt={t('ui.photo')} />{:else}<span>◯</span>{/if}</div>
      <div><button disabled={busy || !entry.allowed} on:click={photo}>{t('ui.photo')}</button><small>{image ? t('ui.photoReady') : quote?.photoAvailable ? t('ui.photoReuse') : t('ui.requirePhoto')}</small></div>
    </div>
    <div class="fee-summary"><span>{t('ui.actualFee')}</span><strong>{quote ? '$ ' + quote.fee.toLocaleString(data.general.locale) : '—'}</strong>
      {#if quote}<small>{t('ui.copy')} {quote.copyNumber}</small>{/if}
    </div>
    <div class="button-row">
      <button class="primary" disabled={busy || !entry.allowed || !quote || definition.requirePhoto && !image && !quote.photoAvailable} on:click={() => issue('cash')}>{t('ui.issueCash')}</button>
      <button disabled={busy || !entry.allowed || !quote || definition.requirePhoto && !image && !quote.photoAvailable} on:click={() => issue('bank')}>{t('ui.issueBank')}</button>
    </div>
  </div><aside class="preview-pane"><Document document={preview} locale={data.general.locale} /></aside>{/if}
</div>
