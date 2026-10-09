import { newDocument } from './model.mjs';
export function adminFixture() {
  const id = { ...newDocument('id_card'), label: 'Identidade', firstFee: 0, reissueFee: 100, allowForgery: true };
  const permit = { ...newDocument('alvara_bebidas', 'alvara_bebidas'), label: 'Alvará de funcionamento', format: 'a4',
    requiresAuthorization: true, requirePhoto: false, body: 'A cidade de Forge autoriza {{firstName}} {{lastName}} a exercer a atividade descrita neste documento.',
    fields: [{ key: 'estabelecimento', label: 'Estabelecimento', source: 'input', type: 'text', required: true, forgeable: false, default: 'Comércio da Praça' }],
    appearance: { ...id.appearance, background: '#f7f2e8', secondary: '#eae1d0', text: '#253447' } };
  return { catalogue: [{ name: 'id_card', label: 'Identidade', stack: false }, { name: 'alvara_bebidas', label: 'Alvará', stack: false }],
    config: { schemaVersion: 1, revision: 1, general: { cityName: 'Forge', logo: '', locale: 'pt-BR', range: 3, popupMs: 10000, closeKey: 'BACK',
      labels: { id: 'IRG', firstName: 'Nome', lastName: 'Sobrenome', dob: 'Nascimento', sex: 'Sexo', issuedAt: 'Expedição', expiresAt: 'Validade' } },
      types: { id_card: id, alvara_bebidas: permit }, npcs: [] } };
}

