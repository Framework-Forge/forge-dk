export function interpolate(body, document) {
  const values = { ...(document.identity || {}) };
  for (const field of document.fields || []) values[field.key] = field.value;
  return String(body || '').replace(/\{\{([\w]+)\}\}/g, (_, key) => String(values[key] ?? ''));
}
export function dateLabel(seconds, locale = 'pt-BR') {
  if (!seconds) return '';
  const date = new Date(Number(seconds) * 1000);
  if (!Number.isFinite(date.getTime())) return '';
  try { return date.toLocaleDateString(locale); } catch { return date.toLocaleDateString('pt-BR'); }
}
export function normalizeDate(value) {
  const text = String(value || '');
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  const local = /^(\d{2})\/(\d{2})\/(\d{4})$/.exec(text);
  if (!iso && !local) return null;
  const [year, month, day] = iso ? iso.slice(1).map(Number) : [Number(local[3]), Number(local[2]), Number(local[1])];
  const leap = year % 4 === 0 && (year % 100 !== 0 || year % 400 === 0);
  const days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (year < 1 || year > 9999 || month < 1 || month > 12 || day < 1 || day > days[month - 1]) return null;
  return `${String(year).padStart(4, '0')}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
}
export function formatDateInput(value) {
  const text = String(value || '');
  const iso = /^(\d{4})-(\d{2})-(\d{2})$/.exec(text);
  if (iso) return `${iso[3]}/${iso[2]}/${iso[1]}`;
  const digits = text.replace(/\D/g, '').slice(0, 8);
  return [digits.slice(0, 2), digits.slice(2, 4), digits.slice(4)].filter(Boolean).join('/');
}
export function displayDate(value) {
  return /^\d{4}-\d{2}-\d{2}$/.test(String(value)) ? formatDateInput(value) : value;
}
export function documentAppearance(appearance = {}, forged = false) {
  const { forgedStampImage, forgedStampText, forged: alternate, ...result } = appearance;
  if (forged && alternate?.enabled) {
    for (const key of ['background','secondary','text','accent','fontFamily','patternStyle','patternOpacity']) {
      if (alternate[key] !== undefined) result[key] = alternate[key];
    }
    if (alternate.emblemImage) result.emblemImage = alternate.emblemImage;
  }
  return { ...result, stampImage: forged ? (forgedStampImage || '') : (appearance.stampImage || ''),
    stampStyle: forged ? 'single' : 'double', stampText: forged ? (forgedStampText || '') : (appearance.stampText || '') };
}
export function previewDocument(definition, general, identity = {}, forged = false) {
  return { ...definition, cityName: general.cityName, logo: general.logo,
    appearance: documentAppearance(definition.appearance, forged),
    labels: { ...general.labels, ...(definition.labels || {}) },
    identity: { id: 'DK-000001', firstName: 'Pierre', lastName: 'Moraes', dob: '01/01/1990', sex: 'M', ...identity },
    serial: 'DK-PREVIEW', copyNumber: 1, issuedAt: Date.now() / 1000,
    expiresAt: definition.validityDays ? Date.now() / 1000 + definition.validityDays * 86400 : 0,
    fields: (definition.fields || []).map(field => ({ ...field, value: field.default || '—' })) };
}
export function newDocument(key, item = 'id_card') {
  return { key, item, label: '', format: 'card', active: true, requiresAuthorization: false,
    permissionSource: 'documents', permissionKey: key, category: '', firstFee: 0, reissueFee: 0,
    forgeryFee: 0, allowForgery: false, requirePhoto: true, validityDays: 0, subject: 'person',
    animation: true, animationMs: 2500, displayMs: 0, presentationStyle: 'police', prop: '', body: '', fields: [], labels: {}, layout: {card:{},a4:{}},
    forgeableIdentity: { id: false, firstName: false, lastName: false, dob: false, sex: false },
    appearance: { background: '#172a40', secondary: '#29455f', text: '#ffffff', accent: '#e59a32',
      pattern: true, patternStyle: 'diagonal', patternOpacity: .18, stamp: true, profileStamp: false,
      signature: true, headerCity: '', headerTitle: '', emblemImage: '', fontFamily: 'sans', forged: {enabled:false},
      stampText: '', stampImage: '', forgedStampImage: '', forgedStampText: '' } };
}

export function removeDocumentType(config, key) {
  if (!Object.hasOwn(config.types || {}, key)) return config;
  const types = { ...config.types };
  delete types[key];
  return { ...config, types, npcs: (config.npcs || []).map(npc => ({ ...npc,
    services: (npc.services || []).filter(service => service !== key) })) };
}
