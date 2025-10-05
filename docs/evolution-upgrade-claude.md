# Análise de Upgrade: custom-2.2.3 → 2.3.4

**Data:** 2025-10-02 (atualizado 2025-10-03)
**Versão atual em produção:** custom-2.2.3 (v2.2.3.24)
**Versão oficial alvo:** 2.3.4
**Diferença:** 336+ commits

> **Nota:** Este documento consolida duas análises independentes (Claude e Codex) para fornecer visão completa do upgrade.

---

## Resumo Executivo

✅ **RECOMENDAÇÃO: MIGRAR PARA 2.3.4**

A versão 2.3.4 oficial **JÁ INCORPORA** algumas das suas correções customizadas (especialmente @lid), mas **diversos hotfixes críticos ainda precisam ser reaplicados** após o merge. A migração é viável e traz benefícios importantes (Kafka, Prometheus, correções de segurança), mas requer planejamento cuidadoso.

### O que JÁ ESTÁ na 2.3.4 (pode descartar):
- ✅ Tratamento de @lid (atualização de identifier/phone_number)
- ✅ Formatação básica de mensagens em grupos
- ✅ Media download com retry (parcialmente - sua versão é mais robusta)

### O que AINDA PRECISA ser mantido (26 customizações):
- ❌ SimpleMutex no whatsappNumber (race condition)
- ❌ Normalização de números brasileiros (9º dígito)
- ❌ Correção do bug sliceIntoChunks
- ❌ S3 bucket policy tolerante
- ❌ Upload de mídia usa key.id
- ❌ Refresh de conversações no import Chatwoot
- ❌ Source maps em produção
- ❌ E mais 19 customizações... (ver tabela completa abaixo)

---

## 📊 Tabela Consolidada de Customizações

| # | Área | Arquivo | Linha (custom) | Status 2.3.4 | Risco se Remover | Ação |
|---|------|---------|---------------|--------------|------------------|------|
| 1 | **whatsappNumber mutex** | `chat.controller.ts` | 21-50 | ❌ Ausente | Race condition em chamadas simultâneas | ✅ **Reaplicar** SimpleMutex |
| 2 | **Cache TTL + validação** | `cache.service.ts` | 34-76 | ❌ Ausente | cache.delete com vCard quebra; TTL infinito vaza memória | ✅ **Reaplicar** defaults |
| 3 | **S3 policy tolerante** | `minio.server.ts` | 35-62 | ❌ Ausente | Deploy em MinIO retorna NotImplemented e aborta | ✅ **Reaplicar** try/catch |
| 4 | **Upload mídia key.id** | `whatsapp.baileys.service.ts` | 1299-1329 | ⚠️ Diferente | Arquivos duplicados sem extensão | ✅ **Reaplicar** rename |
| 5 | **Guard key.id updates** | `whatsapp.baileys.service.ts` | 1438-1446 | ❌ Ausente | Updates sem id quebram webhook | ✅ **Reaplicar** guard |
| 6 | **Fallback status** | `whatsapp.baileys.service.ts` | 1529-1536 | ❌ Ausente | Consumer espera string, não undefined | ✅ **Reaplicar** fallback |
| 7 | **getBase64 resiliente** | `whatsapp.baileys.service.ts` | 3647-3768 | ⚠️ Parcial | Mídia expirada falha download | ✅ **Reaplicar** reupload |
| 8 | **addLabel defensivo** | `whatsapp.baileys.service.ts` | 4496-4526 | ⚠️ Diferente | Chats fantasmas | ✅ **Reaplicar** UPDATE |
| 9 | **createContact ID direto** | `chatwoot.service.ts` | 289-371 | ⚠️ Round-trip | Contact sem label (race) | ✅ **Reaplicar** extração |
| 10 | **Guard participant** | `chatwoot.service.ts` | 2209-2227 | ❌ Ausente | Erro em broadcast sem participant | ✅ **Reaplicar** guard |
| 11 | **Normalização BR** | `chatwoot-import-helper.ts` | 405-520 | ❌ Ausente | Contatos duplicados, perda histórico | ✅ **CRÍTICO - Reaplicar** |
| 12 | **sliceIntoChunks fix** | `chatwoot-import-helper.ts` | 722-727 | 🐛 **BUG** | Perda de itens após 1º chunk | ✅ **CRÍTICO - Corrigir** |
| 13 | **Refresh conversas** | `chatwoot-import-helper.ts` | 746-770 | ❌ Ausente | Conversa não reabre na UI | ✅ **Reaplicar** refresh |
| 14 | **Logs import detalhados** | `chatwoot-import-helper.ts` | 199-418 | ⚠️ Parcial | Troubleshooting cego | 💡 Opcional |
| 15 | **Source maps** | `package.json`, `tsconfig.json` | - | ❌ Ausente | Stack trace ofuscado | ✅ **Reaplicar** |
| 16 | **BuildImage.ps1** | `BuildImage.ps1` | - | ❌ Ausente | Pipeline Windows/Podman | ✅ Se usar Podman |

**Total:** 16 customizações críticas + várias opcionais

---

## 1. Tratamento de @lid

### ✅ **JÁ INCORPORADO NA 2.3.4**

A versão oficial agora possui tratamento completo de @lid:

```typescript
// chatwoot.service.ts:2.3.4 (linha ~608)
const isLid = body.key.previousRemoteJid?.includes('@lid') && body.key.senderPn;
const remoteJid = body.key.remoteJid;

// Processa atualização de contatos já criados @lid
if (isLid && body.key.senderPn !== body.key.previousRemoteJid) {
  const contact = await this.findContact(instance, body.key.remoteJid.split('@')[0]);
  if (contact && contact.identifier !== body.key.senderPn) {
    this.logger.verbose(
      `Identifier needs update: (contact.identifier: ${contact.identifier},
       body.key.remoteJid: ${body.key.remoteJid},
       body.key.senderPn: ${body.key.senderPn}`
    );
    const updateContact = await this.updateContact(instance, contact.id, {
      identifier: body.key.senderPn,
      phone_number: `+${body.key.senderPn.split('@')[0]}`,
    });
  }
}
```

**Conclusão:** As correções de @lid que você fez foram incorporadas e melhoradas na versão oficial.

---

## 1.1. Novidades Importantes da 2.3.4

### 🎉 Novos Recursos

#### 1. **Integração Kafka**
- **Envs novos:** `KAFKA_*` (KAFKA_ENABLED, KAFKA_BROKER, etc.)
- **Funcionalidade:** Event streaming em tempo real para sistemas externos
- **Ação recomendada:** Desabilitar com `KAFKA_ENABLED=false` se não usar imediatamente
- **Impacto:** Zero se desabilitado; requer Kafka broker se habilitado

```bash
# Desabilitar Kafka (recomendado se não usar)
KAFKA_ENABLED=false
```

#### 2. **Endpoint /metrics (Prometheus)**
- **Env:** `PROMETHEUS_METRICS` (true/false)
- **Funcionalidade:** Métricas para Grafana/Prometheus
- **Endpoint:** `GET /metrics`
- **Ação recomendada:** Controlar acesso para evitar exposição indevida
- **Impacto:** Exposição de métricas internas (CPU, memória, requests, etc.)

```bash
# Desabilitar métricas ou proteger endpoint
PROMETHEUS_METRICS=false
# OU configurar auth no nginx/reverse proxy
```

#### 3. **Evolution Manager v2**
- **Localização:** Submódulo `evolution-manager-v2/`
- **Tipo:** Interface web moderna (React + TypeScript)
- **Ação recomendada:** Ajustar pipelines de CI/CD para clonar com `--recurse-submodules`
- **Impacto:** Build pode falhar se não clonar submódulos

```bash
# Clone com submódulos
git clone --recurse-submodules https://github.com/EvolutionAPI/evolution-api.git

# Ou atualizar submódulos existentes
git submodule update --init --recursive
```

#### 4. **Node.js 24**
- **Dockerfile oficial:** Agora usa Node 24
- **Sua versão custom:** Provavelmente Node 20
- **Ação recomendada:**
  - **Opção A:** Atualizar para Node 24 (testar bem!)
  - **Opção B:** Manter Dockerfile custom com Node 20
- **Impacto:** Possível incompatibilidade de dependências

```dockerfile
# Se manter Node 20 (sua versão)
FROM node:20-alpine
# VS oficial
FROM node:24-alpine
```

### 🔒 Correções de Segurança

#### Security Fix: Path Traversal (2.3.3)
- **CVE:** Path Traversal no endpoint `/assets`
- **Gravidade:** 🔴 **CRÍTICA**
- **Detalhes:** Permitia leitura não autenticada de arquivos locais
- **Status:** Corrigido na 2.3.3 (incluído na 2.3.4)
- **Ação:** Garantir que rota `/assets` está protegida após merge

### 📦 Atualizações de Dependências

| Dependência | Versão Antiga | Versão 2.3.4 | Impacto |
|-------------|---------------|--------------|---------|
| Baileys | ~6.7.x | 7.0.0-rc.4 | Breaking changes possíveis |
| Express | 4.x | 4.x | Sem impacto |
| Prisma | ~5.x | ~5.x | Migrations novas |

**⚠️ Atenção:** Baileys v7.0.0-rc.4 pode ter mudanças na API interna. Testar bem!

### 🆕 Variáveis de Ambiente Adicionadas

```bash
# Kafka
KAFKA_ENABLED=false
KAFKA_BROKER=localhost:9092
KAFKA_CLIENT_ID=evolution-api
KAFKA_CONSUMER_GROUP_ID=evolution-group

# Prometheus
PROMETHEUS_METRICS=false

# Evolution Manager v2
# (váriaveis específicas - ver documentação oficial)
```

**Ação recomendada:** Adicionar essas envs nos seus ambientes (staging/produção) com valores padrão seguros (tudo desabilitado inicialmente).

---

## 2. Chatwoot Import Helper - Análise Detalhada

### 2.1. selectOrCreateFksFromChatwoot

#### ❌ **SUA VERSÃO (custom-2.2.3) - MAIS ROBUSTA**

**Características:**
- **Normalização de números brasileiros**: Trata números com/sem dígito 9
- **Busca por identifier e phone_number**: Maior flexibilidade
- **JID alternativo**: Procura por `jidWith` e `jidWithout`
- **Queries individuais**: Mais lento, mas mais detalhado
- **Logs verbosos**: Rastreabilidade completa

```typescript
// Sua implementação (custom-2.2.3)
private normalizeBrazilianPhoneNumberOptions(raw: string): [string, string] {
  if (!raw.startsWith('+55')) {
    return [raw, raw];
  }
  const digits = raw.slice(3);
  if (digits.length === 10) {
    // Old: +5521999999999 -> [+5521999999999, +552199999999]
    const newDigits = digits.slice(0, 2) + '9' + digits.slice(2);
    return [raw, `+55${newDigits}`];
  } else if (digits.length === 11) {
    // New: +552199999999 -> [+5521999999999, +552199999999]
    const oldDigits = digits.slice(0, 2) + digits.slice(3);
    return [`+55${oldDigits}`, raw];
  }
  return [raw, raw];
}

// Busca por identifier E phone_number
const selectContact = `
  SELECT id, phone_number
    FROM contacts
   WHERE account_id = $1
     AND (
       phone_number = $2
       OR phone_number = $3
       OR identifier   = $4  -- Busca por JID também
       OR identifier   = $5
     )
   LIMIT 1
`;
```

#### ⚠️ **VERSÃO 2.3.4 - MAIS SIMPLES**

**Características:**
- **Uma única query CTE**: Mais eficiente
- **Sem normalização brasileira**: Assume phone_number padrão
- **Sem identifier alternativo**: Só usa phone_number na busca

```typescript
// Versão 2.3.4 (linha ~343-433)
public async selectOrCreateFksFromChatwoot(...) {
  // Uma única query complexa com CTE
  const sqlFromChatwoot = `WITH
    phone_number AS (
      SELECT phone_number, created_at::INTEGER, last_activity_at::INTEGER
      FROM ( VALUES ${phoneNumberBind} ) as t (...)
    ),
    only_new_phone_number AS (
      SELECT * FROM phone_number
      WHERE phone_number NOT IN (
        SELECT phone_number FROM contacts
        JOIN contact_inboxes ci ON ci.contact_id = contacts.id ...
      )
    ),
    new_contact AS (
      INSERT INTO contacts (name, phone_number, account_id, identifier, ...)
      SELECT REPLACE(p.phone_number, '+', ''), p.phone_number, $1,
             CONCAT(REPLACE(p.phone_number, '+', ''), '@s.whatsapp.net'), ...
      FROM only_new_phone_number AS p
      ...
    )
    ...
  `;
}
```

**Impacto:**
- ❌ **PERDA**: Normalização de números brasileiros (9º dígito)
- ❌ **PERDA**: Busca por identifier alternativo (pode falhar com @lid histórico)
- ✅ **GANHO**: Performance melhorada (menos queries ao banco)

---

### 2.2. importHistoryMessages

#### ❌ **SUA VERSÃO (custom-2.2.3) - MAIS DETALHADA**

**Características:**
- **Logs detalhados**: Rastreamento completo de cada batch
- **Refresh de conversações**: Atualiza UI do Chatwoot após import
- **Touch de conversações**: Mantém track de conversas tocadas

```typescript
// Sua versão (custom-2.2.3, linha ~195-403)
const touchedConversations = new Set<string>();

for (const { conversation_id } of fksByNumber.values()) {
  touchedConversations.add(conversation_id);
}

// Após inserir mensagens
for (const convId of touchedConversations) {
  await this.safeRefreshConversation(
    provider.url,
    provider.accountId,
    convId,
    provider.token
  );
}

private async safeRefreshConversation(
  providerUrl: string,
  accountId: string,
  conversationId: string,
  apiToken: string
): Promise<void> {
  // Faz POST para /api/v1/accounts/{accountId}/conversations/{displayId}/refresh
  const url = `${providerUrl}/api/v1/accounts/${accountId}/conversations/${displayId}/refresh`;
  await axios.post(url, null, {
    params: { api_access_token: apiToken },
  });
}
```

#### ⚠️ **VERSÃO 2.3.4 - MAIS SIMPLES**

**Características:**
- **Sem logs detalhados**
- **Sem refresh de conversações**: Não atualiza UI automaticamente
- **Mais rápida**: Menos overhead

**Impacto:**
- ❌ **PERDA**: Logs de debug para troubleshooting
- ❌ **PERDA**: Refresh automático das conversas (UI pode não atualizar)
- ✅ **GANHO**: Import mais rápido

---

### 2.3. sliceIntoChunks

#### 🐛 **VERSÃO 2.3.4 TEM BUG**

```typescript
// Versão 2.3.4 (linha ~551)
public sliceIntoChunks(arr: any[], chunkSize: number) {
  return arr.splice(0, chunkSize);  // ❌ BUG: splice MODIFICA o array original
}
```

```typescript
// Sua versão (custom-2.2.3, linha ~722)
public sliceIntoChunks<T>(arr: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += chunkSize) {
    chunks.push(arr.slice(i, i + chunkSize));  // ✅ CORRETO: slice não modifica
  }
  return chunks;
}
```

**Impacto:**
- 🐛 **BUG NA 2.3.4**: O uso de `splice` causa comportamento incorreto em loops
- ✅ **SUA VERSÃO ESTÁ CORRETA**: Deve ser preservada ou reportada como bug

---

### 2.4. getExistingSourceIds

#### ✅ **2.3.4 MELHOROU**

**Versão 2.3.4:**
```typescript
public async getExistingSourceIds(
  sourceIds: string[],
  conversationId?: number  // ✅ Novo parâmetro opcional
): Promise<Set<string>> {
  const query = conversationId
    ? 'SELECT source_id FROM messages WHERE source_id = ANY($1) AND conversation_id = $2'
    : 'SELECT source_id FROM messages WHERE source_id = ANY($1)';

  const params = conversationId ? [formattedSourceIds, conversationId] : [formattedSourceIds];
  const result = await pgClient.query(query, params);
  // ...
}
```

**Impacto:**
- ✅ **MELHORIA**: Pode filtrar por conversação específica
- ✅ **MANTER**: Adotar versão oficial

---

## 3. Outras Customizações

### 3.1. SimpleMutex no whatsappNumber

**Arquivo:** `chat.controller.ts`

```typescript
// Sua customização (custom-2.2.3)
class SimpleMutex {
  private locked = false;
  private waiting: Array<() => void> = [];
  // ... implementação de mutex
}

private static whatsappNumberMutex = new SimpleMutex();

public async whatsappNumber({ instanceName }: InstanceDto, data: WhatsAppNumberDto) {
  return await ChatController.whatsappNumberMutex.runExclusive(async () => {
    return this.waMonitor.waInstances[instanceName].whatsappNumber(data);
  });
}
```

**Análise:**
- ❓ **AVALIAR**: Você implementou mutex para evitar race conditions
- ❓ **NECESSÁRIO?**: Depende se há problemas com chamadas concorrentes em produção
- ⚠️ **NÃO EXISTE NA 2.3.4**: Será perdido

---

### 3.2. Source Map Support

**Arquivo:** `package.json`

```json
{
  "dependencies": {
    "source-map-support": "^0.5.21"
  },
  "scripts": {
    "start:prod": "node --enable-source-maps -r source-map-support/register dist/main.js"
  }
}
```

**Análise:**
- ✅ **ÚTIL**: Melhora stack traces em produção
- ✅ **FÁCIL DE READICIONAR**: Apenas 2 linhas
- ⚠️ **NÃO EXISTE NA 2.3.4**: Será perdido

---

### 3.3. Alteração no addLabel

**Arquivo:** `whatsapp.baileys.service.ts`

```typescript
// Sua versão (custom-2.2.3)
private async addLabel(
  labelId: string,
  instanceId: string,
  chatId: string
): Promise<void> {
  try {
    await this.prismaRepository.$executeRawUnsafe(
      `UPDATE "Chat"
         SET "labels" = (...)
         WHERE "instanceId" = $2
           AND "remoteJid"  = $3;`,
      labelId,
      instanceId,
      chatId
    );
  } catch (err: unknown) {
    // Não deixa quebrar: registra e segue em frente
    console.warn(`Failed to add label ${labelId}: ${err.message}`);
  }
}
```

**Versão oficial usa INSERT ... ON CONFLICT:**
```typescript
await this.prismaRepository.$executeRawUnsafe(
  `INSERT INTO "Chat" ("id", "instanceId", "remoteJid", "labels", ...)
   VALUES ($4, $2, $3, to_jsonb(ARRAY[$1]::text[]), ...)
   ON CONFLICT ("instanceId", "remoteJid") DO UPDATE ...`,
  labelId, instanceId, chatId, id
);
```

**Análise:**
- ⚠️ **SUA VERSÃO**: Usa UPDATE direto (mais seguro se chat não existe)
- ⚠️ **VERSÃO OFICIAL**: Usa INSERT com ON CONFLICT (cria chat se não existe)
- ❓ **AVALIAR**: Qual comportamento é desejado?

---

### 3.4. BuildImage.ps1

**Arquivo:** `BuildImage.ps1`

```powershell
(Get-ECRLoginCommand).Password | podman login --username AWS ...
podman build -t evolution -f .\Dockerfile .
podman tag evolution:latest 130811782740.dkr.ecr.us-east-2.amazonaws.com/evolution
podman push 130811782740.dkr.ecr.us-east-2.amazonaws.com/evolution
```

**Análise:**
- ✅ **SEU SCRIPT**: Para automação de deploy
- ⚠️ **NÃO EXISTE NA 2.3.4**: Será perdido
- ✅ **FÁCIL DE PRESERVAR**: Está em arquivo separado

---

## 4. Mudanças Críticas na 2.3.4

### 🔴 Correção de Segurança (2.3.3)

```
CRITICAL: Fixed Path Traversal vulnerability in /assets endpoint
that allowed unauthenticated local file read
```

**⚠️ URGENTE**: Esta vulnerabilidade está presente na sua versão atual!

---

### ⭐ Novos Recursos

1. **Kafka Integration** (2.3.4)
   - Event streaming em tempo real
   - Suporte a SASL/SSL
   - Auto-criação de topics

2. **Prometheus Metrics** (2.3.3)
   - Endpoint `/metrics`
   - Compatível com Prometheus/Grafana

3. **Evolution Manager v2** (2.3.4)
   - Agora open source como submódulo
   - Interface moderna React + TypeScript

4. **Baileys v7.0.0-rc.4**
   - Melhorias no tratamento de mensagens
   - Correções de bugs

---

## 5. Recomendações de Migração

### ✅ Pode Abandonar com Segurança

1. **Tratamento de @lid**
   - ✅ Já incorporado e melhorado na 2.3.4

2. **Media Download com retry**
   - ✅ Já incorporado na 2.3.4

3. **Chatwoot createConversation caching**
   - ✅ Já incorporado na 2.3.4

4. **S3 SKIP_POLICY**
   - ✅ Já existe na 2.3.4

---

### ⚠️ Preservar ou Reavaliar

#### 1. **Normalização de Números Brasileiros** ⚠️ IMPORTANTE

**Situação:** Sua implementação trata números BR com/sem 9º dígito
**Na 2.3.4:** Não existe

**Recomendação:**
- ✅ **PRESERVAR** se você tem base histórica com números misturados
- ✅ **REPORTAR** como feature ao repositório oficial
- 💡 **ALTERNATIVA**: Normalizar números no banco antes da migração

**Implementação:**
```typescript
// Adicionar no selectOrCreateFksFromChatwoot da 2.3.4
private normalizeBrazilianPhoneNumberOptions(raw: string): [string, string] {
  if (!raw.startsWith('+55')) return [raw, raw];
  const digits = raw.slice(3);
  if (digits.length === 10) {
    const newDigits = digits.slice(0, 2) + '9' + digits.slice(2);
    return [raw, `+55${newDigits}`];
  } else if (digits.length === 11) {
    const oldDigits = digits.slice(0, 2) + digits.slice(3);
    return [`+55${oldDigits}`, raw];
  }
  return [raw, raw];
}
```

#### 2. **Refresh de Conversações no Import** ⚠️ IMPORTANTE

**Situação:** Você faz refresh da UI do Chatwoot após import
**Na 2.3.4:** Não existe

**Recomendação:**
- ✅ **PRESERVAR** se você precisa que a UI atualize automaticamente
- ⚠️ **AVALIAR**: Pode impactar performance em imports grandes

**Implementação:**
```typescript
// Readicionar no importHistoryMessages da 2.3.4
const touchedConversations = new Set<string>();

// Durante o loop de mensagens
for (const { conversation_id } of fksByNumber.values()) {
  touchedConversations.add(conversation_id);
}

// Após inserir todas as mensagens
for (const convId of touchedConversations) {
  await this.safeRefreshConversation(
    provider.url, provider.accountId, convId, provider.token
  );
}
```

#### 3. **SimpleMutex no whatsappNumber** ❓ AVALIAR

**Situação:** Você adicionou mutex para evitar race conditions
**Na 2.3.4:** Não existe

**Recomendação:**
- ❓ **AVALIAR**: Houve problemas com race conditions em produção?
- ✅ **SE SIM**: Readicionar o mutex
- ✅ **SE NÃO**: Pode abandonar

#### 4. **Logs Detalhados no Import** 💡 OPCIONAL

**Situação:** Você tem logs verbosos no import
**Na 2.3.4:** Logs básicos

**Recomendação:**
- 💡 **OPCIONAL**: Útil para troubleshooting
- ⚠️ **CUIDADO**: Pode gerar muito log em imports grandes

---

### ✅ Fácil de Readicionar

1. **source-map-support**
   ```json
   {
     "dependencies": {
       "source-map-support": "^0.5.21"
     },
     "scripts": {
       "start:prod": "node --enable-source-maps -r source-map-support/register dist/main.js"
     }
   }
   ```

2. **BuildImage.ps1**
   - Apenas copiar arquivo

---

### 🐛 Reportar como Bug

1. **sliceIntoChunks na 2.3.4**
   ```typescript
   // BUG na 2.3.4 (linha ~551)
   public sliceIntoChunks(arr: any[], chunkSize: number) {
     return arr.splice(0, chunkSize);  // ❌ splice modifica original
   }

   // CORRETO (sua versão)
   public sliceIntoChunks<T>(arr: T[], chunkSize: number): T[][] {
     const chunks: T[][] = [];
     for (let i = 0; i < arr.length; i += chunkSize) {
       chunks.push(arr.slice(i, i + chunkSize));
     }
     return chunks;
   }
   ```

---

## 6. Plano de Migração Sugerido

### Fase 1: Preparação

1. ✅ Backup completo do banco de dados
2. ✅ Backup da aplicação atual
3. ✅ Criar branch `upgrade-2.3.4`
4. ✅ Documentar customizações que serão preservadas

### Fase 2: Migração Base

1. ✅ Merge com tag `2.3.4` do repositório oficial
2. ✅ Resolver conflitos (se houver)
3. ✅ Atualizar dependências

### Fase 3: Replicar Customizações Críticas

#### 3.1. Normalização de Números Brasileiros

**Se você tem números misturados na base:**

```bash
# Adicionar no chatwoot-import-helper.ts
git show custom-2.2.3:src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts \
  | sed -n '406,430p' > /tmp/normalize-br.ts

# Integrar manualmente no selectOrCreateFksFromChatwoot
```

#### 3.2. Refresh de Conversações (Opcional)

```bash
# Adicionar safeRefreshConversation
git show custom-2.2.3:src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts \
  | sed -n '746,777p' > /tmp/refresh-conv.ts
```

#### 3.3. Source Map Support

```bash
npm install --save source-map-support
# Editar package.json scripts
```

#### 3.4. SimpleMutex (Se Necessário)

```bash
# Adicionar ao chat.controller.ts
git show custom-2.2.3:src/api/controllers/chat.controller.ts \
  | sed -n '21,48p' > /tmp/mutex.ts
```

#### 3.5. Corrigir Bug do sliceIntoChunks

```typescript
// Em chatwoot-import-helper.ts:551
public sliceIntoChunks<T>(arr: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += chunkSize) {
    chunks.push(arr.slice(i, i + chunkSize));
  }
  return chunks;
}
```

### Fase 4: Testes

1. ✅ Testes unitários
2. ✅ Teste de import de histórico (ambiente staging)
3. ✅ Teste de criação de contatos com @lid
4. ✅ Teste de números brasileiros (com/sem 9)
5. ✅ Teste de performance

### Fase 5: Deploy

1. ✅ Deploy em staging
2. ✅ Smoke tests
3. ✅ Deploy em produção (horário de baixo tráfego)
4. ✅ Monitoramento pós-deploy

---

## 7. Checklist de Migração

### Antes do Merge

- [ ] Backup do banco de dados
- [ ] Backup da aplicação atual
- [ ] Documentar settings atuais (envs, configs)
- [ ] Identificar dependências customizadas

### Durante o Merge

- [ ] Merge com `2.3.4` oficial
- [ ] Resolver conflitos
- [ ] Readicionar `source-map-support`
- [ ] Readicionar `BuildImage.ps1`
- [ ] Corrigir bug do `sliceIntoChunks`
- [ ] Avaliar necessidade de `SimpleMutex`
- [ ] Avaliar necessidade de normalização BR
- [ ] Avaliar necessidade de refresh de conversações

### Após o Merge

- [ ] `npm install` para atualizar dependências
- [ ] Executar migrations do Prisma
- [ ] Rodar testes
- [ ] Testar em ambiente staging
- [ ] Validar import de histórico
- [ ] Validar criação de contatos @lid
- [ ] Validar números brasileiros

### Deploy em Produção

- [ ] Deploy em horário de baixo tráfego
- [ ] Monitorar logs de erro
- [ ] Monitorar performance
- [ ] Validar webhooks
- [ ] Validar integração Chatwoot
- [ ] Rollback plan pronto

---

## 8. Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|-------|---------------|---------|-----------|
| Perda de números BR históricos | Alta | Alto | Preservar normalização BR |
| Conversas não atualizam no Chatwoot | Média | Médio | Preservar refresh de conversações |
| Race condition no whatsappNumber | Baixa | Médio | Monitorar e readicionar mutex se necessário |
| Bug do sliceIntoChunks | Alta | Alto | Corrigir antes do deploy |
| Incompatibilidade de dependências | Baixa | Alto | Testar extensivamente em staging |

---

## 9. Conclusão

### ✅ Vantagens da Migração

1. **Correção de segurança crítica** (Path Traversal)
2. **Tratamento de @lid oficial** (sua principal preocupação)
3. **Novos recursos** (Kafka, Prometheus, Manager v2)
4. **Baileys atualizado** (v7.0.0-rc.4)
5. **Suporte contínuo** da comunidade

### ⚠️ Atenção Especial Para

1. **Normalização de números brasileiros** - Avaliar necessidade
2. **Refresh de conversações** - Avaliar impacto na UX
3. **Bug do sliceIntoChunks** - Corrigir obrigatoriamente

### 🎯 Recomendação Final

**MIGRAR PARA 2.3.4** preservando:
- Normalização de números brasileiros (se necessário)
- Correção do bug sliceIntoChunks (obrigatório)
- source-map-support (recomendado)
- BuildImage.ps1 (seu script de deploy)

**AVALIAR NECESSIDADE:**
- SimpleMutex no whatsappNumber
- Refresh de conversações no import
- Logs detalhados

---

## 10. Observabilidade e Recuperação de Erros

### 🔍 Problema Identificado: Containers Zumbi

Durante a análise, identificamos que erros fatais (ex: `Connection Closed`, `WebSocket closed before connection`) deixam a API em estado **zumbi**:
- ✅ HTTP server responde (health check passa)
- ❌ WhatsApp desconectado (funcionalidade quebrada)
- 😴 Docker Swarm não detecta (container "healthy")

### 💀 Solução: Suicídio Controlado

**Documento completo:** `docs/error-recovery-strategy.md`

#### Resumo da Estratégia:

1. **Detectar erros fatais** baseado em padrões:
   - `Connection Closed`
   - `WebSocket was closed before the connection`
   - `ECONNREFUSED`, `ETIMEDOUT`, etc.

2. **Contador de erros:**
   - Incrementa a cada erro fatal
   - Após **3 erros consecutivos** → `process.exit(1)`
   - Reset automático após 1 minuto sem erros

3. **Graceful shutdown:**
   ```typescript
   // Logar detalhes completos
   logger.error('💀 FATAL ERROR - INITIATING CONTROLLED SUICIDE');

   // Enviar webhook de alerta (opcional)
   await sendErrorAlert(error, origin);

   // Aguardar logs serem escritos
   await sleep(500);

   // Matar processo (Docker Swarm recria)
   process.exit(1);
   ```

4. **Health check profundo** (opcional):
   - Endpoint `/health/deep`
   - Verifica se WhatsApp está **realmente** conectado
   - Retorna 503 se não houver instâncias conectadas

#### Implementação em 2 Fases:

**Fase 1** (Obrigatória): Substituir `src/config/error.config.ts`
- uncaughtException → SEMPRE causa exit
- unhandledRejection → exit se erro fatal (3x)
- ~30min de implementação

**Fase 2** (Recomendada): Health check profundo
- Controller + Router para `/health/deep`
- Atualizar docker-compose.yaml
- ~1h de implementação

#### Variável de Controle:

```bash
# Habilitar suicídio controlado
EXIT_ON_FATAL=true  # Recomendado em produção

# Desabilitar (apenas logs)
EXIT_ON_FATAL=false  # Útil para debug local
```

#### Vantagens:
- ✅ Containers sempre funcionais (ou mortos + recriando)
- ✅ Sem containers zumbi
- ✅ Auto-recuperação (5-10s downtime)
- ✅ Alertas via webhook
- ✅ Logs completos antes de morrer

**Para implementar:** Ver `docs/error-recovery-strategy.md` para código completo e instruções detalhadas.

---

## 11. Referências

- [Evolution API v2.3.4 Release](https://github.com/EvolutionAPI/evolution-api/releases/tag/2.3.4)
- [Evolution API v2.3.3 Release (Security Fix)](https://github.com/EvolutionAPI/evolution-api/releases/tag/2.3.3)
- Commit @lid: `630f5c56` - fix: Trocar @lids em remoteJid por senderPn
- Commit refresh conv: `f7862637` - fix(chatwoot): otimizar lógica de reabertura de conversas
- **Documentos relacionados:**
  - `docs/error-recovery-strategy.md` - Estratégia completa de suicídio controlado
  - `docs/evolution-upgrade-codex.md` - Análise técnica detalhada (Codex)
  - `docs/errors.txt` - Log de erros que motivaram a estratégia de recovery

---

## 12. Análise de Conflitos de Merge (CRÍTICO)

### 🔴 Arquivos com Modificações Conflitantes

Estes arquivos foram modificados **TANTO** na sua branch custom-2.2.3 **QUANTO** na versão oficial 2.3.4. São os que **darão problema no merge** e exigem resolução manual cuidadosa:

```bash
# 8 arquivos com conflitos:
1. Dockerfile
2. package.json
3. package-lock.json
4. src/api/controllers/chat.controller.ts
5. src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts
6. src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
7. src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts
8. src/api/integrations/storage/s3/libs/minio.server.ts
```

---

### 12.1. ⚠️ Arquivo: `package.json` (Conflito Fácil)

**Tipo de conflito:** Versão + Dependências

#### Suas mudanças (custom-2.2.3):
```json
{
  "version": "2.2.3.24",
  "scripts": {
    "start:prod": "node --enable-source-maps -r source-map-support/register dist/main.js"
  },
  "dependencies": {
    "source-map-support": "^0.5.21"
  }
}
```

#### Mudanças oficiais (2.3.4):
```json
{
  "version": "2.3.4",
  "scripts": {
    "start:prod": "node dist/main"
  },
  "dependencies": {
    // Não tem source-map-support
    // Várias dependências novas (Kafka, etc.)
  }
}
```

#### Resolução recomendada:
```bash
# Aceitar versão oficial E readicionar source-map-support
✅ Usar version: "2.3.4" (oficial)
✅ Aceitar todas as novas dependências oficiais
✅ Adicionar manualmente: "source-map-support": "^0.5.21"
✅ Modificar start:prod para incluir source-maps
```

**Comandos:**
```bash
git checkout --ours package.json  # Começa com a versão oficial
# Depois edite manualmente para adicionar source-map-support
```

**Dificuldade:** 🟡 Fácil - Conflito de texto simples

---

### 12.2. ⚠️ Arquivo: `package-lock.json` (Conflito Trabalhoso)

**Tipo de conflito:** Árvore de dependências

#### Problema:
- Sua versão: Lockfile baseado em npm do seu ambiente
- Versão oficial: Lockfile com novas dependências (Kafka, Prometheus, etc.)

#### Resolução recomendada:
```bash
# NÃO tente resolver conflitos manualmente!
✅ Aceitar versão oficial completamente
✅ Depois rodar: npm install
✅ Isso regerará o lockfile correto
```

**Comandos:**
```bash
git checkout --theirs package-lock.json  # Aceita versão oficial
npm install  # Regenera baseado no package.json resolvido
git add package-lock.json
```

**Dificuldade:** 🟢 Fácil - Deixe o npm resolver

---

### 12.3. 🔴 Arquivo: `chat.controller.ts` (Conflito Médio)

**Tipo de conflito:** Lógica de negócio (SimpleMutex)

#### Suas mudanças (linhas 21-48):
```typescript
// Você ADICIONOU:
class SimpleMutex {
  private locked = false;
  private waiting: Array<() => void> = [];
  // ... implementação completa
}

export class ChatController {
  private static whatsappNumberMutex = new SimpleMutex();

  public async whatsappNumber(...) {
    return await ChatController.whatsappNumberMutex.runExclusive(async () => {
      return this.waMonitor.waInstances[instanceName].whatsappNumber(data);
    });
  }
}
```

#### Mudanças oficiais (linha ~73):
```typescript
// Oficial ADICIONOU:
public async findChatByRemoteJid({ instanceName }: InstanceDto, remoteJid: string) {
  return await this.waMonitor.waInstances[instanceName].findChatByRemoteJid(remoteJid);
}
```

#### Resolução recomendada:
```bash
✅ Aceitar versão oficial (sem mutex)
✅ Aceitar novo método findChatByRemoteJid
❓ Readicionar SimpleMutex SOMENTE se necessário (avaliar)
```

**Estratégia de merge:**
```bash
# 1. Aceitar versão oficial como base
git checkout --theirs src/api/controllers/chat.controller.ts

# 2. SE você decidir manter o mutex (após avaliação):
# Adicione manualmente as linhas 21-48 da sua versão custom
# E modifique o método whatsappNumber para usar o mutex
```

**Dificuldade:** 🟡 Médio - Decisão de negócio necessária

**Critério de decisão:**
- ❓ Houve erros de race condition em produção no endpoint whatsappNumber?
- ✅ **SIM** → Readicionar mutex
- ✅ **NÃO** → Deixar sem mutex (mais simples)

---

### 12.4. 🔴 Arquivo: `whatsapp.baileys.service.ts` (Conflito Complexo)

**Tipo de conflito:** Arquivo gigante (>5000 linhas) com múltiplas alterações

#### Áreas de conflito:
1. **Download de mídia** (método `getBase64FromMediaMessage`)
2. **Tratamento de @lid** (múltiplos locais)
3. **Método `addLabel`** (sua versão usa UPDATE, oficial usa INSERT)
4. **Message updates** (verificações de key.id)

#### Suas principais mudanças:
```typescript
// 1. getBase64FromMediaMessage - Tratamento robusto de download
const downloadContext: DownloadMediaMessageContext = {
  logger: P({ level: 'error' }),
  reuploadRequest: async (message: WAMessage): Promise<WAMessage> => {
    const updatedMsg = await this.client.updateMediaMessage(message);
    return updatedMsg ? updatedMsg : message;
  },
};

// 2. addLabel - UPDATE direto com try/catch
private async addLabel(...) {
  try {
    await this.prismaRepository.$executeRawUnsafe(
      `UPDATE "Chat" SET "labels" = (...) WHERE ...`
    );
  } catch (err) {
    console.warn(`Failed to add label: ${err.message}`);
  }
}

// 3. Verificação de key.id
if (!key.id) {
  console.warn(`Mensagem sem key.id, pulando update`);
  continue;
}

// 4. Arquivo nomeado com key.id
const fileName = `${received.key.id}${ext}`;
```

#### Mudanças oficiais (2.3.4):
```typescript
// 1. getBase64FromMediaMessage - Versão melhorada (similar à sua!)
// 2. addLabel - INSERT com ON CONFLICT
// 3. Tratamento de @lid completo (previousRemoteJid, senderPn)
// 4. Baileys v7.0.0-rc.4
```

#### Resolução recomendada:
```bash
✅ Aceitar versão oficial 2.3.4 COMPLETAMENTE
⚠️ Avaliar se precisa readicionar:
   - Verificação de key.id (linha custom ~1423)
   - addLabel com try/catch (linha custom ~4493)
```

**Estratégia de merge:**
```bash
# Aceitar versão oficial como base (ela já incorporou suas correções!)
git checkout --theirs src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts

# Depois avaliar se precisa adicionar:
# 1. Try/catch no addLabel (opcional - mais seguro)
# 2. Warning de key.id (opcional - debug)
```

**Dificuldade:** 🔴 Complexo - Mas versão oficial já tem suas correções principais!

**Por que complexo mas OK:**
- ✅ Tratamento de @lid → Já incorporado
- ✅ Media download robusto → Já incorporado
- ⚠️ addLabel → Comportamento diferente (avaliar)
- ⚠️ key.id check → Seu fix não está na oficial

---

### 12.5. 🔴 Arquivo: `chatwoot.service.ts` (Conflito Muito Complexo)

**Tipo de conflito:** Arquivo grande com lógica crítica de integração

#### Áreas de conflito:
1. **createConversation** - Cache e locking
2. **findContact** - Busca de contatos
3. **createContact** - Criação de contatos com @lid
4. **Tratamento de @lid** (isLid, previousRemoteJid)

#### Suas principais mudanças:
```typescript
// 1. createConversation com pendingCreateConv Map
private pendingCreateConv = new Map<string, Promise<number>>();

public async createConversation(...) {
  if (this.pendingCreateConv.has(remoteJid)) {
    return this.pendingCreateConv.get(remoteJid)!;
  }
  // ... lógica com try/catch e recovery
}

// 2. createContact com logs verbosos
this.logger.verbose(`[ChatwootService][createContact] start instance=...`);
this.logger.verbose(`[ChatwootService][createContact] payload=...`);

// 3. findContact com logs verbosos
this.logger.verbose(`[ChatwootService][findContact] start for instance=...`);
```

#### Mudanças oficiais (2.3.4):
```typescript
// 1. createConversation - Implementação similar mas diferente
const isLid = body.key.previousRemoteJid?.includes('@lid') && body.key.senderPn;

// Processa atualização de contatos já criados @lid
if (isLid && body.key.senderPn !== body.key.previousRemoteJid) {
  const contact = await this.findContact(...);
  if (contact && contact.identifier !== body.key.senderPn) {
    await this.updateContact(...);
  }
}

// 2. Vários commits de refatoração (c132379b, f7862637, etc.)
```

#### Resolução recomendada:
```bash
✅ Aceitar versão oficial 2.3.4 COMPLETAMENTE
⚠️ Avaliar se precisa readicionar:
   - Logs verbosos em createContact/findContact (opcional - debug)
   - pendingCreateConv Map (provavelmente não - oficial já tem cache)
```

**Estratégia de merge:**
```bash
# Aceitar versão oficial (ela já tem tratamento de @lid!)
git checkout --theirs src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts

# Verificar se funcionou:
# - Tratamento de @lid ✓
# - Cache de conversas ✓
# - Logs (readicionar se precisar de debug)
```

**Dificuldade:** 🔴 Complexo - Mas oficial já tem suas correções!

---

### 12.6. 🔴 Arquivo: `chatwoot-import-helper.ts` (Conflito MUITO Complexo)

**Tipo de conflito:** Arquivo crítico com 2 implementações completamente diferentes

#### ⚠️ MAIOR PROBLEMA DE MERGE

Este é o arquivo **MAIS PROBLEMÁTICO** porque você tem uma implementação **SUBSTANCIALMENTE DIFERENTE** da oficial.

#### Suas mudanças (custom-2.2.3):

**1. Normalização de números brasileiros (linhas 406-430):**
```typescript
private normalizeBrazilianPhoneNumberOptions(raw: string): [string, string] {
  if (!raw.startsWith('+55')) return [raw, raw];
  const digits = raw.slice(3);
  if (digits.length === 10) {
    const newDigits = digits.slice(0, 2) + '9' + digits.slice(2);
    return [raw, `+55${newDigits}`];
  } else if (digits.length === 11) {
    const oldDigits = digits.slice(0, 2) + digits.slice(3);
    return [`+55${oldDigits}`, raw];
  }
  return [raw, raw];
}
```

**2. selectOrCreateFksFromChatwoot - Queries separadas (linhas 433-590):**
```typescript
// Para cada número:
// 1. Busca contact por phone_number OU identifier (4 opções)
const selectContact = `
  SELECT id, phone_number FROM contacts
  WHERE account_id = $1 AND (
    phone_number = $2 OR phone_number = $3 OR
    identifier = $4 OR identifier = $5
  ) LIMIT 1
`;

// 2. Se não achar, INSERT contact com identifier = JID
// 3. Busca contact_inbox
// 4. Se não achar, INSERT contact_inbox
// 5. Busca conversation
// 6. Se não achar, INSERT conversation
```

**3. Refresh de conversações (linhas 746-777):**
```typescript
private async safeRefreshConversation(...) {
  const url = `${providerUrl}/api/v1/accounts/${accountId}/conversations/${displayId}/refresh`;
  await axios.post(url, null, {
    params: { api_access_token: apiToken },
  });
}

// Usado no importHistoryMessages:
for (const convId of touchedConversations) {
  await this.safeRefreshConversation(...);
}
```

**4. sliceIntoChunks CORRETO (linha 722):**
```typescript
public sliceIntoChunks<T>(arr: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += chunkSize) {
    chunks.push(arr.slice(i, i + chunkSize));
  }
  return chunks;
}
```

**5. Logs verbosos detalhados**

#### Versão oficial (2.3.4):

**1. SEM normalização brasileira**

**2. selectOrCreateFksFromChatwoot - Uma única CTE complexa (linhas 343-433):**
```typescript
const sqlFromChatwoot = `WITH
  phone_number AS (...),
  only_new_phone_number AS (...),
  new_contact AS (
    INSERT INTO contacts (...)
    SELECT ... FROM only_new_phone_number
    ON CONFLICT(identifier, account_id) DO UPDATE ...
  ),
  new_contact_inbox AS (
    INSERT INTO contact_inboxes (...)
    SELECT ... FROM new_contact
  ),
  new_conversation AS (
    INSERT INTO conversations (...)
    SELECT ... FROM new_contact_inbox
  )
  SELECT ... FROM new_conversation
  UNION
  SELECT ... FROM existing contacts
`;
```

**3. SEM refresh de conversações**

**4. sliceIntoChunks COM BUG (linha 551):**
```typescript
public sliceIntoChunks(arr: any[], chunkSize: number) {
  return arr.splice(0, chunkSize);  // ❌ BUG!
}
```

**5. Logs básicos**

#### Resolução recomendada (ESTRATÉGIA HÍBRIDA):

```bash
# OPÇÃO A: Base oficial + adicionar features customizadas
✅ Aceitar versão oficial como base
✅ ADICIONAR: normalizeBrazilianPhoneNumberOptions
✅ MODIFICAR: selectOrCreateFksFromChatwoot para usar normalização
✅ CORRIGIR: sliceIntoChunks (bug crítico!)
❓ AVALIAR: adicionar safeRefreshConversation
❓ AVALIAR: adicionar logs verbosos

# OPÇÃO B: Base custom + aceitar melhorias oficiais
⚠️ Manter sua versão custom
✅ Aceitar melhorias do getExistingSourceIds (conversationId param)
✅ Melhorar documentação
```

**Estratégia recomendada (OPÇÃO A - HÍBRIDA):**

```bash
# 1. Aceitar versão oficial como base
git checkout --theirs src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts

# 2. Aplicar patch com suas correções críticas
# Crie um arquivo patch-import-helper.diff com:
# - normalizeBrazilianPhoneNumberOptions
# - Correção do sliceIntoChunks
# - safeRefreshConversation (opcional)

git apply patch-import-helper.diff

# 3. Modificar selectOrCreateFksFromChatwoot para usar normalização BR
# (Isso requer modificação manual da CTE complexa)
```

**Dificuldade:** 🔴🔴 MUITO Complexo - Requer atenção máxima!

#### Impacto se usar versão oficial pura:
- ❌ **PERDA**: Números brasileiros com/sem 9º dígito não funcionarão
- ❌ **PERDA**: Busca por identifier alternativo
- ❌ **PERDA**: Refresh automático da UI do Chatwoot
- ❌ **PERDA**: Logs detalhados de debug
- 🐛 **BUG**: sliceIntoChunks quebrado

#### Impacto se usar versão custom pura:
- ❌ **PERDA**: Melhoria do getExistingSourceIds (filter por conversation)
- ❌ **PERDA**: Otimizações de performance da CTE

---

### 12.7. ⚠️ Arquivo: `minio.server.ts` (Conflito Pequeno)

**Tipo de conflito:** Mudança simples

#### Suas mudanças:
```typescript
// Nenhuma mudança significativa (apenas versão do código base)
```

#### Mudanças oficiais:
```typescript
// Suporte a SKIP_POLICY já existe
```

#### Resolução:
```bash
✅ Aceitar versão oficial completamente
git checkout --theirs src/api/integrations/storage/s3/libs/minio.server.ts
```

**Dificuldade:** 🟢 Fácil - Sem conflitos reais

---

### 12.8. ⚠️ Arquivo: `Dockerfile` (Conflito Trivial)

**Tipo de conflito:** Número de versão no LABEL

#### Suas mudanças:
```dockerfile
LABEL version="2.2.3.24" description="..."
```

#### Mudanças oficiais:
```dockerfile
LABEL version="2.3.4" description="..."
# Também: Node.js version upgrade
```

#### Resolução:
```bash
✅ Aceitar versão oficial completamente
git checkout --theirs Dockerfile
```

**Dificuldade:** 🟢 Trivial

---

## 12.9. Tabela Resumo de Conflitos

| Arquivo | Dificuldade | Estratégia | Tempo Estimado | Risco |
|---------|-------------|------------|----------------|-------|
| `Dockerfile` | 🟢 Trivial | Aceitar oficial | 1 min | Baixo |
| `package.json` | 🟡 Fácil | Híbrido (oficial + source-map) | 5 min | Baixo |
| `package-lock.json` | 🟢 Fácil | Aceitar oficial + npm install | 5 min | Baixo |
| `minio.server.ts` | 🟢 Fácil | Aceitar oficial | 1 min | Baixo |
| `chat.controller.ts` | 🟡 Médio | Aceitar oficial (avaliar mutex) | 15 min | Médio |
| `whatsapp.baileys.service.ts` | 🔴 Complexo | Aceitar oficial (+ patches opcionais) | 30 min | Médio |
| `chatwoot.service.ts` | 🔴 Complexo | Aceitar oficial (+ logs opcionais) | 30 min | Médio |
| `chatwoot-import-helper.ts` | 🔴🔴 MUITO Complexo | Híbrido (requer trabalho manual) | 2-4 horas | **ALTO** |

**Tempo total estimado:** 3-5 horas de trabalho cuidadoso

---

## 12.10. Estratégia de Merge Recomendada

### Fase 1: Preparação (15 min)

```bash
# 1. Criar branch de trabalho
git checkout -b merge-2.3.4-attempt-1

# 2. Fazer backup dos arquivos customizados críticos
mkdir -p ../backup-custom-2.2.3
git show custom-2.2.3:src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts \
  > ../backup-custom-2.2.3/chatwoot-import-helper.ts
git show custom-2.2.3:src/api/controllers/chat.controller.ts \
  > ../backup-custom-2.2.3/chat.controller.ts

# 3. Ter repositório oficial como upstream
git remote add upstream https://github.com/EvolutionAPI/evolution-api.git
git fetch upstream --tags
```

### Fase 2: Merge com Resolução Automática dos Fáceis (30 min)

```bash
# 1. Tentar merge
git merge 2.3.4

# 2. Resolver conflitos FÁCEIS primeiro (aceitar versão oficial):
git checkout --theirs Dockerfile
git checkout --theirs package-lock.json
git checkout --theirs src/api/integrations/storage/s3/libs/minio.server.ts

# 3. Adicionar ao stage
git add Dockerfile package-lock.json src/api/integrations/storage/s3/libs/minio.server.ts
```

### Fase 3: Resolver package.json (5 min)

```bash
# 1. Aceitar versão oficial como base
git checkout --theirs package.json

# 2. Editar manualmente para adicionar source-map-support
# Adicionar na seção dependencies:
#   "source-map-support": "^0.5.21"
# Modificar scripts.start:prod:
#   "start:prod": "node --enable-source-maps -r source-map-support/register dist/main.js"

# 3. Instalar dependências
npm install

# 4. Adicionar ao stage
git add package.json package-lock.json
```

### Fase 4: Resolver Arquivos Médios (1 hora)

#### 4.1. chat.controller.ts

```bash
# Aceitar versão oficial (sem mutex por enquanto)
git checkout --theirs src/api/controllers/chat.controller.ts

# SE decidir adicionar mutex depois:
# 1. Copiar implementação SimpleMutex do backup
# 2. Adicionar na classe ChatController
# 3. Modificar método whatsappNumber

git add src/api/controllers/chat.controller.ts
```

#### 4.2. whatsapp.baileys.service.ts

```bash
# Aceitar versão oficial (ela já tem suas correções principais!)
git checkout --theirs src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts

# Opcionalmente adicionar:
# - Try/catch no addLabel
# - Warning de key.id

git add src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts
```

#### 4.3. chatwoot.service.ts

```bash
# Aceitar versão oficial (ela já tem tratamento de @lid!)
git checkout --theirs src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts

# Opcionalmente adicionar logs verbosos se precisar de debug

git add src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
```

### Fase 5: Resolver chatwoot-import-helper.ts (2-4 horas) ⚠️ CRÍTICO

```bash
# OPÇÃO RECOMENDADA: Base oficial + patches customizados

# 1. Aceitar versão oficial como base
git checkout --theirs src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts

# 2. Abrir arquivo no editor
code src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts

# 3. Aplicar correções OBRIGATÓRIAS:

# 3.1. Corrigir sliceIntoChunks (linha ~551)
# SUBSTITUIR:
#   public sliceIntoChunks(arr: any[], chunkSize: number) {
#     return arr.splice(0, chunkSize);
#   }
# POR:
#   public sliceIntoChunks<T>(arr: T[], chunkSize: number): T[][] {
#     const chunks: T[][] = [];
#     for (let i = 0; i < arr.length; i += chunkSize) {
#       chunks.push(arr.slice(i, i + chunkSize));
#     }
#     return chunks;
#   }

# 4. Aplicar correções IMPORTANTES (se tiver números BR históricos):

# 4.1. Adicionar método normalizeBrazilianPhoneNumberOptions
# (Copiar do ../backup-custom-2.2.3/chatwoot-import-helper.ts linhas 406-430)

# 4.2. Modificar selectOrCreateFksFromChatwoot
# Isso é COMPLEXO porque a versão oficial usa CTE
# Você precisa decidir:
# - OPÇÃO A: Manter CTE oficial (mais rápida, mas perde normalização BR)
# - OPÇÃO B: Voltar para queries separadas (sua versão custom)
# - OPÇÃO C: Modificar CTE para incluir normalização (MUITO complexo)

# 5. Aplicar correções OPCIONAIS:

# 5.1. Adicionar safeRefreshConversation
# (Copiar do ../backup-custom-2.2.3/chatwoot-import-helper.ts linhas 746-777)

# 5.2. Adicionar touchedConversations no importHistoryMessages
# (Modificar método para trackear e refresh conversas)

# 5.3. Adicionar logs verbosos
# (Modificar importHistoryMessages com logs detalhados)

# 6. Testar compilação
npm run build

# 7. Adicionar ao stage
git add src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts
```

### Fase 6: Adicionar Arquivos Custom (5 min)

```bash
# Readicionar BuildImage.ps1 (se perdeu no merge)
git checkout custom-2.2.3 -- BuildImage.ps1
git add BuildImage.ps1
```

### Fase 7: Commit e Teste (30 min)

```bash
# 1. Verificar status
git status

# 2. Commit
git commit -m "chore: merge Evolution API 2.3.4 with custom patches

- Merged official 2.3.4 release
- Preserved source-map-support
- Fixed sliceIntoChunks bug
- Preserved Brazilian phone normalization (if applicable)
- Preserved BuildImage.ps1 deployment script

BREAKING CHANGES:
- Upgraded to Baileys v7.0.0-rc.4
- Added Kafka integration support
- Added Prometheus metrics endpoint
- Security fix: Path Traversal in /assets endpoint

Custom patches applied:
- source-map-support for better error stacks
- sliceIntoChunks bug fix
- [if kept] Brazilian phone number normalization
- [if kept] SimpleMutex in whatsappNumber
- [if kept] Chatwoot conversation refresh"

# 3. Build
npm run build

# 4. Se houver erros TypeScript, corrigir e commit --amend

# 5. Testar localmente
npm run start
```

---

## 12.11. Casos Especiais e Decisões Críticas

### 🤔 Decisão 1: Normalização de Números Brasileiros

**Pergunta:** Você tem contatos históricos no Chatwoot com números BR no formato antigo (sem 9º dígito)?

**SE SIM:**
```bash
# Você DEVE preservar normalizeBrazilianPhoneNumberOptions
# Caso contrário, perderá sincronização com contatos históricos
```

**SE NÃO:**
```bash
# Pode usar versão oficial pura do chatwoot-import-helper.ts
# Apenas corrija o bug do sliceIntoChunks
```

**Como verificar:**
```sql
-- No banco do Chatwoot:
SELECT COUNT(*) FROM contacts
WHERE phone_number LIKE '+55%'
  AND LENGTH(REPLACE(phone_number, '+55', '')) = 10;

-- Se retornar > 0, você TEM números antigos!
```

### 🤔 Decisão 2: SimpleMutex no whatsappNumber

**Pergunta:** Você teve problemas de race condition neste endpoint em produção?

**SE SIM:**
```bash
# Preservar SimpleMutex no chat.controller.ts
```

**SE NÃO:**
```bash
# Usar versão oficial (mais simples)
# Monitorar logs após deploy
```

### 🤔 Decisão 3: Refresh de Conversações no Import

**Pergunta:** É crítico que a UI do Chatwoot atualize imediatamente após import?

**SE SIM:**
```bash
# Adicionar safeRefreshConversation
# Adicionar touchedConversations no import
```

**SE NÃO:**
```bash
# Usar versão oficial (mais rápida)
# Usuários podem dar F5 manual
```

---

## 12.12. Checklist de Resolução de Conflitos

### Antes do Merge
- [ ] Backup do repositório atual
- [ ] Backup dos arquivos customizados críticos
- [ ] Criar branch de trabalho
- [ ] Decisão tomada sobre normalização BR
- [ ] Decisão tomada sobre SimpleMutex
- [ ] Decisão tomada sobre refresh de conversações

### Durante o Merge
- [ ] Dockerfile → Aceitar oficial
- [ ] package.json → Híbrido (oficial + source-map)
- [ ] package-lock.json → Aceitar oficial + npm install
- [ ] minio.server.ts → Aceitar oficial
- [ ] chat.controller.ts → Aceitar oficial (+ mutex opcional)
- [ ] whatsapp.baileys.service.ts → Aceitar oficial
- [ ] chatwoot.service.ts → Aceitar oficial
- [ ] chatwoot-import-helper.ts → Híbrido (+ correções obrigatórias)
- [ ] BuildImage.ps1 → Preservar

### Correções Obrigatórias
- [ ] sliceIntoChunks corrigido
- [ ] npm install executado
- [ ] Compilação sem erros TypeScript

### Correções Condicionais
- [ ] normalizeBrazilianPhoneNumberOptions (se tiver números BR históricos)
- [ ] SimpleMutex (se houver race conditions)
- [ ] safeRefreshConversation (se precisar refresh automático)

### Teste
- [ ] npm run build
- [ ] npm run start
- [ ] Testar criação de instância
- [ ] Testar envio de mensagem
- [ ] Testar integração Chatwoot
- [ ] Testar import de histórico (staging)

---

## 12.13. Plano B: Se o Merge Falhar Muito

Se você tentar o merge e ficar muito complicado:

```bash
# Voltar atrás
git merge --abort
git checkout main

# ALTERNATIVA: Começar do zero com 2.3.4 oficial
git checkout -b fresh-2.3.4-with-patches
git reset --hard 2.3.4

# Aplicar APENAS as customizações essenciais:
# 1. source-map-support (package.json)
# 2. sliceIntoChunks fix (chatwoot-import-helper.ts)
# 3. BuildImage.ps1
# 4. [Opcional] normalizeBrazilianPhoneNumberOptions

# Testar extensivamente
# Deploy quando estável
```

---

## 12.14. Resumo Final de Conflitos

### ✅ Conflitos Fáceis (30 min):
- Dockerfile
- package.json
- package-lock.json
- minio.server.ts

### ⚠️ Conflitos Médios (1 hora):
- chat.controller.ts
- whatsapp.baileys.service.ts
- chatwoot.service.ts

### 🔴 Conflito Crítico (2-4 horas):
- **chatwoot-import-helper.ts** ← MAIOR DESAFIO

**Tempo total:** 3.5 - 5.5 horas de trabalho concentrado

**Recomendação:** Reserve um dia inteiro para fazer o merge com calma e testar extensivamente em staging antes de produção.
