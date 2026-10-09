<script>
  import { onMount } from 'svelte';
  import Document from './Document.svelte';
  import LayoutEditor from './LayoutEditor.svelte';
  import Icon from './Icon.svelte';
  import FormSection from './FormSection.svelte';
  import ConfirmDialog from './ConfirmDialog.svelte';
  import { previewDocument, newDocument, formatDateInput, removeDocumentType } from './model.mjs';
  import { nui, t, errorText } from './api.mjs';
  export let data;
  export let notify = () => {};
  export let collapsed = false;
  function editorConfig(value) {
    const result = structuredClone(value);
    for (const doc of Object.values(result.types)) {
      doc.appearance = {...newDocument(doc.key).appearance,...doc.appearance};
      doc.animationMs ??= 2500; doc.displayMs ??= 0;
      const a=doc.appearance;
      a.forged = {background:a.background,secondary:a.secondary,text:a.text,accent:a.accent,
        fontFamily:a.fontFamily,patternStyle:a.patternStyle,patternOpacity:a.patternOpacity,emblemImage:'',...a.forged};
      doc.layout ||= {card:{},a4:{}}; doc.presentationStyle ||= 'police';
    }
    return result;
  }
  let config = editorConfig(data.config);
  let page = 'general', selected = Object.keys(config.types)[0] || '', npcId = '', busy = false;
  let forgedPreview = false, deleting = '';
  let records = [], search = '', target = '', permissionType = selected, category = '', recordDetail = null, confirmSerial = '';
  const originalKeys = new Set(Object.keys(config.types));
  $: doc = config.types[selected];
  $: npc = config.npcs.find(entry => entry.id === npcId);
  $: preview = doc ? previewDocument(doc, config.general, {}, doc.allowForgery && forgedPreview) : null;
  async function save() {
    if (busy) return;
    busy = true;
    const result = await nui('save', config);
    busy = false;
    if (!result.ok) return notify(errorText(result.error), true);
    config = editorConfig(result.data);
    for (const key of Object.keys(config.types)) originalKeys.add(key);
    notify(t('ui.saved'));
  }
  function addType() {
    const key = 'document_' + Date.now().toString(36);
    config.types[key] = newDocument(key, data.catalogue.find(item => item.stack === false && !item.conflict)?.name || 'id_card');
    config = { ...config };
    selected = key;
  }
  function confirmDelete() {
    const key = deleting;
    deleting = '';
    config = removeDocumentType(config, key);
    selected = Object.keys(config.types)[0] || '';
    if (!config.types[permissionType]) permissionType = selected;
    forgedPreview = false;
    notify(t('ui.typeRemovedDraft'));
  }
  function renameType(event) {
    const key = event.currentTarget.value;
    if (!/^[\w-]{1,64}$/.test(key) || key === selected || config.types[key]) return;
    const value = config.types[selected];
    delete config.types[selected];
    value.key = key;
    if (value.permissionKey === selected) value.permissionKey = key;
    config.types[key] = value;
    config = { ...config };
    selected = key;
  }
  function setLabel(key, value) {
    doc.labels = { ...(doc.labels || {}) };
    if (value) doc.labels[key] = value; else delete doc.labels[key];
    doc = doc;
  }
  function addField() {
    doc.fields = [...doc.fields, { key: 'field_' + (doc.fields.length + 1), label: '', source: 'input',
      type: 'text', required: false, forgeable: false, default: '' }];
    doc = doc;
  }
  function addNpc() {
    const id = 'service_' + Date.now().toString(36);
    config.npcs = [...config.npcs, { id, label: t('ui.official'), model: 'a_m_m_business_01', mode: 'official',
      enabled: true, distance: 2, heading: 0, coords: null, services: [], interaction: 'interact', wallDetection: true }];
    npcId = id;
  }
  async function position() {
    const result = await nui('placeNpc', { model: npc.model, npcId: npc.id, heading: npc.heading });
    if (!result.ok) notify(errorText(result.error), true);
  }
  async function loadRecords() {
    const result = await nui('records', { identifier: search });
    if (result.ok) records = result.data; else notify(errorText(result.error), true);
  }
  async function permission(enabled) {
    const result = await nui('permission', { target: Number(target), typeKey: permissionType, enabled, category });
    notify(result.ok ? t(enabled ? 'ui.authorized' : 'ui.notAuthorized') : errorText(result.error), !result.ok);
  }
  async function revoke(serial) {
    if (confirmSerial !== serial) { confirmSerial = serial; return; }
    const result = await nui('revoke', { serial });
    confirmSerial = '';
    if (result.ok) await loadRecords(); else notify(errorText(result.error), true);
  }
  async function recordInfo(serial) {
    const result = await nui('record', { serial });
    if (result.ok) recordDetail = result.data; else notify(errorText(result.error), true);
  }
  function switchFormat() {
    if (doc.format === 'a4') doc.appearance = { ...doc.appearance, background: '#f7f2e8', secondary: '#eae1d0', text: '#253447' };
    doc = doc;
  }
  async function uploadSeal(event, key, alternate = false) {
    const file = event.currentTarget.files?.[0], selectedDoc = doc;
    if (!file) return;
    event.currentTarget.value = '';
    if (file.type !== 'image/png') return notify(t('error.invalid_png'), true);
    if (file.size > 65536) return notify(t('error.seal_image_too_large'), true);
    try {
      const image = await new Promise((resolve, reject) => {
        const reader = new FileReader(); reader.onload = () => resolve(reader.result); reader.onerror = reject; reader.readAsDataURL(file);
      });
      if (config.types[selectedDoc.key] !== selectedDoc) return;
      (alternate ? selectedDoc.appearance.forged : selectedDoc.appearance)[key] = image;
      config = { ...config };
    } catch { notify(t('error.invalid_png'), true); }
  }
  onMount(() => {
    const listener = event => {
      if (event.data?.action === 'forge-dk:placement') {
        const placed = config.npcs.find(entry => entry.id === event.data.data.npcId);
        if (!placed) return;
        placed.coords = event.data.data.coords;
        placed.heading = event.data.data.heading;
        config = { ...config };
        notify(t('ui.positioned'));
      }
    };
    window.addEventListener('message', listener);
    return () => window.removeEventListener('message', listener);
  });
</script>

<div class="admin-layout" class:sidebar-collapsed={collapsed}>
  <aside class="navigation">
    <div class="nav-label">{t('ui.management')}</div>
    {#each ['general', 'types', 'npcs', 'records'] as key}
      <button class:active={page === key} aria-label={t('ui.' + key)} aria-current={page === key ? 'page' : undefined} title={t('ui.' + key)} on:click={() => page = key}><Icon name={key} /><span class="nav-text">{t('ui.' + key)}</span>{#if key === 'types' || key === 'npcs'}<span class="nav-count">{key === 'types' ? Object.keys(config.types).length : config.npcs.length}</span>{/if}</button>
    {/each}
    <div class="navigation-bottom"><span>v2.0</span><span>PR BRIDGE</span></div>
  </aside>
  <div class="editor">
    <div class="editor-title"><div><span class="eyebrow">{t('ui.management')}</span><h2>{t('ui.' + page)}</h2></div><button class="primary" disabled={busy} on:click={save}><Icon name="save" />{t(busy ? 'ui.saving' : 'ui.save')}</button></div>
    {#if page === 'general'}
      <FormSection title={t('ui.globalSettings')}>
      <div class="field-grid">
        <label>{t('ui.cityName')}<input bind:value={config.general.cityName} maxlength="80" /></label>
        <label>{t('ui.logo')}<input bind:value={config.general.logo} placeholder="https://..." /></label>
        <label>{t('ui.range')}<input type="number" min="0.5" max="10" step="0.5" bind:value={config.general.range} /></label>
        <label>{t('ui.popup')}<input type="number" min="5000" max="10000" step="1000" bind:value={config.general.popupMs} /></label>
        <label>{t('ui.closeKey')}<input bind:value={config.general.closeKey} /></label>
        <label>{t('ui.locale')}<input bind:value={config.general.locale} placeholder="pt-BR" /></label>
      </div>
      </FormSection>
      <FormSection title={t('ui.headings')}><div class="field-grid">
        {#each Object.keys(config.general.labels) as key}<label><code>{key}</code><input bind:value={config.general.labels[key]} /></label>{/each}
      </div></FormSection>
    {:else if page === 'types'}
      <p class="muted">{t('ui.configHint')}</p>
      <div class="selection-toolbar"><select aria-label={t('ui.selectType')} bind:value={selected} disabled={!Object.keys(config.types).length}>{#each Object.values(config.types) as type}<option value={type.key}>{type.label || type.key}</option>{/each}</select><button on:click={addType} disabled={busy}><Icon name="plus" />{t('ui.addType')}</button>{#if doc}<button class="danger" disabled={busy} on:click={() => deleting = selected}><Icon name="trash" />{t('ui.deleteType')}</button>{/if}</div>
      {#if doc}<div class="type-layout"><div class="type-form">
        <FormSection title={t('ui.documentSettings')} description={t('ui.configHint')}>
        <div class="field-grid">
          <label>{t('ui.key')}<input value={doc.key} disabled={originalKeys.has(selected)} on:change={renameType} /></label>
          <label>{t('ui.label')}<input bind:value={doc.label} /></label>
          <label>{t('ui.item')}<input list="inventory-items" bind:value={doc.item} /><datalist id="inventory-items">{#each data.catalogue as item}<option value={item.name}>{item.label}</option>{/each}</datalist></label>
          <label>{t('ui.format')}<select bind:value={doc.format} on:change={switchFormat}><option value="card">{t('ui.card')}</option><option value="a4">{t('ui.a4')}</option></select></label>
          <label>{t('ui.subject')}<select bind:value={doc.subject}><option value="person">{t('ui.person')}</option><option value="vehicle">{t('ui.vehicle')}</option><option value="business">{t('ui.business')}</option></select></label>
          <label>{t('ui.validity')}<input type="number" min="0" bind:value={doc.validityDays} /></label>
        </div>
        <div class="check-grid">
          <label><input type="checkbox" bind:checked={doc.active} />{t('ui.active')}</label>
          <label><input type="checkbox" bind:checked={doc.requiresAuthorization} />{t('ui.requireAuth')}</label>
          <label><input type="checkbox" bind:checked={doc.allowForgery} />{t('ui.allowForgery')}</label>
          <label><input type="checkbox" bind:checked={doc.requirePhoto} />{t('ui.requirePhoto')}</label>
        </div>
        {#if doc.requiresAuthorization}<div class="field-grid">
          <label>{t('ui.permissionSource')}<select bind:value={doc.permissionSource}><option value="documents">metadata.documents</option><option value="licences">metadata.licences</option></select></label>
          <label>{t('ui.permissionKey')}<input bind:value={doc.permissionKey} /></label>
          <label>{t('ui.category')}<input bind:value={doc.category} placeholder="A" /></label>
        </div>{/if}
        <div class="field-grid">
          {#each ['firstFee', 'reissueFee', 'forgeryFee'] as key}<label>{t('ui.' + key)}<input type="number" min="0" bind:value={doc[key]} /></label>{/each}
        </div>
        </FormSection>
        <FormSection title={t('ui.visualSettings')}><div class="field-grid colours">
          {#each [['background', 'background'], ['secondary', 'secondary'], ['text', 'textColour'], ['accent', 'accent']] as [key, heading]}
            <label>{t('ui.' + heading)}<input type="color" bind:value={doc.appearance[key]} /></label>
          {/each}
        </div>
        <div class="check-grid">{#each ['pattern', 'stamp', 'profileStamp', 'signature'] as key}<label><input type="checkbox" bind:checked={doc.appearance[key]} />{t('ui.' + key)}</label>{/each}
          <label><input type="checkbox" bind:checked={doc.animation} />{t('ui.animation')}</label>
        </div>
        <div class="field-grid">
          <label>{t('ui.headerCity')}<input aria-label={t('ui.headerCity')} bind:value={doc.appearance.headerCity} placeholder={config.general.cityName} maxlength="80" /></label>
          <label>{t('ui.headerTitle')}<input aria-label={t('ui.headerTitle')} bind:value={doc.appearance.headerTitle} placeholder={doc.label} maxlength="80" /></label>
          <label class="asset-field">{t('ui.emblemImage')}<input aria-label={t('ui.emblemImage')} bind:value={doc.appearance.emblemImage} placeholder="https://... / images/logo.png" /><input aria-label={t('ui.uploadEmblem')} type="file" accept="image/png" on:change={event => uploadSeal(event,'emblemImage')} /><small>{t('ui.logoHint')}</small></label>
          <label>{t('ui.documentFont')}<select aria-label={t('ui.documentFont')} bind:value={doc.appearance.fontFamily}>{#each ['sans','serif','mono'] as key}<option value={key}>{t('ui.font'+key[0].toUpperCase()+key.slice(1))}</option>{/each}</select></label>
          {#if doc.appearance.pattern}<label>{t('ui.patternModel')}<select aria-label={t('ui.patternModel')} bind:value={doc.appearance.patternStyle}>
            {#each ['diagonal','grid','waves','dots','guilloche'] as key}<option value={key}>{t('ui.pattern'+key[0].toUpperCase()+key.slice(1))}</option>{/each}
          </select></label><label>{t('ui.patternOpacity')}<input type="number" min="0" max="1" step="0.05" bind:value={doc.appearance.patternOpacity} /></label>{/if}
        </div>
        {#if doc.appearance.stamp}<div class="field-grid">
          <label>{t('ui.stampText')}<input aria-label={t('ui.stampText')} bind:value={doc.appearance.stampText} maxlength="80" /></label>
          <label class="asset-field">{t('ui.stampImage')}<input aria-label={t('ui.stampImage')} bind:value={doc.appearance.stampImage} placeholder="https://... / images/seal.png" /><input aria-label={t('ui.uploadOfficialSeal')} type="file" accept="image/png" on:change={event => uploadSeal(event, 'stampImage')} /><small>{t('ui.sealHint')}</small></label>
          {#if doc.allowForgery}<label class="asset-field">{t('ui.forgedStampImage')}<input aria-label={t('ui.forgedStampImage')} bind:value={doc.appearance.forgedStampImage} placeholder="https://... / images/seal-fake.png" /><input aria-label={t('ui.uploadForgedSeal')} type="file" accept="image/png" on:change={event => uploadSeal(event, 'forgedStampImage')} /><small>{t('ui.forgedSealHint')}</small></label>
          <label>{t('ui.forgedStampText')}<input bind:value={doc.appearance.forgedStampText} maxlength="80" /></label>{/if}
        </div>{/if}
        </FormSection>
        {#if doc.allowForgery}<FormSection title={t('ui.forgedAppearance')}>
          <label class="check"><input aria-label={t('ui.customForgedAppearance')} type="checkbox" bind:checked={doc.appearance.forged.enabled} />{t('ui.customForgedAppearance')}</label>
          {#if doc.appearance.forged.enabled}<div class="field-grid colours">
            {#each [['background','background'],['secondary','secondary'],['text','textColour'],['accent','accent']] as [key,heading]}
              <label>{t('ui.'+heading)}<input aria-label={t('ui.forgedAppearance')+' · '+t('ui.'+heading)} type="color" bind:value={doc.appearance.forged[key]} /></label>
            {/each}
          </div><div class="field-grid">
            <label>{t('ui.documentFont')}<select aria-label={t('ui.forgedAppearance')+' · '+t('ui.documentFont')} bind:value={doc.appearance.forged.fontFamily}>{#each ['sans','serif','mono'] as key}<option value={key}>{t('ui.font'+key[0].toUpperCase()+key.slice(1))}</option>{/each}</select></label>
            <label class="asset-field">{t('ui.forgedEmblemImage')}<input aria-label={t('ui.forgedEmblemImage')} bind:value={doc.appearance.forged.emblemImage} placeholder="https://... / images/logo-fake.png" /><input aria-label={t('ui.uploadForgedEmblem')} type="file" accept="image/png" on:change={event => uploadSeal(event,'emblemImage',true)} /><small>{t('ui.forgedLogoHint')}</small></label>
            <label>{t('ui.patternModel')}<select aria-label={t('ui.forgedAppearance')+' · '+t('ui.patternModel')} bind:value={doc.appearance.forged.patternStyle}>{#each ['diagonal','grid','waves','dots','guilloche'] as key}<option value={key}>{t('ui.pattern'+key[0].toUpperCase()+key.slice(1))}</option>{/each}</select></label>
            <label>{t('ui.patternOpacity')}<input aria-label={t('ui.forgedAppearance')+' · '+t('ui.patternOpacity')} type="number" min="0" max="1" step="0.05" bind:value={doc.appearance.forged.patternOpacity} /></label>
          </div>{/if}
        </FormSection>{/if}
        <FormSection title={t('ui.presentationTiming')}><div class="field-grid">
          <label>{t('ui.displayMs')}<input aria-label={t('ui.displayMs')} type="number" min="0" max="120000" step="1000" bind:value={doc.displayMs} /><small>{t('ui.displayMsHint')}</small></label>
          {#if doc.animation}<label>{t('ui.animationMs')}<input aria-label={t('ui.animationMs')} type="number" min="250" max="10000" step="250" bind:value={doc.animationMs} /><small>{t('ui.animationMsHint')}</small></label>{/if}
        </div>
        {#if doc.animation}<div class="field-grid">
          <label>{t('ui.presentationStyle')}<select aria-label={t('ui.presentationStyle')} bind:value={doc.presentationStyle}><option value="police">{t('ui.police')}</option><option value="citizen">{t('ui.citizen')}</option></select></label>
          <label>{t('ui.prop')}<input bind:value={doc.prop} placeholder={doc.format === 'a4' ? 'h4_prop_h4_files_paper_01b' : 'prop_franklin_dl'} /><small>{t('ui.propHint')}</small></label>
        </div>{/if}
        </FormSection>
        <FormSection title={t('ui.headings')}><div class="field-grid">
          {#each Object.keys(config.general.labels) as key}<label><code>{key}</code><input value={doc.labels?.[key] || ''} placeholder={config.general.labels[key]} on:input={event => setLabel(key, event.currentTarget.value)} /></label>{/each}
        </div>
        {#if doc.allowForgery}<h3>{t('ui.forgedIdentity')}</h3><div class="check-grid">
          {#each ['id', 'firstName', 'lastName', 'dob', 'sex'] as key}<label><input type="checkbox" bind:checked={doc.forgeableIdentity[key]} />{config.general.labels[key]}</label>{/each}
        </div>{/if}
        </FormSection>
        <FormSection title={t('ui.body')}><label><textarea rows="5" bind:value={doc.body}></textarea><small>{t('ui.bodyHint')}</small></label></FormSection>
        <FormSection title={t('ui.customFields')} description={t('ui.fieldSourceHint')}>
        <div class="section-title"><span></span><button on:click={addField}><Icon name="plus" />{t('ui.addField')}</button></div>
        {#each doc.fields as field, i}<div class="field-card"><div class="field-grid">
          <label>{t('ui.fieldKey')}<input bind:value={field.key} /></label><label>{t('ui.fieldLabel')}<input bind:value={field.label} /></label>
          <label>{t('ui.source')}<select bind:value={field.source}><option value="input">{t('ui.input')}</option><option value="identity">{t('ui.identity')}</option></select></label>
          <label>{t('ui.fieldType')}<select bind:value={field.type}>{#each ['text', 'number', 'date', 'textarea'] as key}<option value={key}>{t('ui.field' + key[0].toUpperCase() + key.slice(1))}</option>{/each}</select></label>
          <label class="wide">{t('ui.default')}{#if field.type === 'date'}<input value={formatDateInput(field.default)} inputmode="numeric" maxlength="10" placeholder="DD/MM/YYYY" on:input={event => { field.default = formatDateInput(event.currentTarget.value); event.currentTarget.value = field.default; doc = doc; }} />{:else}<input bind:value={field.default} />{/if}</label>
        </div><div class="check-grid"><label><input type="checkbox" bind:checked={field.required} />{t('ui.required')}</label><label><input type="checkbox" bind:checked={field.forgeable} />{t('ui.forgeable')}</label></div>
        <button class="danger" on:click={() => doc.fields = doc.fields.filter((_, index) => index !== i)}>{t('ui.remove')}</button></div>{/each}
        </FormSection>
      </div><aside class="preview-pane"><span class="eyebrow">{t('ui.preview')}</span>{#if doc.allowForgery}<label class="check preview-mode"><input type="checkbox" bind:checked={forgedPreview} />{t('ui.previewForgery')}</label>{/if}<LayoutEditor {doc} {preview} locale={config.general.locale} onChange={value => { config.types[selected] = value; config = {...config}; }} /><small>{t('ui.snapshotHint')}</small></aside></div>{:else}<div class="empty-state"><Icon name="document" /><h3>{t('ui.noTypes')}</h3><p>{t('ui.noTypesHint')}</p><button class="primary" on:click={addType}><Icon name="plus" />{t('ui.addType')}</button></div>{/if}
    {:else if page === 'npcs'}
      <div class="selection-toolbar"><select aria-label={t('ui.selectNpc')} bind:value={npcId}><option value="">—</option>{#each config.npcs as entry}<option value={entry.id}>{entry.label || entry.id}</option>{/each}</select><button on:click={addNpc}><Icon name="plus" />{t('ui.addNpc')}</button></div>
      {#if !config.npcs.length}<p class="muted">{t('ui.noNpcs')}</p>{/if}
      {#if npc}<FormSection title={t('ui.npcSettings')}><div class="field-grid">
        <label>{t('ui.label')}<input bind:value={npc.label} /></label><label>{t('ui.model')}<input bind:value={npc.model} /></label>
        <label>{t('ui.subject')}<select bind:value={npc.mode}><option value="official">{t('ui.official')}</option><option value="forgery">{t('ui.forgery')}</option></select></label>
        <label>{t('ui.distance')}<input type="number" min="1" max="5" step="0.5" bind:value={npc.distance} /></label>
        <label>{t('ui.heading')}<input aria-label={t('ui.heading')} type="number" value={npc.heading} readonly /><small>{t('ui.headingHint')}</small></label>
        <label>{t('ui.interaction')}<select value={npc.interaction || 'interact'} on:change={event => { npc.interaction = event.currentTarget.value; config = { ...config }; }}><option value="interact">Interact</option><option value="target">Target</option></select></label>
      </div><label class="check"><input type="checkbox" bind:checked={npc.enabled} />{t('ui.enabled')}</label>
      <label class="check"><input type="checkbox" checked={npc.wallDetection !== false} on:change={event => { npc.wallDetection = event.currentTarget.checked; config = { ...config }; }} />{t('ui.wallDetection')}</label>
      <button class="primary" on:click={position}><Icon name="npcs" />{t('ui.position')}</button>
      <p class="coordinates">{npc.coords ? [npc.coords.x, npc.coords.y, npc.coords.z].map(value => Number(value).toFixed(2)).join(' · ') : '—'}</p>
      </FormSection><FormSection title={t('ui.services')}><div class="check-grid">{#each Object.values(config.types) as type}<label><input type="checkbox" bind:group={npc.services} value={type.key} />{type.label || type.key}</label>{:else}<p class="muted">{t('ui.noTypes')}</p>{/each}</div></FormSection>
      <button class="danger" on:click={() => { config.npcs = config.npcs.filter(entry => entry.id !== npcId); npcId = ''; }}><Icon name="trash" />{t('ui.remove')}</button>{/if}
    {:else}
      <FormSection title={t('ui.permissions')}><div class="field-grid">
        <label>{t('ui.target')}<input type="number" min="1" bind:value={target} /></label>
        <label>{t('ui.document')}<select bind:value={permissionType}>{#each Object.values(config.types) as type}<option value={type.key}>{type.label}</option>{/each}</select></label>
        <label>{t('ui.category')}<input bind:value={category} placeholder="A" /></label>
      </div><div class="button-row"><button disabled={!permissionType || !target} on:click={() => permission(true)}>{t('ui.grant')}</button><button class="danger" disabled={!permissionType || !target} on:click={() => permission(false)}>{t('ui.deny')}</button></div></FormSection>
      <FormSection title={t('ui.records')}><div class="selection-toolbar"><label>{t('ui.recordSearch')}<input bind:value={search} /></label><button on:click={loadRecords}>{t('ui.search')}</button></div>
      <div class="records-list">{#each records as record}<div class="record-row"><div><strong>{config.types[record.type_key]?.label || record.type_key}</strong><code>{record.serial}</code><small>{record.owner_identifier}</small></div><div><span>{t('ui.' + record.status)}</span><small>{t('ui.copies')}: {record.copies}</small>{#if record.pending_deliveries > 0}<small class="warning-text">{t('ui.pendingDelivery')}</small>{/if}</div><div><button on:click={() => recordInfo(record.serial)}>{t('ui.details')}</button><button class="danger" disabled={record.status === 'revoked'} on:click={() => revoke(record.serial)}>{t(confirmSerial === record.serial ? 'ui.confirmRevoke' : 'ui.revoke')}</button></div></div>{:else}<p class="muted">{t('ui.noRecords')}</p>{/each}</div>
      {#if recordDetail}<div class="record-detail"><Document document={recordDetail.document} locale={config.general.locale} /><h3>{t('ui.receipts')}</h3><p>{t('ui.' + recordDetail.kind)} · {t('ui.' + recordDetail.status)}</p>{#each recordDetail.receipts as receipt}<div class="record-row"><code>{receipt.copy_id}</code><span>{t('ui.' + receipt.status)}</span><span>{receipt.account} · $ {receipt.fee}</span></div>{/each}</div>{/if}</FormSection>
    {/if}
  </div>
</div>
{#if deleting && config.types[deleting]}<ConfirmDialog label={config.types[deleting].label || deleting} onCancel={() => deleting = ''} onConfirm={confirmDelete} />{/if}
