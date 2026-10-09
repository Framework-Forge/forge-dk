import fallback from '../../locales/pt-br.json';
let translations = fallback;
export function setTranslations(value) { translations = { ...fallback, ...(value || {}) }; }
export function t(key) { return translations[key] || key; }
export function assetUrl(value) {
  if (String(value || '').startsWith('images/')) {
    return window.GetParentResourceName ? 'https://cfx-nui-' + window.GetParentResourceName() + '/' + value : '../../' + value;
  }
  return value || '';
}
export function errorText(error) {
  const [code, detail] = String(error || 'operation_failed').split(':');
  return t('error.' + code) + (detail ? ' (' + detail + ')' : '');
}
export async function nui(action, data = {}) {
  if (!window.GetParentResourceName) return { ok: false, error: 'connection_failed' };
  try {
    const response = await fetch('https://' + window.GetParentResourceName() + '/' + action, {
      method: 'POST', headers: { 'Content-Type': 'application/json; charset=UTF-8' }, body: JSON.stringify(data) });
    return await response.json();
  } catch { return { ok: false, error: 'connection_failed' }; }
}
export async function headshot(txd) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    const timeout = setTimeout(() => { image.onload = image.onerror = null; reject(new Error('photo_timeout')); }, 4500);
    image.crossOrigin = 'anonymous';
    image.onload = () => {
      clearTimeout(timeout);
      try {
        const canvas = document.createElement('canvas');
        canvas.width = canvas.height = 192;
        const ctx = canvas.getContext('2d');
        if (!ctx || !image.naturalWidth) throw new Error('photo_failed');
        ctx.drawImage(image, 0, 0, 192, 192);
        resolve(canvas.toDataURL('image/png'));
      } catch (error) { reject(error); }
    };
    image.onerror = () => { clearTimeout(timeout); reject(new Error('photo_failed')); };
    image.src = 'https://nui-img/' + encodeURIComponent(txd) + '/' + encodeURIComponent(txd);
  });
}
