# Migração Evolution API: custom-2.2.3 → 2.3.4
## Guia Passo a Passo

**Data:** 2025-10-03
**Tempo estimado total:** 5-7 horas (customizações completas)
**Dificuldade:** Média-Alta

---

## 📋 CONFIGURAÇÃO DA SUA MIGRAÇÃO

**⚠️ IMPORTANTE:** Este guia é genérico. Para sua configuração específica, veja:

👉 **`docs/migracao-config.md`** 👈

### Seu Perfil Confirmado:
- ✅ Base com números BR legados (10 dígitos)
- ✅ Race conditions confirmadas (SimpleMutex necessário)
- ✅ Usa MinIO (S3 policy tolerante necessário)
- ✅ Pipeline Windows/Podman (BuildImage.ps1 necessário)

**Resultado:** **20 customizações** serão aplicadas (16 críticas + 4 recomendadas)

---

## ⚠️ ANTES DE COMEÇAR (LEIA migracao-config.md)

### Decisões Críticas (JÁ RESPONDIDAS = TODAS SIM)

#### 1. Você tem contatos históricos no Chatwoot com números BR antigos (sem 9º dígito)?

```sql
-- Execute no banco do Chatwoot:
SELECT COUNT(*) AS numeros_antigos
FROM contacts
WHERE phone_number LIKE '+55%'
  AND LENGTH(REPLACE(phone_number, '+55', '')) = 10;
```

- **Se retornar > 0:** ✅ PRESERVAR normalização BR (obrigatório)
- **Se retornar 0:** ❌ Pode ignorar normalização BR

**SUA DECISÃO:** [ ] Sim, preservar normalização BR  |  [ ] Não, ignorar

---

#### 2. Você já teve problemas de race condition no endpoint whatsappNumber?

- Sintoma: Dois requests simultâneos criam sessões duplicadas
- Logs: Erros em `chat.controller.ts:whatsappNumber`

**SUA DECISÃO:** [X] Sim, preservar SimpleMutex  |  [ ] Não, ignorar

---

#### 3. Você usa MinIO (em vez de AWS S3)?

**SUA DECISÃO:** [ X] Sim, preservar S3 policy tolerante  |  [ ] Não (AWS S3), ignorar

---

#### 4. Você usa pipeline Windows/Podman?

**SUA DECISÃO:** [ X] Sim, preservar BuildImage.ps1  |  [ ] Não, ignorar

---

## 📋 CHECKLIST COMPLETO

### Pré-requisitos

- [ X] Backup completo do banco de dados
- [ X] Backup do código atual (`tar -czf backup-$(date +%Y%m%d).tar.gz /path/to/evolution-api`)
- [ X] Ambiente staging disponível
- [ X] Acesso ao repositório upstream (https://github.com/EvolutionAPI/evolution-api.git)
- [ ] Node.js instalado localmente (para testes) - usar podman.
- [ ] Git configurado

---

## FASE 1: PREPARAÇÃO (30 minutos)

### 1.1. Criar Ambiente Isolado

```bash
# 1. Navegar para o diretório do projeto
cd /path/to/evolution-api

# 2. Garantir que está na branch atual limpa
git status
# Se houver mudanças não commitadas, commit ou stash

# 3. Criar branch de trabalho
git checkout -b upgrade-2.3.4-$(date +%Y%m%d)

# 4. Adicionar remote upstream (se não existir)
git remote add upstream https://github.com/EvolutionAPI/evolution-api.git 2>/dev/null || echo "Upstream já existe"

# 5. Buscar tags do upstream
git fetch upstream --tags
```

### 1.2. Backup de Arquivos Críticos

```bash
# Criar diretório de backup
mkdir -p ../backup-custom-files

# Backup dos arquivos que serão modificados
git show custom-2.2.3:src/api/controllers/chat.controller.ts \
  > ../backup-custom-files/chat.controller.ts

git show custom-2.2.3:src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts \
  > ../backup-custom-files/chatwoot-import-helper.ts

git show custom-2.2.3:src/api/services/cache.service.ts \
  > ../backup-custom-files/cache.service.ts

git show custom-2.2.3:src/api/integrations/storage/s3/libs/minio.server.ts \
  > ../backup-custom-files/minio.server.ts

git show custom-2.2.3:package.json \
  > ../backup-custom-files/package.json

git show custom-2.2.3:BuildImage.ps1 \
  > ../backup-custom-files/BuildImage.ps1 2>/dev/null || echo "BuildImage.ps1 não existe"

echo "✅ Backup criado em ../backup-custom-files/"
```

### 1.3. Verificar Estado Atual

```bash
# Verificar versão atual
cat package.json | grep '"version"'

# Verificar branch atual
git branch --show-current

# Listar arquivos modificados localmente (não deve ter nada)
git status --short
```

**✅ Checkpoint:** Se tudo OK, prosseguir para Fase 2.

---

## FASE 2: MERGE E RESOLUÇÃO DE CONFLITOS (1-2 horas)

### 2.1. Tentar Merge

```bash
# Merge com tag 2.3.4
git merge 2.3.4

# Isso VAI dar conflitos - ESPERADO!
```

**Saída esperada:**
```
Auto-merging package.json
CONFLICT (content): Merge conflict in package.json
Auto-merging src/api/controllers/chat.controller.ts
CONFLICT (content): Merge conflict in src/api/controllers/chat.controller.ts
...
Automatic merge failed; fix conflicts and then commit the result.
```

### 2.2. Resolver Conflitos Fáceis (Aceitar Versão Oficial)

```bash
# 1. Dockerfile - Aceitar oficial
git checkout --theirs Dockerfile
git add Dockerfile

# 2. package-lock.json - Aceitar oficial (vamos regenerar depois)
git checkout --theirs package-lock.json
git add package-lock.json

# 3. minio.server.ts - Aceitar oficial
git checkout --theirs src/api/integrations/storage/s3/libs/minio.server.ts
git add src/api/integrations/storage/s3/libs/minio.server.ts

echo "✅ Conflitos fáceis resolvidos"
```

### 2.3. Resolver package.json (Híbrido)

```bash
# Aceitar versão oficial como base
git checkout --theirs package.json

# Editar manualmente
nano package.json  # ou seu editor preferido
```

**Adicionar no package.json:**

1. Na seção `dependencies`, adicionar:
```json
"source-map-support": "^0.5.21",
```

2. Na seção `scripts`, modificar `start:prod`:
```json
"start:prod": "node --enable-source-maps -r source-map-support/register dist/main.js",
```

```bash
# Salvar e adicionar ao stage
git add package.json

echo "✅ package.json resolvido com source-map-support"
```

### 2.4. Resolver chat.controller.ts

**Se você respondeu SIM para SimpleMutex:**

```bash
# Aceitar versão oficial primeiro
git checkout --theirs src/api/controllers/chat.controller.ts

# Abrir arquivo para edição
nano src/api/controllers/chat.controller.ts
```

**Adicionar ANTES da classe ChatController (após os imports):**

```typescript
// SimpleMutex para evitar race conditions
class SimpleMutex {
  private locked = false;
  private waiting: Array<() => void> = [];

  async acquire(): Promise<void> {
    if (this.locked) {
      await new Promise<void>(resolve => this.waiting.push(resolve));
    }
    this.locked = true;
  }

  release(): void {
    const next = this.waiting.shift();
    if (next) next();
    else this.locked = false;
  }

  async runExclusive<T>(fn: () => Promise<T>): Promise<T> {
    await this.acquire();
    try {
      return await fn();
    } finally {
      this.release();
    }
  }
}
```

**Adicionar DENTRO da classe ChatController:**

```typescript
export class ChatController {
  constructor(private readonly waMonitor: WAMonitoringService) {}

  // ADICIONAR AQUI:
  private static whatsappNumberMutex = new SimpleMutex();

  public async whatsappNumber({ instanceName }: InstanceDto, data: WhatsAppNumberDto) {
    // MODIFICAR para usar mutex:
    return await ChatController.whatsappNumberMutex.runExclusive(async () => {
      return this.waMonitor.waInstances[instanceName].whatsappNumber(data);
    });
  }
  // ... resto do código
}
```

**Se você respondeu NÃO para SimpleMutex:**

```bash
# Apenas aceitar oficial
git checkout --theirs src/api/controllers/chat.controller.ts
```

```bash
# Adicionar ao stage
git add src/api/controllers/chat.controller.ts

echo "✅ chat.controller.ts resolvido"
```

### 2.5. Resolver whatsapp.baileys.service.ts

```bash
# Aceitar versão oficial (ela já incorporou a maioria das correções)
git checkout --theirs src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts
git add src/api/integrations/channel/whatsapp/whatsapp.baileys.service.ts

echo "✅ whatsapp.baileys.service.ts resolvido (versão oficial)"
```

### 2.6. Resolver chatwoot.service.ts

```bash
# Aceitar versão oficial (ela já tem tratamento de @lid)
git checkout --theirs src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts
git add src/api/integrations/chatbot/chatwoot/services/chatwoot.service.ts

echo "✅ chatwoot.service.ts resolvido (versão oficial)"
```

### 2.7. Resolver chatwoot-import-helper.ts (CRÍTICO - 30 min)

**⚠️ NO SEU CASO:** Usar **SUBSTITUIÇÃO COMPLETA** (ver `migracao-config.md`)

Porque:
- ✅ Tem normalização BR (crítico para sua base legada)
- ✅ Tem busca por identifier (mais robusto)
- ✅ Tem refresh de conversas (UX melhor)
- ✅ Tem logs detalhados (troubleshooting)

```bash
# 1. SUBSTITUIR arquivo completo pela sua versão custom
cp ../backup-custom-files/chatwoot-import-helper.ts \
   src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts

# 2. Abrir para corrigir sliceIntoChunks (único ajuste necessário)
nano src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts
```

#### 2.7.1. ÚNICO AJUSTE: Corrigir sliceIntoChunks

**Localizar método sliceIntoChunks (linha ~722):**

```typescript
// Verificar se sua versão está correta:
public sliceIntoChunks<T>(arr: T[], chunkSize: number): T[][] {
  const chunks: T[][] = [];
  for (let i = 0; i < arr.length; i += chunkSize) {
    chunks.push(arr.slice(i, i + chunkSize));
  }
  return chunks;
}
```

**✅ Se estiver assim, está OK!**

**❌ Se estiver usando `splice`, corrigir para usar `slice`**

```bash
# Salvar arquivo
# Verificar se compila
npm run build

# Se OK, adicionar ao stage
git add src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts

echo "✅ chatwoot-import-helper.ts resolvido"
```

### 2.8. Reaplicar BuildImage.ps1 (se necessário)

**Se você respondeu SIM para BuildImage.ps1:**

```bash
# Copiar do backup
cp ../backup-custom-files/BuildImage.ps1 ./

git add BuildImage.ps1

echo "✅ BuildImage.ps1 restaurado"
```

### 2.9. Regenerar package-lock.json

```bash
# Instalar dependências (regenera lockfile)
npm install

# Adicionar ao stage
git add package-lock.json

echo "✅ package-lock.json regenerado"
```

### 2.10. Verificar Estado do Merge

```bash
# Não deve ter conflitos restantes
git status

# Esperado:
# All conflicts fixed but you are still merging.
#   (use "git commit" to conclude merge)
```

---

## FASE 3: APLICAR CUSTOMIZAÇÕES CRÍTICAS (1.5 horas)

### 3.1. Aplicar Patches em Arquivos Oficiais

**⚠️ NO SEU CASO:** Você precisa aplicar **9 patches adicionais** (ver detalhes em `migracao-config.md`)

Resumo rápido:

```bash
# Lista de patches a aplicar:
# 1. minio.server.ts - S3 policy tolerante (MinIO)
# 2. cache.service.ts - TTL defaults + validação
# 3-6. whatsapp.baileys.service.ts - 4 correções
# 7-8. chatwoot.service.ts - 2 correções
```

**👉 Abra `docs/migracao-config.md` seção "PATCHES ESPECÍFICOS" e aplique cada um.**

**Estimativa:** 45-60 minutos para aplicar todos os 9 patches.

**Após aplicar todos os patches, voltar aqui para continuar.**

---

### 3.2. Implementar Suicídio Controlado (Error Recovery)

**Substituir src/config/error.config.ts:**

```bash
# Abrir arquivo
nano src/config/error.config.ts
```

**Conteúdo completo:**

```typescript
import { Logger } from './logger.config';
import { configService, Webhook } from './env.config';
import axios from 'axios';

let isShuttingDown = false;
let fatalErrorCount = 0;
const FATAL_ERROR_THRESHOLD = 3;

const FATAL_ERROR_PATTERNS = [
  /Connection Closed/i,
  /WebSocket was closed before the connection/i,
  /ECONNREFUSED/i,
  /ETIMEDOUT/i,
  /socket hang up/i,
];

function isFatalError(error: Error): boolean {
  const errorMessage = error?.message || '';
  const errorStack = error?.stack || '';
  return FATAL_ERROR_PATTERNS.some(pattern =>
    pattern.test(errorMessage) || pattern.test(errorStack)
  );
}

async function sendErrorAlert(error: Error, origin: string): Promise<void> {
  try {
    const webhook = configService.get<Webhook>('WEBHOOK');
    if (!webhook.EVENTS.ERRORS_WEBHOOK || !webhook.EVENTS.ERRORS) {
      return;
    }

    const errorData = {
      event: 'fatal_error_shutdown',
      data: {
        error: error.name || 'Fatal Error',
        message: error.message || 'Unknown fatal error',
        stack: error.stack || '',
        origin,
        action: 'Container will restart',
      },
      date_time: new Date().toISOString(),
      hostname: process.env.HOSTNAME || 'unknown',
      pid: process.pid,
    };

    await axios.post(webhook.EVENTS.ERRORS_WEBHOOK, errorData, {
      timeout: 3000,
    });
  } catch (webhookError) {
    console.error('[ERROR ALERT] Failed to send webhook:', webhookError.message);
  }
}

async function gracefulShutdown(
  error: Error,
  origin: string,
  logger: Logger
): Promise<void> {
  if (isShuttingDown) return;
  isShuttingDown = true;

  logger.error('========================================');
  logger.error('💀 FATAL ERROR DETECTED - INITIATING CONTROLLED SUICIDE');
  logger.error('========================================');
  logger.error({
    origin,
    error: {
      name: error.name,
      message: error.message,
      stack: error.stack,
    },
    pid: process.pid,
    uptime: process.uptime(),
    memoryUsage: process.memoryUsage(),
  });

  await sendErrorAlert(error, origin).catch(() => {});
  await new Promise(resolve => setTimeout(resolve, 500));

  logger.error('🔴 Exiting process with code 1...');
  logger.error('🔄 Docker Swarm will restart the container automatically');
  logger.error('========================================');

  // Verificar se deve fazer exit (controlado por env var)
  if (process.env.EXIT_ON_FATAL !== 'false') {
    process.exit(1);
  } else {
    logger.warn('⚠️  EXIT_ON_FATAL=false - Not exiting (debug mode)');
  }
}

export function onUnexpectedError() {
  const logger = new Logger('ErrorHandler');

  process.on('uncaughtException', async (error: Error, origin: string) => {
    const exceptionLogger = new Logger('uncaughtException');
    exceptionLogger.error({
      origin,
      stderr: process.stderr.fd,
      error: {
        name: error.name,
        message: error.message,
        stack: error.stack,
      },
    });

    exceptionLogger.warn('⚠️  Uncaught exception detected - this is ALWAYS fatal');
    await gracefulShutdown(error, origin, exceptionLogger);
  });

  process.on('unhandledRejection', async (reason: any, promise: Promise<any>) => {
    const rejectionLogger = new Logger('unhandledRejection');
    const error = reason instanceof Error ? reason : new Error(String(reason));

    rejectionLogger.error({
      origin: promise,
      stderr: process.stderr.fd,
      error: {
        name: error.name,
        message: error.message,
        stack: error.stack,
      },
    });

    if (isFatalError(error)) {
      fatalErrorCount++;
      rejectionLogger.warn(`⚠️  Fatal error pattern detected (${fatalErrorCount}/${FATAL_ERROR_THRESHOLD})`);

      if (fatalErrorCount >= FATAL_ERROR_THRESHOLD) {
        rejectionLogger.error('🔴 Fatal error threshold reached - forcing restart');
        await gracefulShutdown(error, 'unhandledRejection', rejectionLogger);
      }
    }

    setTimeout(() => {
      if (fatalErrorCount > 0) {
        fatalErrorCount = Math.max(0, fatalErrorCount - 1);
      }
    }, 60000);
  });

  process.on('SIGTERM', () => {
    logger.info('📡 SIGTERM received - initiating graceful shutdown');
    process.exit(0);
  });

  process.on('SIGINT', () => {
    logger.info('📡 SIGINT received - initiating graceful shutdown');
    process.exit(0);
  });

  logger.info('✅ Error handlers registered (with controlled suicide)');
}
```

```bash
# Adicionar ao stage
git add src/config/error.config.ts

echo "✅ Error recovery implementado"
```

### 3.2. Adicionar Variáveis de Ambiente Novas

**Criar arquivo .env.example atualizado:**

```bash
nano .env.example
```

**Adicionar ao final:**

```bash
# ==========================================
# NOVIDADES 2.3.4
# ==========================================

# Kafka (Event Streaming)
KAFKA_ENABLED=false
KAFKA_BROKER=localhost:9092
KAFKA_CLIENT_ID=evolution-api
KAFKA_CONSUMER_GROUP_ID=evolution-group

# Prometheus (Métricas)
PROMETHEUS_METRICS=false

# Error Recovery (Suicídio Controlado)
EXIT_ON_FATAL=true  # true = exit em erros fatais | false = apenas log (debug)
```

```bash
git add .env.example

echo "✅ Variáveis de ambiente documentadas"
```

### 3.3. Atualizar .gitignore (se necessário)

```bash
# Garantir que .env está ignorado
echo ".env" >> .gitignore
echo "*.log" >> .gitignore

git add .gitignore
```

---

## FASE 4: BUILD E TESTES LOCAIS (30 minutos)

### 4.1. Build

```bash
# Limpar build anterior
rm -rf dist/

# Build
npm run build

# Verificar se build passou
echo $?
# Esperado: 0 (sucesso)
```

**Se houver erros TypeScript:**
- Corrigir erros apontados
- Executar `npm run build` novamente
- Repetir até build passar

### 4.2. Verificar Arquivos Gerados

```bash
# Verificar se dist/ foi criado
ls -la dist/

# Verificar main.js existe
ls -la dist/main.js

echo "✅ Build compilou com sucesso"
```

### 4.3. Commit do Merge

```bash
# Commit do merge
git commit -m "chore: merge Evolution API 2.3.4 with critical patches

- Merged official 2.3.4 release
- Preserved source-map-support
- Fixed sliceIntoChunks bug (critical)
- Implemented controlled suicide for fatal errors
$(if [ -f BuildImage.ps1 ]; then echo '- Preserved BuildImage.ps1 deployment script'; fi)

BREAKING CHANGES:
- Upgraded to Baileys v7.0.0-rc.4
- Added Kafka integration support (disabled by default)
- Added Prometheus metrics endpoint (disabled by default)
- Security fix: Path Traversal in /assets endpoint

Custom patches applied:
- source-map-support for better error stacks
- sliceIntoChunks bug fix (prevents data loss in imports)
$(if grep -q 'SimpleMutex' src/api/controllers/chat.controller.ts; then echo '- SimpleMutex in whatsappNumber (prevents race conditions)'; fi)
$(if grep -q 'normalizeBrazilianPhoneNumberOptions' src/api/integrations/chatbot/chatwoot/utils/chatwoot-import-helper.ts; then echo '- Brazilian phone number normalization (9th digit)'; fi)
- Error recovery with controlled suicide (EXIT_ON_FATAL)

Co-Authored-By: Claude <noreply@anthropic.com>"

echo "✅ Merge commitado"
```

---

## FASE 5: TESTES EM STAGING (2-3 horas)

### 5.1. Preparar Ambiente Staging

```bash
# Push para branch remota
git push origin upgrade-2.3.4-$(date +%Y%m%d)

# OU se staging usa diretamente:
# scp -r . usuario@staging:/path/to/evolution-api/
```

### 5.2. Configurar Variáveis de Ambiente em Staging

**No servidor staging, criar/atualizar .env:**

```bash
# SSH para staging
ssh usuario@staging-server

cd /path/to/evolution-api

# Backup do .env atual
cp .env .env.backup.$(date +%Y%m%d)

# Editar .env
nano .env
```

**Adicionar/verificar:**

```bash
# Desabilitar novidades (por enquanto)
KAFKA_ENABLED=false
PROMETHEUS_METRICS=false

# Habilitar suicídio controlado
EXIT_ON_FATAL=true

# Manter outras variáveis existentes
# ...
```

### 5.3. Build e Restart em Staging

```bash
# Pull código atualizado
git pull origin upgrade-2.3.4-$(date +%Y%m%d)

# Instalar dependências
npm install

# Build
npm run build

# Restart do serviço (depende do seu setup)
# Docker:
docker-compose down && docker-compose up -d

# OU PM2:
pm2 restart evolution-api

# OU Systemd:
sudo systemctl restart evolution-api
```

### 5.4. Monitorar Startup

```bash
# Docker logs
docker-compose logs -f --tail=100

# OU PM2 logs
pm2 logs evolution-api

# Buscar por:
# - "✅ Error handlers registered (with controlled suicide)"
# - "HTTP - ON: 8080" (ou sua porta)
# - Erros de startup
```

**⚠️ Se houver loop de restart:**
- Verificar logs: `docker logs <container-id>`
- Problema comum: banco/redis fora
- Corrigir problema antes de continuar

### 5.5. Testes Funcionais em Staging

#### 5.5.1. Teste 1: Criar Instância

```bash
curl -X POST http://staging:8080/instance/create \
  -H "apikey: SEU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "test-upgrade",
    "qrcode": true
  }'

# Esperado: Retorna QR code e instance criada
```

#### 5.5.2. Teste 2: Conectar WhatsApp

- Escanear QR code com WhatsApp
- Verificar se conecta com sucesso
- Logs devem mostrar: `connection.update: open`

#### 5.5.3. Teste 3: Enviar Mensagem

```bash
curl -X POST http://staging:8080/message/sendText/test-upgrade \
  -H "apikey: SEU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5521999999999",
    "text": "Teste migração 2.3.4"
  }'

# Verificar se mensagem chegou no WhatsApp
```

#### 5.5.4. Teste 4: Integração Chatwoot (SE usar)

```bash
# Criar integração Chatwoot
curl -X POST http://staging:8080/chatwoot/set/test-upgrade \
  -H "apikey: SEU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "enabled": true,
    "accountId": "1",
    "token": "SEU_CHATWOOT_TOKEN",
    "url": "https://chatwoot.example.com",
    "signMsg": false,
    "nameInbox": "Test Inbox"
  }'

# Enviar mensagem para a instância
# Verificar se aparece no Chatwoot
```

#### 5.5.5. Teste 5: Import Histórico Chatwoot (SE usar)

```bash
# Importar últimas 50 mensagens
curl -X POST http://staging:8080/chatwoot/import/test-instance \
  -H "apikey: SEU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "test-instance",
    "limit": 50
  }'

# Verificar logs:
# - Não deve ter "perda de itens" (bug sliceIntoChunks corrigido)
# - Contatos brasileiros devem aparecer corretamente (se normalização BR ativa)
# - Conversas devem reabrir na UI (se safeRefreshConversation aplicado)
```

#### 5.5.6. Teste 6: Erro Fatal (Suicídio Controlado)

```bash
# Forçar erro fatal (opcional - CUIDADO)
# Desconectar banco de dados temporariamente
# OU
# Fechar conexão WhatsApp e tentar enviar mensagem

# Verificar logs:
docker logs <container-id> 2>&1 | grep "FATAL ERROR"

# Esperado:
# - "💀 FATAL ERROR DETECTED - INITIATING CONTROLLED SUICIDE"
# - Container morre (exit code 1)
# - Docker Swarm recria container automaticamente
# - Novo container sobe saudável
```

### 5.6. Monitoramento Pós-Deploy Staging (24h)

```bash
# Monitorar restarts
docker ps -a | grep evolution

# Monitorar logs de erro
docker logs -f <container-id> 2>&1 | grep -i error

# Métricas
# - Restarts: < 2 por hora = OK
# - Erros fatais: < 3 consecutivos = OK
# - Tempo de uptime: > 1 hora sem restart = OK
```

**✅ Checkpoint:** Se staging estável por 24h, prosseguir para produção.

---

## FASE 6: DEPLOY EM PRODUÇÃO (1 hora + monitoramento)

### 6.1. Preparação Pré-Deploy

- [ ] Staging estável por 24h
- [ ] Todos os testes funcionais passando
- [ ] Backup do banco de dados de produção
- [ ] Janela de manutenção agendada (baixo tráfego)
- [ ] Rollback plan pronto
- [ ] Equipe de suporte avisada

### 6.2. Rollback Plan

**Criar script de rollback:**

```bash
cat > rollback.sh << 'EOF'
#!/bin/bash
set -e

echo "🔄 Iniciando rollback para custom-2.2.3..."

# Checkout para versão anterior
git checkout custom-2.2.3

# Reinstalar dependências antigas
npm install

# Rebuild
npm run build

# Restart
docker-compose down
docker-compose up -d

echo "✅ Rollback concluído"
EOF

chmod +x rollback.sh
```

### 6.3. Deploy

```bash
# 1. SSH para produção
ssh usuario@production-server

cd /path/to/evolution-api

# 2. Backup do código atual
tar -czf backup-pre-upgrade-$(date +%Y%m%d-%H%M).tar.gz .

# 3. Pull código atualizado
git fetch origin
git checkout upgrade-2.3.4-$(date +%Y%m%d)

# 4. Backup do .env
cp .env .env.backup.$(date +%Y%m%d)

# 5. Atualizar .env (IMPORTANTE)
nano .env
```

**Adicionar/verificar no .env de produção:**

```bash
# Desabilitar novidades
KAFKA_ENABLED=false
PROMETHEUS_METRICS=false

# Habilitar suicídio controlado
EXIT_ON_FATAL=true
```

```bash
# 6. Instalar dependências
npm install

# 7. Build
npm run build

# 8. Restart (em horário de baixo tráfego)
docker-compose down
docker-compose up -d

# OU se usar blue-green deployment:
# ... seu processo de blue-green
```

### 6.4. Monitoramento Pós-Deploy (Primeiras 2 horas)

```bash
# Terminal 1: Logs gerais
docker-compose logs -f

# Terminal 2: Erros fatais
docker logs -f <container-id> 2>&1 | grep -E "FATAL|ERROR|WARN"

# Terminal 3: Métricas do container
watch -n 5 'docker stats --no-stream <container-id>'
```

**Checklist de validação:**

- [ ] Container subiu sem erros
- [ ] Instâncias existentes reconectaram
- [ ] Mensagens sendo enviadas/recebidas
- [ ] Webhooks funcionando
- [ ] Chatwoot integrado (se aplicável)
- [ ] Sem erros de database
- [ ] Sem loops de restart

### 6.5. Teste de Fumaça em Produção

```bash
# 1. Listar instâncias
curl -X GET http://production:8080/instance/fetchInstances \
  -H "apikey: SEU_API_KEY"

# 2. Verificar status de uma instância
curl -X GET http://production:8080/instance/connectionState/INSTANCE_NAME \
  -H "apikey: SEU_API_KEY"

# 3. Enviar mensagem de teste (para número interno da equipe)
curl -X POST http://production:8080/message/sendText/INSTANCE_NAME \
  -H "apikey: SEU_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "number": "5521999999999",
    "text": "✅ Upgrade 2.3.4 concluído com sucesso"
  }'
```

### 6.6. Monitoramento Estendido (7 dias)

**Métricas a observar:**

| Métrica | Alvo | Ação se Fora |
|---------|------|--------------|
| Uptime | > 99% | Investigar causa de restarts |
| Restarts por dia | < 5 | Analisar logs de erros fatais |
| Tempo médio entre restarts | > 4h | OK - erros transientes |
| Erros de importação Chatwoot | 0 | Verificar sliceIntoChunks |
| Duplicação de contatos BR | 0 | Verificar normalização |

**Alertas a configurar:**

- Container em loop de restart (> 3 em 5 min)
- Erro fatal sem auto-recovery
- Performance degradada (CPU > 80% por > 10 min)

---

## FASE 7: PÓS-DEPLOY E LIMPEZA

### 7.1. Merge para Branch Principal

```bash
# Após 7 dias estável em produção:

# 1. Checkout para main
git checkout main

# 2. Merge da branch de upgrade
git merge upgrade-2.3.4-$(date +%Y%m%d)

# 3. Tag a versão
git tag -a v2.3.4-custom-$(date +%Y%m%d) -m "Evolution API 2.3.4 with critical patches"

# 4. Push
git push origin main --tags
```

### 7.2. Documentação

- [ ] Atualizar README.md com versão 2.3.4
- [ ] Documentar variáveis de ambiente novas (Kafka, Prometheus, EXIT_ON_FATAL)
- [ ] Atualizar runbook de operações
- [ ] Documentar procedimento de rollback
- [ ] Compartilhar análise com time

### 7.3. Cleanup

```bash
# Remover backups antigos (após 30 dias)
find ../backup-custom-files -mtime +30 -delete
find . -name "*.backup.*" -mtime +30 -delete

# Remover branches temporárias locais
git branch -d upgrade-2.3.4-$(date +%Y%m%d)
```

---

## TROUBLESHOOTING

### Problema 1: Container em Loop de Restart

**Sintoma:**
```
Container reinicia a cada 5-10 segundos
Logs mostram sempre o mesmo erro fatal
```

**Diagnóstico:**
```bash
# Ver últimos 50 logs
docker logs --tail=50 <container-id>

# Buscar por padrão de erro
docker logs <container-id> 2>&1 | grep -A10 "FATAL ERROR"
```

**Soluções comuns:**

1. **Banco de dados fora:**
```bash
# Verificar PostgreSQL
docker exec -it postgres_container pg_isready
# OU
psql -h localhost -U postgres -c "SELECT 1"
```

2. **Redis fora:**
```bash
# Verificar Redis
docker exec -it redis_container redis-cli ping
# OU
redis-cli ping
```

3. **Variáveis de ambiente inválidas:**
```bash
# Revisar .env
cat .env | grep -E "DATABASE|REDIS|CACHE"
```

**Workaround temporário:**
```bash
# Desabilitar suicídio controlado para debug
echo "EXIT_ON_FATAL=false" >> .env

# Restart
docker-compose restart

# Investigar logs sem container morrer
docker logs -f <container-id>

# Após corrigir, reabilitar
sed -i 's/EXIT_ON_FATAL=false/EXIT_ON_FATAL=true/' .env
```

---

### Problema 2: Build Falha com Erros TypeScript

**Sintoma:**
```
npm run build
...
error TS2322: Type 'X' is not assignable to type 'Y'
```

**Solução:**
```bash
# 1. Limpar cache
rm -rf node_modules dist
npm install

# 2. Verificar versão do TypeScript
npm list typescript
# Deve ser >= 5.0

# 3. Se ainda falhar, verificar tsconfig.json
cat tsconfig.json
# strict: true pode causar erros em código legado

# 4. Temporariamente, reduzir strict (NÃO RECOMENDADO para produção)
# Editar tsconfig.json: "strict": false
```

---

### Problema 3: Chatwoot Import Duplica Contatos

**Sintoma:**
```
Após import, contatos aparecem duplicados no Chatwoot
Especialmente números brasileiros com/sem 9º dígito
```

**Diagnóstico:**
```sql
-- No banco Chatwoot:
SELECT phone_number, COUNT(*) as duplicates
FROM contacts
GROUP BY phone_number
HAVING COUNT(*) > 1;
```

**Solução:**
```sql
-- Script de cleanup (EXECUTE COM CUIDADO):
WITH duplicates AS (
  SELECT id, phone_number,
         ROW_NUMBER() OVER (PARTITION BY phone_number ORDER BY created_at) as rn
  FROM contacts
  WHERE phone_number LIKE '+55%'
)
DELETE FROM contacts
WHERE id IN (
  SELECT id FROM duplicates WHERE rn > 1
);
```

**Prevenção:**
- Garantir que normalizeBrazilianPhoneNumberOptions foi aplicada
- OU fazer limpeza preventiva ANTES do import

---

### Problema 4: Erro "Cannot find module 'source-map-support'"

**Sintoma:**
```
Error: Cannot find module 'source-map-support'
```

**Solução:**
```bash
# Instalar dependência
npm install --save source-map-support

# Rebuild
npm run build

# Restart
docker-compose restart
```

---

## ANEXOS

### Anexo A: Script de Verificação Pré-Merge

```bash
#!/bin/bash
# pre-merge-check.sh

echo "=== Verificação Pré-Merge ==="

# 1. Verificar git limpo
if [[ -n $(git status --porcelain) ]]; then
  echo "❌ Git working directory não está limpo"
  git status --short
  exit 1
fi

# 2. Verificar branch atual
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" == "main" ]] || [[ "$CURRENT_BRANCH" == "master" ]]; then
  echo "❌ Não fazer merge diretamente na branch principal"
  exit 1
fi

# 3. Verificar se upstream existe
if ! git remote get-url upstream > /dev/null 2>&1; then
  echo "❌ Remote 'upstream' não configurado"
  exit 1
fi

# 4. Verificar se tag 2.3.4 existe
if ! git tag -l | grep -q "^2.3.4$"; then
  echo "⚠️  Tag 2.3.4 não encontrada - fazendo fetch"
  git fetch upstream --tags
fi

echo "✅ Todas as verificações passaram"
echo "Branch atual: $CURRENT_BRANCH"
echo "Pronto para merge com 2.3.4"
```

### Anexo B: Queries de Diagnóstico Chatwoot

```sql
-- 1. Verificar números antigos (sem 9º dígito)
SELECT COUNT(*) AS numeros_antigos
FROM contacts
WHERE phone_number LIKE '+55%'
  AND LENGTH(REPLACE(phone_number, '+55', '')) = 10;

-- 2. Verificar duplicação
SELECT phone_number, COUNT(*) as total,
       STRING_AGG(id::text, ', ') as contact_ids
FROM contacts
WHERE phone_number LIKE '+55%'
GROUP BY phone_number
HAVING COUNT(*) > 1
ORDER BY total DESC;

-- 3. Verificar conversas sem refresh
SELECT c.id, c.display_id, c.status, c.last_activity_at
FROM conversations c
WHERE c.status = 0  -- Resolvido
  AND c.last_activity_at > NOW() - INTERVAL '1 hour'
ORDER BY c.last_activity_at DESC;
```

### Anexo C: Comando de Deploy em Um Passo (Staging)

```bash
#!/bin/bash
# deploy-staging.sh

set -e

echo "🚀 Deploy Evolution API 2.3.4 - Staging"

# Variáveis
BRANCH="upgrade-2.3.4-$(date +%Y%m%d)"
ENV_FILE=".env"

# 1. Pull
git fetch origin
git checkout "$BRANCH"
git pull origin "$BRANCH"

# 2. Backup .env
cp "$ENV_FILE" "${ENV_FILE}.backup.$(date +%Y%m%d-%H%M)"

# 3. Instalar deps
npm install

# 4. Build
npm run build

# 5. Restart
docker-compose down
docker-compose up -d

# 6. Wait for healthy
echo "⏳ Aguardando container ficar healthy..."
sleep 10

# 7. Health check
if curl -f http://localhost:8080/health > /dev/null 2>&1; then
  echo "✅ Deploy concluído com sucesso"
  docker-compose ps
else
  echo "❌ Health check falhou"
  docker-compose logs --tail=50
  exit 1
fi
```

---

## CHECKLIST FINAL

### Antes do Deploy Produção

- [ ] Staging estável por 24h
- [ ] Todos os testes funcionais OK
- [ ] Backup do banco de dados
- [ ] Backup do código atual
- [ ] .env atualizado com variáveis novas
- [ ] Rollback plan testado
- [ ] Equipe avisada
- [ ] Janela de manutenção agendada

### Durante o Deploy

- [ ] Build passou sem erros
- [ ] Container subiu sem erros
- [ ] Logs não mostram erros fatais
- [ ] Instâncias reconectaram
- [ ] Testes de fumaça passaram

### Após o Deploy

- [ ] Monitoramento ativo (2h contínuo)
- [ ] Métricas dentro do esperado
- [ ] Sem restarts anormais
- [ ] Documentação atualizada
- [ ] Tag de versão criada

---

## CONTATOS E SUPORTE

- **Documentação oficial:** https://github.com/EvolutionAPI/evolution-api
- **Issues:** https://github.com/EvolutionAPI/evolution-api/issues
- **Discord:** https://discord.gg/evolution (se existir)

**Documentos relacionados:**
- `docs/evolution-upgrade-claude.md` - Análise completa
- `docs/evolution-upgrade-codex.md` - Análise técnica
- `docs/error-recovery-strategy.md` - Estratégia de error recovery
- `docs/errors.txt` - Log de erros históricos

---

**FIM DO GUIA**

Boa sorte com a migração! 🚀
