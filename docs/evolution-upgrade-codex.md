# Avaliação Codex: custom-2.2.3 → 2.3.4

**Data:** 2025-10-03  
**Base atual:** branch `custom-2.2.3`  
**Alvo oficial:** tag `2.3.4`

---

## Resumo Executivo
- ✅ **Migrar é viável**, mas vários hotfixes locais continuam ausentes na `2.3.4` e precisam ser reimplantados.
- 2.3.4 entrega ganhos relevantes (Kafka, métricas Prometheus, Evolution Manager v2, correções de segurança), mas **não substitui** correções críticas do seu fork (import Chatwoot, cache, mídia, S3, mutex).
- Estratégia sugerida: fazer merge limpo com `2.3.4`, aplicar somente os patches ainda necessários (listados abaixo) e validar com roteiro de testes focado em Chatwoot, Baileys/S3 e fluxo de provisionamento.

---

## O que já está coberto na 2.3.4 (pode descartar)
- **Atualização de contatos @lid**: a rotina oficial agora atualiza `identifier`/`phone_number` quando o `senderPn` muda (`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:467`, tag 2.3.4).
- **Formatação básica de mensagens em grupos**: a versão oficial já formata DDI/DDD e evita repetir prefixo para mensagens enviadas por você (`src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:2145`, tag 2.3.4). O seu patch acrescenta salvaguardas extras (ver abaixo), mas o cabeçalho padrão já existe.

> Fora esses dois pontos, nenhum outro ajuste structural do fork foi absorvido pela 2.3.4.

---

## Customizações que ainda precisam ser mantidas/portadas
| Área | Referência no fork | Situação na 2.3.4 | Risco se remover | Ação recomendada |
| --- | --- | --- | --- | --- |
| `whatsappNumber` serializado | `src/api/controllers/chat.controller.ts:21-50` (branch custom-2.2.3) | Ausente | Race condition reativando sessão com dois requests simultâneos | Reaplicar `SimpleMutex`
| Cache TTL + validação de chave | `src/api/services/cache.service.ts:34-76` | Ausente | `cache.delete` com vCard quebra monitoramento; TTL infinito causa vazamento | Reaplicar default TTL e logs
| S3 bucket policy tolerante | `src/api/integrations/storage/s3/libs/minio.server.ts:35-62` | Ausente | Deploy em MinIO retorna `NotImplemented` e aborta startup | Reaplicar try/catch e log
| Upload de mídia usa `key.id` | `src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts:1299-1329` | Oficial mantém `Date.now() + nome original` | Arquivos duplicados e sem extensão coerente | Reaplicar renome para `${key.id}${ext}`
| Guard `key.id` nas atualizações | `.../whatsapp.baileys.service.ts:1438-1446` | Ausente | Atualizações sem `id` quebram webhook/status | Reaplicar guard + warn
| Fallback `status ?? 'UNKNOWN'` | `.../whatsapp.baileys.service.ts:1529-1536` | Ausente | Quebra consumer que espera string | Reaplicar fallback
| `getBase64FromMediaMessage` resiliente (reupload + metadados) | `.../whatsapp.baileys.service.ts:3647-3768` | Oficial tem fallback parcial, mas não força reupload nem corrige metadata | Falhas ao baixar mídia expirada e inconsistências de metadata | Reaplicar melhorias críticas; manter apenas diffs necessários
| `addLabel` em chats | `.../whatsapp.baileys.service.ts:4496-4526` | Oficial ainda usa UPSERT com INSERT | Criar chats “fantasmas” quando não existe conversa local | Reaplicar update defensivo
| Chatwoot `createContact` com ID direto | `src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts:289-371` | Oficial faz round-trip `findContact` | Contact recém-criado sem label (race) | Reaplicar extração de `id` do payload e retry de label
| Salvaguarda para `participant` ausente | `.../chatwoot.service.ts:2209-2227` | Ausente | Erro em webhooks sem `participant` (ex.: broadcast) | Reaplicar apenas o guard `if (!participantJid)`
| Import Chatwoot – normalização BR e busca por `identifier` | `src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts:405-520` | Oficial usa CTE simples | Contatos duplicados e perda de histórico com números sem 9 | Manter rotina step-by-step ou incorporar normalização à CTE
| Import Chatwoot – chunking correto | `.../chatwoot-import-helper.ts:722-727` | Oficial mantém bug `splice` | Perda de itens após primeiro chunk | Reaplicar fix simples
| Import Chatwoot – refresh de conversas | `.../chatwoot-import-helper.ts:746-770` | Ausente | Conversa não reabre na UI após import | Reaplicar `safeRefreshConversation`
| Logging detalhado de import | múltiplas linhas 199-418 | Parcial | Diagnóstico de import fica cego | Opcional, mas recomendável portar o que ajudar troubleshooting
| Source maps em produção | `package.json:1-18`, `tsconfig.json:3-12` | Ausente | Stack trace ofuscado em prod | Reaplicar dependência `source-map-support`
| Script `BuildImage.ps1` + ajustes Podman | `BuildImage.ps1`, `Dockerfile:3-9` | Ausente / label diferente | Necessário se pipeline usa Podman + ECR | Reaplicar se pipeline Windows/Podman continuar ativo

---

## Novidades importantes da 2.3.4
- **Kafka**: novos envs (`KAFKA_*`); desative via `KAFKA_ENABLED=false` se não usar imediatamente.
- **/metrics Prometheus**: controlar por `PROMETHEUS_METRICS` para evitar exposição indevida.
- **Evolution Manager v2**: submódulo incluso; ajuste pipelines que clonam o repositório para usar `--recurse-submodules`.
- **Dependências**: Node 24 no Dockerfile oficial; revise compatibilidade com seu runtime (se ficar em Node 20, adapte imagem).
- **Security**: inclui fix de Path Traversal de 2.3.3; mantenha rota `/assets` protegida após merge.

---

## Plano sugerido de migração
1. **Branch de trabalho** a partir de `2.3.4` (tag oficial) + merge do seu fork.
2. **Aplicar novamente** os patches listados na tabela (idealmente como commits isolados para facilitar rebases futuros).
3. **Ajustar build**: decidir entre Docker oficial (Node 24) ou manter imagem custom com source maps/Podman script.
4. **Testes recomendados**:
   - Import histórico Chatwoot (números brasileiros com e sem 9; conversas reabertas).
   - Download de mídia expirada e envio ao S3/MinIO.
   - Rotina `whatsappNumber` sob carga (chamadas simultâneas).
   - Fluxo @lid para garantir que o comportamento oficial atende ao seu caso real.
5. **Verificar novas features** (Kafka, métricas) e desabilitar o que não for usado.

---

## Observabilidade e “Suicídio” Controlado
- Conte os erros recorrentes relatados em `docs/errors.txt` (por exemplo `Connection Closed`, `WebSocket was closed before the connection was established`, `Cannot create property 'senderMessageKeys'...`).
- Mantenha um contador global (em memória) no ponto central de captura (`src/config/error.config.ts` ou em um interceptor de logger) e incremente quando qualquer um desses padrões ocorrer.
- Ao atingir **3 ocorrências consecutivas**, logue o motivo e finalize o processo com `process.exit(1)` quando `EXIT_ON_FATAL=true`; o Docker/Swarm recria o container automaticamente.
- Reinicie o contador quando uma reconexão bem-sucedida for concluída (evento `connection.update` com estado `open`) para evitar resets desnecessários.
- Exponha um `/health` simples ou mantenha métricas internas para monitorar o número de erros antes de um shutdown e alertar o time antes que o serviço pare totalmente.

---

## Itens de atenção antes do deploy
- Conferir se a etiqueta `LABEL version` do Dockerfile oficial está defasada (`2.3.1`): ajustar para refletir a versão interna.
- Garantir que `source-map-support` continue carregado (`node --enable-source-maps -r source-map-support/register`).
- Atualizar documentação/monitoramento para novos endpoints (Kafka, métricas).
- Revisar variáveis de ambiente adicionadas pela Evolution Manager v2 para que ambientes legados não quebrem.

---

## Conclusão
- **Migre para 2.3.4**, mas mantenha os hotfixes críticos relacionados a Chatwoot, Baileys/S3, cache e build.
- O ganho principal é aderir às correções de segurança e novos recursos, sem sacrificar as proteções adicionadas no seu fork.
- Depois do merge, monitore especialmente: importações em massa, uploads de mídia e reconexões WhatsApp.
