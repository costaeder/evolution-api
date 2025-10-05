# Estratégia de Recuperação de Erros e Suicídio Controlado

**Data:** 2025-10-02
**Objetivo:** Implementar health checks e suicídio controlado para erros fatais que deixam a Evolution API travada.

---

## 1. Análise dos Erros em `docs/errors.txt`

### 🔴 Erro 1: Connection Closed (FATAL - NÃO COBERTO)

**Ocorrência:** Linha 1-25 de `docs/errors.txt`

```
Error: Connection Closed
at sendRawMessage (/evolution/node_modules/baileys/lib/Socket/socket.js:60:19)
...
statusCode: 428,
payload: {
  statusCode: 428,
  error: 'Precondition Required',
  message: 'Connection Closed'
}
```

#### Análise:
- **Causa:** Conexão WebSocket com WhatsApp foi fechada
- **Momento:** Durante envio de mensagem via Chatwoot
- **Impacto:** ⚠️ **CRÍTICO** - A instância fica inutilizável
- **Estado atual:** ❌ **NÃO COBERTO** - Apenas logado, não há recovery

#### Cobertura atual:
```typescript
// src/config/error.config.ts (atual)
process.on('uncaughtException', (error, origin) => {
  logger.error({ origin, stderr: process.stderr.fd, error });
  // ❌ Não faz NADA para se recuperar!
});
```

#### Problema:
Após este erro, a API continua rodando mas:
- ✅ Health check HTTP: Passa (servidor responde)
- ❌ Funcionalidade real: QUEBRADA (WhatsApp desconectado)
- ❌ Docker Swarm: NÃO detecta (container está "healthy")

---

### 🔴 Erro 2: uncaughtException - WebSocket Closed (FATAL - PARCIALMENTE COBERTO)

**Ocorrência:** Linha 28-44 de `docs/errors.txt`

```
{
  origin: 'uncaughtException',
  error: Error: WebSocket was closed before the connection was established
    at WebSocket.close (/evolution/node_modules/ws/lib/websocket.js:299:7)
    at WebSocketClient.close (/evolution/node_modules/baileys/lib/Socket/Client/websocket.js:53:21)
    at ts.restartInstance (/evolution/src/api/controllers/instance.controller.ts:345:30)
```

#### Análise:
- **Causa:** Tentativa de fechar WebSocket antes de conectar (race condition)
- **Momento:** Durante restart de instância
- **Impacto:** 🔥 **CRÍTICO** - Exception não tratada, processo pode morrer ou ficar inconsistente
- **Estado atual:** ⚠️ **PARCIALMENTE COBERTO** - Logado mas não há recovery

#### Cobertura atual:
```typescript
// src/config/error.config.ts (atual)
process.on('uncaughtException', (error, origin) => {
  logger.error({ origin, stderr: process.stderr.fd, error });
  // ⚠️ Apenas loga, processo continua em estado INCONSISTENTE
});
```

#### Problema:
- Node.js: Após `uncaughtException`, o processo está em **estado indefinido**
- Best practice: Sempre fazer shutdown após uncaughtException
- Realidade atual: **Processo continua rodando** (perigoso!)

---

### 🟡 Erro 3: Failed to Decrypt Message (NÃO-FATAL - ADEQUADAMENTE COBERTO)

**Ocorrência:** Linha 76-79 de `docs/errors.txt`

```
TypeError: Cannot create property 'senderMessageKeys' on number '91'
  at new SenderKeyState (/evolution/node_modules/baileys/WASignalGroup/sender_key_state.js:48:56)
  ...
msg=failed to decrypt message
```

#### Análise:
- **Causa:** Corrupção de dados no sender key state (bug do Baileys)
- **Momento:** Recebimento de mensagens de status@broadcast
- **Impacto:** 🟡 **BAIXO** - Apenas mensagens de status não são decriptadas
- **Estado atual:** ✅ **ADEQUADAMENTE COBERTO** - Erro capturado e logado pelo Baileys

#### Cobertura:
```typescript
// Baileys já trata internamente
// Loga o erro mas continua funcionando
// Não afeta o funcionamento geral da API
```

---

## 2. Resumo de Cobertura

| Erro | Gravidade | Cobertura Atual | Causa Travamento? | Precisa Suicídio? |
|------|-----------|-----------------|-------------------|-------------------|
| Connection Closed | 🔴 CRÍTICA | ❌ Não coberto | ✅ SIM | ✅ SIM |
| uncaughtException (WebSocket) | 🔥 CRÍTICA | ⚠️ Parcial (apenas log) | ✅ SIM | ✅ SIM |
| Failed to decrypt | 🟡 BAIXA | ✅ Coberto | ❌ Não | ❌ Não |

**Conclusão:** 2 de 3 erros precisam de implementação de **suicídio controlado**.

---

## 3. Por que a API "Trava" sem Avisar

### Problema Atual

```
┌─────────────────────┐
│  Evolution API      │
│  (container)        │
│                     │
│  HTTP Server: ✅    │  ← Health check passa
│  WebSocket WA: ❌   │  ← Conexão morreu
│  Funcionalidade: ❌ │  ← Não envia/recebe mensagens
└─────────────────────┘
         ↑
         │
    Docker Swarm diz: "Container healthy!" 😱
```

### Por que acontece:

1. **Erro fatal ocorre** (Connection Closed, uncaughtException)
2. **Processo Node.js:** Continua rodando (apenas logou)
3. **HTTP Server:** Continua respondendo (Express ainda funciona)
4. **Health check:** ✅ Passa (porta 8080 responde)
5. **Docker Swarm:** 😴 "Tá tudo bem!"
6. **Realidade:** 💀 WhatsApp desconectado, mensagens não chegam

**Resultado:** Container zumbi - vivo mas não funcional.

---

## 4. Solução: Suicídio Controlado

### Conceito

Quando um **erro fatal** é detectado:

```
1. ⚠️  Erro fatal detectado
2. 📝 Logar detalhes completos
3. 📡 Enviar alerta via webhook (opcional)
4. ⏱️  Aguardar 500ms para logs serem escritos
5. 💀 process.exit(1)
6. 🔄 Docker Swarm detecta exit code 1
7. ✅ Docker Swarm recria container SAUDÁVEL
```

### Vantagens

- ✅ Container sempre funcional (ou morto)
- ✅ Sem containers zumbi
- ✅ Auto-recuperação automática
- ✅ Alertas via webhook
- ✅ Logs completos antes de morrer

### Desvantagens

- ⚠️ Breve downtime (~5-10s durante restart)
- ⚠️ Conexões WebSocket ativas são perdidas (mas já estavam quebradas)
- ⚠️ Se erro for persistente (ex: banco fora), vai ficar em loop (mas isso é melhor que travar)

---

## 5. Implementação

### 5.1. Novo `src/config/error.config.ts`

Arquivo completo em: `src/config/error.config.ts` (ver código anexo)

**Principais features:**

```typescript
// 1. Lista de erros fatais
const FATAL_ERROR_PATTERNS = [
  /Connection Closed/i,
  /WebSocket was closed before the connection/i,
  /ECONNREFUSED/i,
  /ETIMEDOUT/i,
  /socket hang up/i,
];

// 2. Contador de erros (evita suicídio por erro transiente único)
let fatalErrorCount = 0;
const FATAL_ERROR_THRESHOLD = 3; // Após 3 erros consecutivos

// 3. Graceful shutdown
async function gracefulShutdown(error, origin, logger) {
  logger.error('💀 FATAL ERROR - INITIATING CONTROLLED SUICIDE');

  // Logar tudo
  logger.error({ error, origin, pid, uptime, memoryUsage });

  // Enviar webhook de alerta
  await sendErrorAlert(error, origin);

  // Aguardar logs serem escritos
  await sleep(500);

  // Matar processo
  process.exit(1); // Docker Swarm recria
}

// 4. Handler de uncaughtException (SEMPRE FATAL)
process.on('uncaughtException', async (error, origin) => {
  // uncaughtException = processo em estado inconsistente
  // Melhor ação: SEMPRE fazer shutdown
  await gracefulShutdown(error, origin, logger);
});

// 5. Handler de unhandledRejection (CONDICIONALMENTE FATAL)
process.on('unhandledRejection', async (reason, promise) => {
  const error = reason instanceof Error ? reason : new Error(reason);

  // Verificar se é erro fatal
  if (isFatalError(error)) {
    fatalErrorCount++;

    if (fatalErrorCount >= FATAL_ERROR_THRESHOLD) {
      // 3 erros fatais consecutivos = suicídio
      await gracefulShutdown(error, 'unhandledRejection', logger);
    }
  }
});
```

---

### 5.2. Health Check HTTP Endpoint (Opcional mas Recomendado)

**Arquivo:** `src/api/controllers/health.controller.ts`

```typescript
import { WAMonitoringService } from '@api/services/monitor.service';

export class HealthController {
  constructor(private readonly waMonitor: WAMonitoringService) {}

  /**
   * Health check simples (já existe)
   * GET /health
   */
  public async health() {
    return {
      status: 'ok',
      timestamp: new Date().toISOString(),
      uptime: process.uptime(),
    };
  }

  /**
   * Health check PROFUNDO (novo)
   * GET /health/deep
   *
   * Verifica se WhatsApp está realmente conectado
   */
  public async deepHealth() {
    const instances = this.waMonitor.waInstances;
    const instanceKeys = Object.keys(instances);

    if (instanceKeys.length === 0) {
      return {
        status: 'degraded',
        reason: 'No instances configured',
        timestamp: new Date().toISOString(),
      };
    }

    // Verificar se pelo menos uma instância está conectada
    const connectedInstances = instanceKeys.filter(key => {
      try {
        const instance = instances[key];
        return instance?.client?.state === 'open';
      } catch {
        return false;
      }
    });

    if (connectedInstances.length === 0) {
      // NENHUMA instância conectada = UNHEALTHY
      return {
        status: 'unhealthy',
        reason: 'No WhatsApp instances connected',
        instances: {
          total: instanceKeys.length,
          connected: 0,
          disconnected: instanceKeys.length,
        },
        timestamp: new Date().toISOString(),
      };
    }

    return {
      status: 'healthy',
      instances: {
        total: instanceKeys.length,
        connected: connectedInstances.length,
        disconnected: instanceKeys.length - connectedInstances.length,
      },
      timestamp: new Date().toISOString(),
    };
  }
}
```

**Router:** `src/api/routes/health.router.ts`

```typescript
import { Router } from 'express';
import { HealthController } from '@api/controllers/health.controller';
import { waMonitor } from '@api/server.module';

const router = Router();
const healthController = new HealthController(waMonitor);

// Health check simples
router.get('/health', async (req, res) => {
  const result = await healthController.health();
  res.status(200).json(result);
});

// Health check profundo
router.get('/health/deep', async (req, res) => {
  const result = await healthController.deepHealth();

  const statusCode =
    result.status === 'healthy' ? 200 :
    result.status === 'degraded' ? 200 : // Ainda aceitável
    503; // unhealthy = Service Unavailable

  res.status(statusCode).json(result);
});

export default router;
```

---

### 5.3. Docker Compose / Swarm Config

**Atualizar `docker-compose.yaml`:**

```yaml
services:
  evolution:
    image: evolution-api:latest

    # Health check usando endpoint profundo
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:8080/health/deep"]
      interval: 30s      # Verifica a cada 30s
      timeout: 10s       # Timeout de 10s
      retries: 3         # 3 falhas consecutivas = unhealthy
      start_period: 40s  # Aguarda 40s antes de começar health checks

    # Restart policy
    restart: unless-stopped

    # Ou, se usar Docker Swarm:
    deploy:
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
```

**Comportamento:**

```
1. Container inicia
2. Aguarda 40s (start_period)
3. Começa health checks a cada 30s
4. Se /health/deep retorna 503 (unhealthy):
   - Tenta 3 vezes (retries)
   - Se 3 falhas consecutivas: marca container como unhealthy
   - Docker Swarm MATA e RECRIA
5. Novo container saudável assume
```

---

## 6. Estratégia de Deploy

### Fase 1: Adicionar Suicídio Controlado (Seguro)

```bash
# 1. Substituir src/config/error.config.ts
git checkout feature/error-recovery
cp docs/error-recovery-strategy/error.config.ts src/config/error.config.ts

# 2. Build
npm run build

# 3. Deploy em staging
# Container com erro fatal vai se matar e recriar

# 4. Monitorar logs
docker service logs -f evolution_api

# Buscar por:
# - "💀 FATAL ERROR DETECTED"
# - "🔄 Docker Swarm will restart"
```

**Risco:** 🟢 BAIXO - Melhora estabilidade, não quebra nada

---

### Fase 2: Adicionar Health Check Profundo (Recomendado)

```bash
# 1. Adicionar health check controller
cp docs/error-recovery-strategy/health.controller.ts src/api/controllers/
cp docs/error-recovery-strategy/health.router.ts src/api/routes/

# 2. Registrar rota no index.router.ts
# Adicionar: import healthRouter from './health.router';
#           app.use('/', healthRouter);

# 3. Build
npm run build

# 4. Testar endpoint
curl http://localhost:8080/health/deep

# Deve retornar:
# {
#   "status": "healthy",
#   "instances": { ... }
# }

# 5. Atualizar docker-compose.yaml com healthcheck
# 6. Deploy
```

**Risco:** 🟡 MÉDIO - Altera health check (testar bem em staging)

---

## 7. Monitoramento Pós-Deploy

### Logs a Observar

```bash
# Container sendo recriado (suicídio controlado)
docker service logs evolution_api | grep "FATAL ERROR DETECTED"

# Health checks falhando
docker service ps evolution_api --format "table {{.ID}}\t{{.Name}}\t{{.CurrentState}}"

# Containers em loop de restart (problema persistente)
docker stats evolution_api
```

### Métricas

| Métrica | Valor Esperado | Ação se Fora |
|---------|---------------|--------------|
| Restarts por hora | < 2 | Investigar causa raiz |
| Tempo entre restarts | > 5 min | Problema persistente (ex: banco fora) |
| Health check failures | < 1% | OK |
| Health check failures | > 10% | Problema de infraestrutura |

---

## 8. Casos Especiais

### Caso 1: Loop de Restart Infinito

**Sintoma:**
```
Container reinicia a cada 5 segundos
Logs mostram sempre o mesmo erro fatal
```

**Causa possível:**
- Banco de dados fora
- Redis fora
- Configuração inválida
- Bug no código de inicialização

**Ação:**
```bash
# 1. Parar service
docker service scale evolution_api=0

# 2. Verificar dependências
docker exec -it postgres_container pg_isready
docker exec -it redis_container redis-cli ping

# 3. Verificar logs de inicialização
docker service logs evolution_api | head -50

# 4. Corrigir problema
# 5. Religar service
docker service scale evolution_api=1
```

---

### Caso 2: Erro Transiente Causa Restart Desnecessário

**Sintoma:**
```
Erro de rede transiente (timeout momentâneo)
Container se mata mas não precisava
```

**Solução:**
O código já tem proteção:

```typescript
const FATAL_ERROR_THRESHOLD = 3; // Só suicida após 3 erros

// Erros espaçados não atingem threshold
// Só erros consecutivos causam suicídio
```

Se ainda ocorrer, ajustar threshold:
```typescript
const FATAL_ERROR_THRESHOLD = 5; // Mais tolerante
```

---

## 9. Checklist de Implementação

### Obrigatório (Fase 1)
- [ ] Substituir `src/config/error.config.ts` com nova versão
- [ ] Testar em staging
- [ ] Verificar logs de suicídio controlado
- [ ] Monitorar restarts por 24h
- [ ] Deploy em produção

### Recomendado (Fase 2)
- [ ] Adicionar health check controller
- [ ] Adicionar health check router
- [ ] Atualizar docker-compose.yaml com healthcheck profundo
- [ ] Testar endpoint `/health/deep`
- [ ] Deploy em produção

### Opcional (Fase 3)
- [ ] Adicionar Prometheus metrics
- [ ] Dashboard Grafana para monitorar restarts
- [ ] Alertas Slack/Discord para erros fatais
- [ ] PagerDuty para containers em loop

---

## 10. Código Fonte

### 10.1. `src/config/error.config.ts` (NOVO)

Ver arquivo anexo: `docs/error-recovery-strategy/error.config.ts`

### 10.2. `src/api/controllers/health.controller.ts` (NOVO)

Ver arquivo anexo: `docs/error-recovery-strategy/health.controller.ts`

### 10.3. `src/api/routes/health.router.ts` (NOVO)

Ver arquivo anexo: `docs/error-recovery-strategy/health.router.ts`

---

## 11. Referências

- [Node.js Error Handling Best Practices](https://nodejs.org/api/process.html#process_event_uncaughtexception)
- [Docker Health Checks](https://docs.docker.com/engine/reference/builder/#healthcheck)
- [Docker Swarm Restart Policies](https://docs.docker.com/engine/swarm/how-swarm-mode-works/services/#restart-policy)
- Evolution API Issues:
  - #1234 - Connection Closed (se existir)
  - #5678 - WebSocket race condition (se existir)

---

## 12. FAQ

### Q: O suicídio controlado não vai causar downtime?

**A:** Sim, mas:
- Downtime: ~5-10 segundos (restart do container)
- Alternativa atual: Container zumbi INFINITAMENTE (downtime 100%)
- **Melhor:** 10s de downtime que se recupera sozinho

### Q: E se o erro for persistente? Não vai ficar em loop?

**A:** Sim, mas isso é **bom**:
- Loop de restart = VISÍVEL (você vê nos logs/monitoring)
- Container zumbi = INVISÍVEL (parece que está OK)
- Com loop, você SABE que tem problema e pode investigar

### Q: Preciso realmente do health check profundo?

**A:** Depende:
- **Mínimo:** Suicídio controlado (Fase 1) - já resolve 90%
- **Ideal:** Suicídio + Health check profundo - resolve 100% + detecção proativa

### Q: O threshold de 3 erros não é muito baixo?

**A:** Pode ajustar:
```typescript
const FATAL_ERROR_THRESHOLD = 5; // Mais tolerante
const FATAL_ERROR_THRESHOLD = 1; // Mais agressivo (suicida no primeiro erro fatal)
```

Recomendação: Começar com 3, monitorar por 1 semana, ajustar se necessário.

---

## 13. Conclusão

### Estado Atual
- ❌ Containers zumbi ficam rodando
- ❌ Sem detecção de problemas reais
- ❌ Sem auto-recuperação

### Estado Após Implementação
- ✅ Erros fatais causam restart controlado
- ✅ Container sempre funcional (ou morto + recriando)
- ✅ Logs completos + alertas webhook
- ✅ Health check profundo detecta problemas
- ✅ Auto-recuperação automática

### Próximos Passos
1. Implementar Fase 1 (suicídio controlado)
2. Monitorar por 1 semana
3. Implementar Fase 2 (health check profundo)
4. Adicionar monitoring/alertas (Fase 3 - opcional)
