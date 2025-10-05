# Configuração da Migração Evolution API
## custom-2.2.3 → 2.3.4

**Data:** 2025-10-03
**Perfil:** Produção com base histórica brasileira

---

## ✅ DECISÕES CONFIRMADAS

Baseado na sua resposta, **TODAS as 4 customizações críticas serão aplicadas:**

### 1. ✅ Normalização de Números Brasileiros
**Motivo:** Base tem muito telefone legado (com/sem 9º dígito)
**Impacto:** **CRÍTICO** - Sem isso, contatos duplicam e histórico se perde
**Ação:** Aplicar `normalizeBrazilianPhoneNumberOptions` + modificar `selectOrCreateFksFromChatwoot`

### 2. ✅ SimpleMutex no whatsappNumber
**Motivo:** Houve problemas de race condition
**Impacto:** **ALTO** - Race conditions em chamadas simultâneas
**Ação:** Aplicar classe `SimpleMutex` em `chat.controller.ts`

### 3. ✅ S3 Policy Tolerante (MinIO)
**Motivo:** Usa MinIO em vez de AWS S3
**Impacto:** **MÉDIO** - Deploy aborta com erro `NotImplemented`
**Ação:** Aplicar try/catch em `minio.server.ts`

### 4. ✅ BuildImage.ps1
**Motivo:** Pipeline Windows/Podman
**Impacto:** **BAIXO** - Apenas automação de deploy
**Ação:** Restaurar arquivo `BuildImage.ps1`

---

## 📋 CUSTOMIZAÇÕES OBRIGATÓRIAS PARA SEU CASO

Total: **20 customizações** (16 críticas + 4 recomendadas)

### Críticas (OBRIGATÓRIO aplicar)

| # | Customização | Arquivo | Motivo |
|---|--------------|---------|--------|
| 1 | SimpleMutex | `chat.controller.ts` | Race condition confirmada |
| 2 | Cache TTL defaults | `cache.service.ts` | Prevenir vazamento de memória |
| 3 | S3 policy tolerante | `minio.server.ts` | MinIO (confirmado) |
| 4 | Upload mídia key.id | `whatsapp.baileys.service.ts` | Evitar duplicação de arquivos |
| 5 | Guard key.id updates | `whatsapp.baileys.service.ts` | Prevenir webhook quebrado |
| 6 | Fallback status | `whatsapp.baileys.service.ts` | Consumer espera string |
| 7 | getBase64 resiliente | `whatsapp.baileys.service.ts` | Mídia expirada |
| 8 | addLabel defensivo | `whatsapp.baileys.service.ts` | Evitar chats fantasmas |
| 9 | createContact ID direto | `chatwoot.service.ts` | Race condition de label |
| 10 | Guard participant | `chatwoot.service.ts` | Broadcast sem participant |
| 11 | **Normalização BR** | `chatwoot-import-helper.ts` | **Base legada (CRÍTICO)** |
| 12 | **sliceIntoChunks fix** | `chatwoot-import-helper.ts` | **Bug oficial (CRÍTICO)** |
| 13 | Refresh conversas | `chatwoot-import-helper.ts` | UI não atualiza |
| 14 | Source maps | `package.json` | Stack trace legível |
| 15 | BuildImage.ps1 | `BuildImage.ps1` | Pipeline Podman (confirmado) |
| 16 | Error recovery | `error.config.ts` | Suicídio controlado |

### Recomendadas (fortemente sugerido)

| # | Customização | Arquivo | Motivo |
|---|--------------|---------|--------|
| 17 | Logs import detalhados | `chatwoot-import-helper.ts` | Troubleshooting |
| 18 | Cache.service validação | `cache.service.ts` | Prevenir erros com vCard |
| 19 | getBase64 metadata | `whatsapp.baileys.service.ts` | Metadata correto |
| 20 | Logs createContact | `chatwoot.service.ts` | Debug verbose |

---

## 🎯 ESTRATÉGIA ESPECÍFICA PARA SEU CASO

### Normalização BR: Abordagem Híbrida

Como você tem **muitos números legados**, a normalização BR é **CRÍTICA**.

**Problema:** Versão 2.3.4 usa CTE complexa. Suas alterações usam queries separadas.

**Opções:**

#### OPÇÃO A: Implementação Completa (RECOMENDADA)
- Substituir **TODO** o arquivo `chatwoot-import-helper.ts` pela sua versão custom
- Perder otimizações de CTE da 2.3.4
- **Ganho:** 100% de compatibilidade com números legados
- **Tempo:** +30min
- **Risco:** Baixo (sua versão já está testada)

#### OPÇÃO B: Patch Parcial (Mais trabalhoso)
- Manter CTE da 2.3.4
- Adicionar normalização BR na CTE
- **Ganho:** Performance da CTE + normalização
- **Tempo:** +2-3h (requer conhecimento avançado de PostgreSQL)
- **Risco:** Médio (pode introduzir bugs)

**DECISÃO PARA SEU CASO:** ✅ **OPÇÃO A** (implementação completa)

---

## 📝 RESUMO DAS AÇÕES

### Durante FASE 2 (Merge e Conflitos):

```bash
# 1. Conflitos fáceis (aceitar oficial):
✅ Dockerfile
✅ package-lock.json
✅ minio.server.ts (MAS aplicar patch depois)

# 2. package.json (híbrido):
✅ Aceitar oficial + adicionar source-map-support

# 3. chat.controller.ts:
✅ Aceitar oficial + adicionar SimpleMutex (código fornecido)

# 4. whatsapp.baileys.service.ts:
✅ Aceitar oficial + aplicar 4 patches (fornecidos abaixo)

# 5. chatwoot.service.ts:
✅ Aceitar oficial + aplicar 2 patches (fornecidos abaixo)

# 6. chatwoot-import-helper.ts:
✅ SUBSTITUIR COMPLETAMENTE pela versão custom backup
   (../backup-custom-files/chatwoot-import-helper.ts)
   DEPOIS aplicar correção do sliceIntoChunks da 2.3.4

# 7. BuildImage.ps1:
✅ Restaurar do backup
```

### Durante FASE 3 (Customizações Críticas):

```bash
# 1. error.config.ts:
✅ Substituir completamente (código fornecido)

# 2. cache.service.ts:
✅ Aplicar patch TTL defaults (código fornecido)

# 3. minio.server.ts:
✅ Aplicar patch try/catch (código fornecido)

# 4. Variáveis de ambiente:
✅ Adicionar Kafka, Prometheus, EXIT_ON_FATAL
```

---

## 🔧 PATCHES ESPECÍFICOS

### Patch 1: minio.server.ts (S3 Policy Tolerante - MinIO)

**Localizar método `createBucket` (linha ~35-62):**

```typescript
// ANTES (versão 2.3.4):
private async createBucket() {
  const bucketExists = await this.client.bucketExists(this.bucket);
  if (!bucketExists) {
    await this.client.makeBucket(this.bucket, this.region);

    // Define bucket policy
    const policy = {
      Version: '2012-10-17',
      Statement: [/* ... */],
    };

    await this.client.setBucketPolicy(this.bucket, JSON.stringify(policy));
  }
}
```

**SUBSTITUIR por:**

```typescript
// DEPOIS (com tolerância para MinIO):
private async createBucket() {
  try {
    const bucketExists = await this.client.bucketExists(this.bucket);
    if (!bucketExists) {
      await this.client.makeBucket(this.bucket, this.region);

      // Define bucket policy
      const policy = {
        Version: '2012-10-17',
        Statement: [/* ... */],
      };

      // MinIO pode não suportar setBucketPolicy
      try {
        if (process.env.S3_SKIP_POLICY !== 'true') {
          await this.client.setBucketPolicy(this.bucket, JSON.stringify(policy));
          this.logger.log('Bucket policy configured successfully');
        } else {
          this.logger.warn('S3_SKIP_POLICY=true - Skipping bucket policy configuration');
        }
      } catch (policyError) {
        // MinIO pode retornar NotImplemented - não é fatal
        this.logger.warn(`Failed to set bucket policy (MinIO?): ${policyError.message}`);
        this.logger.warn('Continuing without bucket policy - ensure MinIO is configured correctly');
      }
    }
  } catch (error) {
    this.logger.error('Error creating/configuring S3 bucket:', error);
    throw error;
  }
}
```

**Adicionar no .env:**
```bash
# MinIO: Skip bucket policy (NotImplemented error)
S3_SKIP_POLICY=true
```

---

### Patch 2: cache.service.ts (TTL Defaults + Validação)

**Localizar método `delete` e constructor:**

```typescript
// ADICIONAR no constructor (após inicialização do cache):
constructor(configService: ConfigService) {
  // ... código existente ...

  // Configurar TTL padrão se não especificado
  if (!this.config.TTL) {
    this.config.TTL = 3600; // 1 hora padrão
    this.logger.warn('CACHE.TTL not configured - using default 1 hour');
  }
}

// MODIFICAR método delete (linha ~34-76):
public async delete(key: string): Promise<boolean> {
  // Validar key antes de deletar
  if (!key || typeof key !== 'string') {
    this.logger.warn(`Invalid cache key provided to delete: ${key}`);
    return false;
  }

  // Proteção contra delete de vCard (causa problemas no monitoring)
  if (key.includes('vcard') || key.includes('profilePic')) {
    this.logger.verbose(`Skipping delete of monitoring key: ${key}`);
    return false;
  }

  try {
    await this.cache.del(key);
    this.logger.verbose(`Cache key deleted: ${key}`);
    return true;
  } catch (error) {
    this.logger.error(`Error deleting cache key ${key}: ${error.message}`);
    return false;
  }
}
```

---

### Patch 3: whatsapp.baileys.service.ts (4 correções)

#### 3.1. Upload mídia com key.id (linha ~1299-1329)

**Localizar onde mídia é salva (buscar por `fileName` ou `saveFile`):**

```typescript
// ANTES:
const fileName = `${Date.now()}_${originalFileName}`;

// DEPOIS:
const fileName = `${received.key.id}${ext}`; // ext = extensão do arquivo
```

#### 3.2. Guard key.id em updates (linha ~1438-1446)

**Localizar loop de message updates:**

```typescript
// ADICIONAR no início do loop:
for (const update of updates) {
  // ADICIONAR:
  if (!update.key?.id) {
    this.logger.warn('Message update without key.id - skipping', {
      remoteJid: update.key?.remoteJid,
      fromMe: update.key?.fromMe,
    });
    continue;
  }

  // ... resto do código
}
```

#### 3.3. Fallback status (linha ~1529-1536)

**Localizar onde `status` é processado em webhooks:**

```typescript
// ANTES:
const statusData = {
  status: messageUpdate.status,
  // ...
};

// DEPOIS:
const statusData = {
  status: messageUpdate.status ?? 'UNKNOWN', // Fallback para UNKNOWN
  // ...
};
```

#### 3.4. addLabel defensivo (linha ~4496-4526)

**Localizar método `addLabel`:**

```typescript
// SUBSTITUIR implementação completa:
private async addLabel(labelId: string, instanceId: string, chatId: string): Promise<void> {
  try {
    // Usar UPDATE em vez de INSERT para evitar criar chats fantasmas
    await this.prismaRepository.$executeRawUnsafe(
      `UPDATE "Chat"
       SET "labels" = (
         SELECT COALESCE(
           jsonb_agg(DISTINCT elem),
           '[]'::jsonb
         )
         FROM (
           SELECT jsonb_array_elements(COALESCE("labels", '[]'::jsonb)) AS elem
           UNION ALL
           SELECT to_jsonb($1::text)
         ) combined
       )
       WHERE "instanceId" = $2
         AND "remoteJid" = $3;`,
      labelId,
      instanceId,
      chatId
    );
  } catch (err: unknown) {
    // Não deixar erro de label quebrar fluxo principal
    this.logger.warn(`Failed to add label ${labelId} to chat ${chatId}: ${err.message}`);
  }
}
```

---

### Patch 4: chatwoot.service.ts (2 correções)

#### 4.1. createContact com ID direto (linha ~289-371)

**Localizar método `createContact`:**

```typescript
// ADICIONAR após criar contato:
public async createContact(instance: InstanceDto, data: any) {
  // ... código de criação ...

  const contact = await this.client.post(url, payload);

  // ADICIONAR: Extrair ID diretamente do response
  const contactId = contact.data?.id || contact.data?.payload?.contact?.id;

  if (!contactId) {
    this.logger.warn('Contact created but ID not found in response', {
      instance: instance.instanceName,
      response: contact.data,
    });
  }

  // ADICIONAR: Se houver label, aplicar imediatamente (evita race)
  if (data.label && contactId) {
    try {
      await this.client.post(`${url}/${contactId}/labels`, {
        labels: [data.label],
      });
    } catch (labelError) {
      this.logger.warn(`Failed to apply label to contact ${contactId}:`, labelError.message);
      // Retry após 1s
      setTimeout(async () => {
        try {
          await this.client.post(`${url}/${contactId}/labels`, {
            labels: [data.label],
          });
        } catch (retryError) {
          this.logger.error(`Retry failed for contact ${contactId} label`);
        }
      }, 1000);
    }
  }

  return contact;
}
```

#### 4.2. Guard participant (linha ~2209-2227)

**Localizar processamento de mensagens de grupo:**

```typescript
// ADICIONAR guard no início:
if (message.key.remoteJid?.includes('@g.us')) {
  // Mensagem de grupo
  const participantJid = message.key.participant || message.participant;

  // ADICIONAR:
  if (!participantJid) {
    this.logger.warn('Group message without participant - skipping', {
      remoteJid: message.key.remoteJid,
      fromMe: message.key.fromMe,
    });
    return; // Skip mensagens sem participant (ex: broadcast)
  }

  // ... resto do processamento
}
```

---

## 🔄 SUBSTITUIÇÃO COMPLETA: chatwoot-import-helper.ts

**EM VEZ** de fazer patches parciais, você vai **SUBSTITUIR COMPLETAMENTE** o arquivo pela sua versão custom, pois:
- ✅ Tem normalização BR (crítico para você)
- ✅ Tem busca por identifier (mais robusto)
- ✅ Tem refresh de conversas (UX melhor)
- ✅ Tem logs detalhados (troubleshooting)

**Único ajuste necessário:** Corrigir bug do `sliceIntoChunks` que existe na sua versão também.

**Durante FASE 2.7:**

```bash
# 1. Substituir arquivo completo
cp ../backup-custom-files/chatwoot-import-helper.ts \
   src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts

# 2. Abrir para corrigir sliceIntoChunks
nano src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts
```

**Localizar `sliceIntoChunks` (linha ~722):**

```typescript
// SE sua versão também tiver o bug (splice), corrigir:
public sliceIntoChunks<T>(arr: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += chunkSize) {
    chunks.push(arr.slice(i, i + chunkSize));
  }
  return chunks;
}
```

---

## 🎯 TEMPO ESTIMADO AJUSTADO

Com TODAS as customizações:

- FASE 2: **2-3 horas** (mais tempo pois são muitos patches)
- FASE 3: **1.5 horas** (mais customizações)
- **Total:** 5-7 horas (em vez de 4-6h do mínimo)

---

## ✅ CHECKLIST ESPECÍFICO

### Antes do Merge
- [ ] Backup do banco Chatwoot (contatos duplicados)
- [ ] Query SQL confirmou números legados (+55 com 10 dígitos)
- [ ] MinIO acessível e configurado
- [ ] Pipeline Podman testado

### Durante o Merge
- [ ] SimpleMutex aplicado
- [ ] Normalização BR aplicada (**CRÍTICO**)
- [ ] S3 policy tolerante aplicado
- [ ] BuildImage.ps1 restaurado
- [ ] sliceIntoChunks corrigido
- [ ] Todos os 4 patches em baileys.service aplicados
- [ ] Todos os 2 patches em chatwoot.service aplicados
- [ ] Cache.service patch aplicado
- [ ] minio.server.ts patch aplicado

### Testes em Staging
- [ ] Import histórico com números legados (10 dígitos)
- [ ] Verificar NO Chatwoot que não duplicou contatos
- [ ] Upload de mídia para MinIO (S3_SKIP_POLICY=true)
- [ ] Race condition no whatsappNumber (chamadas simultâneas)
- [ ] Conversas reabrem na UI do Chatwoot após import

---

## 📞 SE ALGO DER ERRADO

**Problema mais provável: Duplicação massiva de contatos BR**

**Se acontecer:**

1. **Parar import imediatamente**
2. **Executar cleanup:**
```sql
-- No banco Chatwoot:
BEGIN;

-- Ver duplicados
SELECT phone_number, COUNT(*)
FROM contacts
WHERE phone_number LIKE '+55%'
GROUP BY phone_number
HAVING COUNT(*) > 1;

-- Se confirmar duplicação, executar cleanup:
WITH duplicates AS (
  SELECT id, phone_number,
         ROW_NUMBER() OVER (
           PARTITION BY REPLACE(REPLACE(phone_number, '+559', '+55'), '+55', '+55')
           ORDER BY created_at
         ) as rn
  FROM contacts
  WHERE phone_number LIKE '+55%'
)
DELETE FROM contacts
WHERE id IN (SELECT id FROM duplicates WHERE rn > 1);

COMMIT;
```

3. **Verificar se normalização BR foi aplicada**
4. **Re-executar import**

---

Este arquivo documenta **EXATAMENTE** o que você precisa fazer no seu caso específico!

Use junto com `migracao-passo-a-passo.md`, mas siga as instruções deste arquivo para garantir que TODAS as customizações críticas sejam aplicadas.
