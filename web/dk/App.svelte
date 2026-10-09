<script>
  import { onMount } from 'svelte';
  import Admin from './Admin.svelte';
  import Service from './Service.svelte';
  import Document from './Document.svelte';
  import Icon from './Icon.svelte';
  import { nui, setTranslations, t, headshot, errorText } from './api.mjs';
  let mode = '', payload = null, general = {}, notice = '', noticeError = false, noticeTimer;
  let suspended = false, suspendReason = '';
  let collapsed = false;
  function notify(message, error = false) {
    notice = message; noticeError = error;
    clearTimeout(noticeTimer);
    noticeTimer = setTimeout(() => notice = '', 6000);
  }
  async function close() { await nui('close'); mode = ''; payload = null; suspended = false; }
  onMount(() => {
    const receive = async event => {
      const { action, data } = event.data || {};
      if (action === 'forge-dk:close') { mode = ''; payload = null; suspended = false; }
      if (action === 'forge-dk:suspend') { suspended = data.hidden; suspendReason = data.reason || ''; }
      if (action === 'forge-dk:configuration') general = data.general;
      if (action === 'forge-dk:bootstrap') { setTranslations(data.translations); general = data.config.general; }
      if (action === 'forge-dk:admin') { setTranslations(data.translations); mode = 'admin'; payload = data; general = data.config.general; }
      if (action === 'forge-dk:service') { mode = 'service'; payload = data; general = data.general; }
      if (action === 'forge-dk:document') { mode = 'document'; payload = data; }
      if (action === 'forge-dk:photo') {
        let image = null;
        try { image = await headshot(data.txd); } catch {}
        await nui('photoResolved', { token: data.token, image });
      }
    };
    const keys = event => { if (event.key === 'Escape' && mode && !suspended && !document.querySelector('dialog[open]')) close(); };
    window.addEventListener('message', receive);
    window.addEventListener('keydown', keys);
    nui('loaded').then(result => { if (result.ok) { setTranslations(result.data.translations); general = result.data.config.general; } });
    if (!window.invokeNative && new URLSearchParams(window.location.search).has('preview')) {
      import('./preview.mjs').then(module => { payload = module.adminFixture(); general = payload.config.general; mode = 'admin'; });
    }
    return () => { window.removeEventListener('message', receive); window.removeEventListener('keydown', keys); clearTimeout(noticeTimer); };
  });
</script>

{#if mode === 'admin' || mode === 'service'}
  <div class="panel-backdrop" class:suspended aria-hidden={suspended}><section class="panel-shell">
    <header class="panel-header"><div class="brand-mark"><Icon name="brand" /></div><div class="panel-heading"><span class="eyebrow">FORGE DK</span><h1>{mode === 'admin' ? t('ui.subtitle') : payload.npc.label}</h1></div><div class="header-actions">
      {#if mode === 'admin'}<button class="icon-button" aria-label={t('ui.toggleNavigation')} title={t('ui.toggleNavigation')} aria-expanded={!collapsed} on:click={() => collapsed = !collapsed}><Icon name="menu" /></button>{/if}
      <button class="close-button icon-button" aria-label={t('ui.close')} title={t('ui.close')} on:click={close}><Icon name="close" /></button>
    </div></header>
    {#if mode === 'admin'}<Admin data={payload} {notify} {collapsed} />{:else}<Service data={payload} {notify} />{/if}
  </section></div>
{:else if mode === 'document'}
  <div class="document-viewer"><Document document={payload.document} locale={general.locale || 'pt-BR'} />
  </div>
{/if}
{#if suspended && suspendReason === 'photo'}<div class="photo-scene" aria-live="polite"><div>{t('ui.photoScene')}<small>{t('ui.photoCancel')}</small></div></div>{/if}
{#if notice && !suspended}<div role="status" class:error={noticeError} class="toast">{notice}</div>{/if}
