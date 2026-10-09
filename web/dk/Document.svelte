<script>
  import { dateLabel, displayDate, interpolate } from './model.mjs';
  import { layoutFor, moveBox } from './layout.mjs';
  import { t, assetUrl } from './api.mjs';
  export let document;
  export let locale = 'pt-BR';
  export let editing = false;
  export let assetWarnings = false;
  export let selectedElement = '';
  export let onSelect = () => {};
  export let onMove = () => {};
  let sheet, drag = null, failedSeal = '', failedLogo = '';
  $: identity = document.identity || {};
  $: labels = document.labels || {};
  $: appearance = document.appearance || {};
  $: sealUrl = assetUrl(appearance.stampImage);
  $: logoUrl = assetUrl(appearance.emblemImage || document.logo);
  $: documentFont = {sans:'Inter, "Segoe UI", sans-serif',serif:'Georgia, "Times New Roman", serif',mono:'"Consolas", "Courier New", monospace'}[appearance.fontFamily] || 'Inter, "Segoe UI", sans-serif';
  $: fullName = [identity.firstName, identity.lastName].filter(Boolean).join(' ');
  $: layout = layoutFor(document);
  $: elements = [
    {key:'logo',kind:'logo'}, {key:'cityName',kind:'city',value:appearance.headerCity || document.cityName},
    {key:'title',kind:'title',value:appearance.headerTitle || document.label}, {key:'divider',kind:'divider'},
    {key:'photo',kind:'photo',visible:!!document.photo || !!document.requirePhoto || document.format !== 'a4'},
    ...[
      ['id',identity.id],['firstName',identity.firstName],['lastName',identity.lastName],
      ['dob',displayDate(identity.dob)],['sex',identity.sex],['issuedAt',dateLabel(document.issuedAt,locale)],
      ['expiresAt',dateLabel(document.expiresAt,locale) || t('ui.noExpiry')],
    ].map(([key,value]) => ({key,kind:'field',label:labels[key] || key,value})),
    {key:'category',kind:'field',label:t('ui.category'),value:document.category,visible:!!document.category},
    {key:'body',kind:'body',value:interpolate(document.body,document),visible:!!document.body},
    ...(document.fields || []).map(field => ({key:'field:'+field.key,kind:'field',label:field.label,value:displayDate(field.value)})),
    {key:'signature',kind:'signature',value:fullName,visible:!!appearance.signature},
    {key:'serial',kind:'serial',value:document.serial || '—'},
    {key:'profileStamp',kind:'profile',visible:!!appearance.profileStamp && !!document.photo},
    {key:'stamp',kind:'stamp',visible:!!appearance.stamp},
    {key:'stampText',kind:'stampText',value:appearance.stampText || '',visible:!!appearance.stamp && !!appearance.stampText},
  ];
  function start(event,key) {
    if (!editing || event.button !== 0) return;
    event.preventDefault(); onSelect(key);
    const rect = sheet.getBoundingClientRect();
    drag = { key, x:event.clientX, y:event.clientY, rect, box:{...layout[key]}, pointer:event.pointerId };
    event.currentTarget.setPointerCapture(event.pointerId);
  }
  function move(event) {
    if (!drag || event.pointerId !== drag.pointer) return;
    onMove(drag.key,moveBox(drag.box,(event.clientX-drag.x)/drag.rect.width*100,(event.clientY-drag.y)/drag.rect.height*100));
  }
  function end(event) { if (drag?.pointer === event.pointerId) drag = null; }
  function position(key) {
    const p = layout[key];
    return `left:${p.x}%;top:${p.y}%;width:${p.width}%;font-size:${p.fontSize}cqw;text-align:${p.align};`;
  }
</script>

<article bind:this={sheet} class:a4={document.format === 'a4'} class:card={document.format !== 'a4'}
  class:layout-editing={editing} class:pattern={appearance.pattern} class="document-sheet positioned-sheet"
  data-pattern={appearance.patternStyle || 'diagonal'} style:--pattern-opacity={appearance.patternOpacity ?? .18}
  style:--document-font={documentFont} style:--paper={appearance.background} style:--secondary={appearance.secondary} style:--ink={appearance.text} style:--accent={appearance.accent}>
  {#each elements as element (element.key)}
    {#if !layout[element.key].hidden && (element.visible !== false || editing && selectedElement === element.key)}
      <!-- svelte-ignore a11y_no_noninteractive_tabindex (interactive only in the layout editor, with keyboard selection) -->
      <div class="document-element" class:element-selected={editing && selectedElement === element.key}
        class:element-placeholder={element.visible === false} data-element={element.key} data-kind={element.kind}
        style={position(element.key)} role={editing ? 'button' : undefined} tabindex={editing ? 0 : undefined}
        aria-label={editing ? (element.label || t('ui.element'+element.key[0].toUpperCase()+element.key.slice(1))) : undefined}
        on:keydown={event => { if (editing && (event.key === 'Enter' || event.key === ' ')) onSelect(element.key); }}
        on:pointerdown={event => start(event,element.key)} on:pointermove={move} on:pointerup={end} on:pointercancel={end}>
        {#if element.kind === 'logo'}
          {#if logoUrl && failedLogo !== logoUrl}<img class="city-logo" src={logoUrl} alt={document.cityName} on:error={() => failedLogo = logoUrl} />{:else}<div class="city-emblem" aria-hidden="true">◇</div>{/if}
          {#if logoUrl && failedLogo === logoUrl && assetWarnings}<small class="seal-error">{t('ui.logoLoadError')}</small>{/if}
        {:else if element.kind === 'city'}<span class="city-name">{element.value}</span>
        {:else if element.kind === 'title'}<h2>{element.value}</h2>
        {:else if element.kind === 'divider'}<hr />
        {:else if element.kind === 'photo'}<div class="portrait">{#if document.photo}<img src={document.photo} alt={fullName} />{:else}<span>◯</span>{/if}</div>
        {:else if element.kind === 'field'}<dl><dt>{element.label}</dt><dd>{element.value || '—'}</dd></dl>
        {:else if element.kind === 'body'}<div class="document-body">{element.value || t('ui.body')}</div>
        {:else if element.kind === 'signature'}<div class="handwriting">{element.value}</div>
        {:else if element.kind === 'serial'}<small class="document-serial">{element.value}</small>
        {:else if element.kind === 'profile'}<img class="photo-stamp" src={document.photo || ''} alt="" />
        {:else if element.kind === 'stamp'}
          {#if sealUrl && failedSeal !== sealUrl}<img class="seal-image" src={sealUrl} alt={t('ui.stamp')} on:error={() => failedSeal = sealUrl} />
          {:else}<div class="city-seal" class:single={appearance.stampStyle === 'single'}>{#if logoUrl && failedLogo !== logoUrl}<img class="seal-emblem" src={logoUrl} alt="" on:error={() => failedLogo = logoUrl} />{:else}<span>◇</span>{/if}<small>{document.cityName}</small></div>{/if}
          {#if sealUrl && failedSeal === sealUrl && assetWarnings}<small class="seal-error">{t('ui.sealLoadError')}</small>{/if}
        {:else if element.kind === 'stampText'}<span class="stamp-caption">{element.value || t('ui.stampText')}</span>{/if}
      </div>
    {/if}
  {/each}
</article>

<style>
  /* Keep the pattern rules scoped so legacy document styles cannot override the selected model. */
  .document-sheet { font-family: var(--document-font, 'Segoe UI', sans-serif); }
  .document-sheet.pattern::before {
    opacity: var(--pattern-opacity, .18);
    background: repeating-linear-gradient(45deg, transparent 0 10px, var(--secondary) 11px, transparent 12px);
  }
  .document-sheet.pattern[data-pattern=grid]::before {
    background: repeating-linear-gradient(0deg, transparent 0 14px, var(--secondary) 15px 16px),
      repeating-linear-gradient(90deg, transparent 0 14px, var(--secondary) 15px 16px);
  }
  .document-sheet.pattern[data-pattern=dots]::before {
    background: radial-gradient(var(--secondary) 1.5px, transparent 2px);
    background-size: 11px 11px;
  }
  .document-sheet.pattern[data-pattern=waves]::before {
    background: repeating-radial-gradient(ellipse at 20% 80%, transparent 0 7px, var(--secondary) 8px 9px, transparent 10px 14px);
  }
  .document-sheet.pattern[data-pattern=guilloche]::before {
    background: repeating-radial-gradient(ellipse at 0% 50%, transparent 0 8px, var(--secondary) 9px 10px, transparent 11px 18px),
      repeating-radial-gradient(ellipse at 100% 50%, transparent 0 8px, var(--secondary) 9px 10px, transparent 11px 18px);
  }
  .seal-emblem { width: 60%; height: 60%; object-fit: contain; }
</style>
