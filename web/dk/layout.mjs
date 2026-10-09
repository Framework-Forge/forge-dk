// Percent coordinates are format-specific and remain proportional at every NUI resolution.
const box = (x, y, width, fontSize = 2, align = 'left') => ({ x, y, width, fontSize, align, hidden: false });
export function defaultLayout(format = 'card', fields = []) {
  const a4 = format === 'a4';
  const result = a4 ? {
    logo: box(7,5,9), cityName: box(20,5,72,2.2), title: box(20,8,72,3.7), divider: box(7,13,86),
    photo: box(7,17,22), id: box(34,17,28), firstName: box(66,17,27), lastName: box(34,23,28),
    dob: box(66,23,27), sex: box(34,29,28), issuedAt: box(66,29,27), expiresAt: box(34,35,28),
    category: box(66,35,27), body: box(7,43,86,2.6), signature: box(7,85,48,4), serial: box(7,92,53,1.3),
    profileStamp: box(67,87,7), stamp: box(79,84,14), stampText: box(74,96,21,1.6,'center'),
  } : {
    logo: box(4.5,7,6), cityName: box(12,7,82,1.8), title: box(12,11,82,3.4), divider: box(4.5,19,91),
    photo: box(4.5,24,23), id: box(31,24,32), firstName: box(68,24,27), lastName: box(31,34,32),
    dob: box(68,34,27), sex: box(31,44,32), issuedAt: box(68,44,27), expiresAt: box(31,54,32),
    category: box(68,54,27), body: box(4.5,68,91,2.2), signature: box(4.5,80,50,4), serial: box(4.5,94,58,1.3),
    profileStamp: box(77,84,6), stamp: box(85,81,11), stampText: box(82,96,16,1.4,'center'),
  };
  fields.forEach((field, index) => {
    result['field:' + field.key] = a4 ? box(7 + (index % 2) * 45, 58 + Math.floor(index / 2) * 6, 41,2.1)
      : box(4.5 + (index % 2) * 47, 65 + Math.floor(index / 2) * 7, 44,1.8);
  });
  return result;
}
export function layoutFor(document) {
  const defaults = defaultLayout(document.format, document.fields || []);
  if (document.format === 'a4' && !document.photo && !document.requirePhoto) {
    for (const key of ['id','lastName','sex','expiresAt']) Object.assign(defaults[key],{x:7,width:40});
    for (const key of ['firstName','dob','issuedAt','category']) Object.assign(defaults[key],{x:54,width:39});
  }
  const overrides = document.layout?.[document.format === 'a4' ? 'a4' : 'card'] || {};
  const result = {};
  for (const [key, fallback] of Object.entries(defaults)) result[key] = sanitizeBox(overrides[key], fallback);
  return result;
}
const number = (value, min, max, fallback) => Number.isFinite(Number(value)) ? Math.min(max,Math.max(min,Number(value))) : fallback;
export function sanitizeBox(value = {}, fallback = box(0,0,20)) {
  const x = number(value.x,0,98,fallback.x);
  return { x, y:number(value.y,0,98,fallback.y), width:number(value.width,1,100-x,Math.min(fallback.width,100-x)),
    fontSize:number(value.fontSize,.5,8,fallback.fontSize), hidden:value.hidden ?? fallback.hidden,
    align:['left','center','right'].includes(value.align) ? value.align : fallback.align };
}
export function moveBox(value, dx, dy) {
  return sanitizeBox({ ...value, x:number(value.x + dx,0,100-value.width,value.x), y:value.y + dy }, value);
}
