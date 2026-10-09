# Forge DK

Sistema de documentos da Forge: administração, atendimento, foto e visualização em NUI Svelte própria. O catálogo de itens continua no Forge Core; o framework continua autoritativo no QBX. Integrações passam pelo PR Bridge.

## Primeiros passos

1. Reinicie o `pr_bridge` atualizado e os recursos consumidores dele em ambiente de teste.
2. Inicie `forge-dk` após `pr_bridge`, `forge-core` e `ox_inventory`. A interface compilada já está em `web/build`.
3. Um administrador com ACE `forge-core.admin` (ou grupo admin reconhecido pelo bridge) abre `/forgedk`, ou **Forge DK — Documentos** no menu principal do Forge Core. Os dois acessos validam a permissão no servidor do DK.
4. Em **Geral**, configure cidade, logo HTTPS, títulos, distância e tempo de apresentação.
5. Em **Tipos de documento**, vincule um item existente, não empilhável e sem ação consumível/export concorrente. Defina cartão/A4, visual, autorização, categoria, campos e taxas.
6. Em **Atendimentos**, crie um NPC, posicione pelo editor do PR Bridge, marque os serviços oferecidos e salve. Nenhum local é criado automaticamente.
7. O jogador interage com o NPC, tira a foto quando exigida, escolhe dinheiro/banco e recebe o item com todas as informações. Use o item para visualizar e o botão do painel para apresentar aos próximos.

Configurações do painel são salvas em `data/config.json` com recuperação do PR Bridge e controle de revisão. As tabelas SQL são criadas na primeira inicialização pelo adaptador de banco do bridge. Não há SQL executado diretamente pelo Forge DK nem dependência de BL Bridge.

## Defaults e autorização

- `id_card`: livre acesso, primeira emissão gratuita, segunda via 100.
- `weapon_license`: item `weaponlicense`, requer `metadata.licences.weapon == true`.
- Categorias e permissões novas ficam em `metadata.documents`; os booleans legados não são substituídos por tabelas.
- Um tipo com categoria requer tanto a permissão principal como a categoria. Conceder a categoria habilita a permissão principal; revogá-la preserva outras categorias.
- Falsificação vem desligada por padrão. Habilite por tipo, escolha os campos falsificáveis e ofereça em um NPC de modo clandestino. Falsificar não concede nenhuma autorização.
- Cada tipo tem um item exclusivo. Desativar uma emissão não impede apresentar documentos já emitidos.
- Documentos para veículos/empresas exigem um validador de vínculo registrado pelo script responsável.

## Registro e apresentação

`forge_dk_documents` guarda o registro e `forge_dk_document_copies` guarda cada via e os comprovantes de entrega. A segunda via é calculada pelo histórico oficial, não pelo item que está na mochila.

O item guarda um snapshot em `metadata.document`: identidade, foto, layout, títulos, texto, campos, serial, validade e via. Transferir o item não altera seu titular. Apresentação lê apenas o slot real no inventário, sem consulta SQL. Alterações de configuração não reescrevem documentos antigos.

A validade usa dias reais, com timestamp persistente. Documentos vencidos/revogados bloqueiam segunda via; renovação/reabilitação é uma evolução separada, não um bypass automático. O selo e a assinatura são visuais, não assinatura digital jurídica.

Verificação oficial é uma operação separada via export e consulta o registro: não confie em flags presentes no item para verificar autenticidade ou conceder licenças.

## Integração e limites

Veja `docs/INTEGRATION.md` para exports, ACE, categorias, validadores e tratamento de entregas pendentes; `docs/TESTING.md` para validação e checklist no FiveM.

Personagens novos entram sem documentos: a primeira identidade e as demais vias/licenças são emitidas no atendimento do Forge DK. O QBX exclui apenas documentos da entrega inicial, inclusive nomes legados em kits já salvos e itens vinculados aos tipos do DK (mesmo inativos). Os outros itens, quantidades e geradores de metadata seguem o fluxo existente. Nenhuma configuração de kit no banco é reescrita e nenhum item de personagem existente é removido. Se DK estiver iniciando/parado, os vínculos salvos em `data/config.json` (ou sua recuperação `.bak`) são lidos apenas para essa classificação; isso não bloqueia os demais itens do kit.

A tecla global de fechar é registrada com o default da configuração bootstrap; remapeamentos feitos pelo jogador no FiveM são preservados. Mudar esse default no painel não substitui automaticamente um binding já registrado.

## Desenvolvimento e origem

Fontes Svelte em `web/dk`; `npm install` e `npm run build` dentro de `web` quando precisar recompilar. O builder também aceita `--toolchain <pasta com dependências instaladas>`. A homologação desta entrega reutilizou o toolchain Svelte do PR Bridge, sem instalar dependências.

Recurso derivado do ID Card open source de Byte Labs. A licença e os créditos originais foram preservados. O script anterior foi copiado integralmente para backup antes da migração e não precisa ficar iniciado em paralelo.
