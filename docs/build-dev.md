# Build e Deploy - Ambiente de Desenvolvimento

**Data:** 2025-10-03
**Versão:** custom-2.3.4-0
**Plataforma:** Podman (Windows/Linux)

---

## 📋 Pré-requisitos

- ✅ Podman instalado
- ✅ Acesso ao servidor 192.168.100.154 (PostgreSQL + Redis)
- ✅ Credenciais do banco de dados
- ✅ Git configurado

---

## 🗄️ Infraestrutura Externa

### PostgreSQL (192.168.100.154:5432)
```
Host: 192.168.100.154
Porta: 5432
Usuário: desenv
Senha: Desenv*123
Database: zyra_9232
```

### Redis (192.168.100.154:6379)
```
Host: 192.168.100.154
Porta: 6379
Sem senha (assumindo configuração atual)
```

---

## 🔧 Configuração Inicial

### 1. Criar arquivo .env na raiz do projeto

```bash
# Copiar do template
cp docs/.env.example .env

# Editar com as configurações de desenvolvimento
nano .env
```

### 2. Configurar variáveis essenciais no `.env`

```bash
# ============================================
# SERVIDOR E API
# ============================================
SERVER_NAME=evolution-dev
SERVER_TYPE=http
SERVER_PORT=8080
SERVER_URL=http://localhost:8080

# Desabilitar SSL em dev
SSL_CONF_PRIVKEY=
SSL_CONF_FULLCHAIN=

# ============================================
# AUTENTICAÇÃO
# ============================================
# Gerar uma nova chave para dev (substitua por uma segura)
AUTHENTICATION_API_KEY=dev_$(openssl rand -hex 16)

# ============================================
# DATABASE - PostgreSQL Externo
# ============================================
DATABASE_PROVIDER=postgresql
DATABASE_CONNECTION_URI=postgresql://desenv:Desenv*123@192.168.100.154:5432/zyra_9232?schema=evolution_api
DATABASE_CONNECTION_CLIENT_NAME=evolution_dev

# Salvar dados no banco
DATABASE_SAVE_DATA_INSTANCE=true
DATABASE_SAVE_DATA_NEW_MESSAGE=true
DATABASE_SAVE_DATA_MESSAGE_UPDATE=true
DATABASE_SAVE_DATA_CONTACTS=true
DATABASE_SAVE_DATA_CHATS=true

# ============================================
# REDIS - Cache Externo
# ============================================
CACHE_REDIS_ENABLED=true
CACHE_REDIS_URI=redis://192.168.100.154:6379
CACHE_REDIS_PREFIX_KEY=evolution_dev
CACHE_REDIS_SAVE_INSTANCES=false

# ============================================
# LOGS
# ============================================
LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE
LOG_COLOR=true
LOG_BAILEYS=error

# ============================================
# ERROR RECOVERY
# ============================================
EXIT_ON_FATAL=true
FATAL_ERROR_THRESHOLD=3

# ============================================
# EVENTOS (desabilitar em dev para simplificar)
# ============================================
RABBITMQ_ENABLED=false
KAFKA_ENABLED=false
WEBSOCKET_ENABLED=false

# ============================================
# S3 (se necessário - deixar desabilitado em dev)
# ============================================
S3_ENABLED=false

# ============================================
# CHATWOOT (se necessário)
# ============================================
CHATWOOT_ENABLED=false
# Se precisar importar histórico:
# CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=postgresql://postgres:senha@192.168.100.154:5432/chatwoot?sslmode=disable

# ============================================
# MÉTRICAS E TELEMETRIA
# ============================================
PROMETHEUS_METRICS=false
TELEMETRY_ENABLED=false

# ============================================
# CORS (abrir para dev local)
# ============================================
CORS_ORIGIN=*
CORS_METHODS=GET,POST,PUT,DELETE
CORS_CREDENTIALS=true

# ============================================
# INSTÂNCIAS
# ============================================
DEL_INSTANCE=false
```

---

## 🐳 Docker Compose para Desenvolvimento

### Criar `docker-compose.dev.yaml`

Como Redis e PostgreSQL são externos, simplificamos o compose:

```yaml
version: "3.8"

services:
  evolution-api:
    container_name: evolution_dev
    image: evolution-api:dev
    restart: unless-stopped
    ports:
      - "8080:8080"
    volumes:
      - ./instances:/evolution/instances
      - ./logs:/evolution/logs
    env_file:
      - .env
    networks:
      - evolution-dev-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

networks:
  evolution-dev-net:
    name: evolution-dev-net
    driver: bridge

volumes:
  instances:
    driver: local
  logs:
    driver: local
```

**Salvar como:** `docker-compose.dev.yaml`

---

## 🏗️ Build da Imagem

### Opção 1: Build Direto (Linux/Mac)

```bash
# 1. Buildar imagem
podman build -t evolution-api:dev -f Dockerfile .

# 2. Verificar imagem criada
podman images | grep evolution-api

# 3. Subir container
podman-compose -f docker-compose.dev.yaml up -d

# 4. Ver logs
podman logs -f evolution_dev
```

### Opção 2: Build com PowerShell (Windows)

Criar script `BuildDev.ps1` na raiz:

```powershell
# BuildDev.ps1 - Build para ambiente de desenvolvimento
$ErrorActionPreference = "Stop"

Write-Host "🚀 Building Evolution API - Development" -ForegroundColor Cyan

# 1. Verificar se .env existe
if (-Not (Test-Path ".env")) {
    Write-Host "❌ Arquivo .env não encontrado!" -ForegroundColor Red
    Write-Host "📝 Copie docs/.env.example para .env e configure" -ForegroundColor Yellow
    exit 1
}

# 2. Build da imagem
Write-Host "🔨 Building Docker image..." -ForegroundColor Yellow
podman build -t evolution-api:dev -f Dockerfile .

if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ Build falhou!" -ForegroundColor Red
    exit 1
}

# 3. Verificar imagem
Write-Host "✅ Imagem criada com sucesso!" -ForegroundColor Green
podman images | Select-String "evolution-api"

# 4. Perguntar se quer subir o container
$resposta = Read-Host "Deseja subir o container agora? (S/N)"
if ($resposta -eq "S" -or $resposta -eq "s") {
    Write-Host "🚀 Subindo container..." -ForegroundColor Yellow
    podman-compose -f docker-compose.dev.yaml up -d

    Write-Host "📊 Status dos containers:" -ForegroundColor Cyan
    podman ps | Select-String "evolution"

    Write-Host ""
    Write-Host "✅ Container rodando!" -ForegroundColor Green
    Write-Host "📝 Ver logs: podman logs -f evolution_dev" -ForegroundColor Yellow
    Write-Host "🌐 API: http://localhost:8080" -ForegroundColor Cyan
}

Write-Host ""
Write-Host "✨ Build concluído!" -ForegroundColor Green
```

**Executar:**
```powershell
.\BuildDev.ps1
```

### Opção 3: Build Manual (Passo a Passo)

```bash
# 1. Limpar builds anteriores (opcional)
podman rmi evolution-api:dev 2>/dev/null || true

# 2. Build
podman build \
  --tag evolution-api:dev \
  --label "version=custom-2.3.4-0" \
  --label "environment=development" \
  --file Dockerfile \
  .

# 3. Verificar sucesso
if [ $? -eq 0 ]; then
    echo "✅ Build concluído com sucesso!"
else
    echo "❌ Build falhou!"
    exit 1
fi
```

---

## 🚀 Deploy e Testes

### 1. Testar conexão com PostgreSQL

Antes de subir a API, verificar conectividade:

```bash
# Usando psql (se instalado)
psql -h 192.168.100.154 -U desenv -d zyra_9232 -c "\dt"

# Ou usando container temporário
podman run --rm -it postgres:15 \
  psql -h 192.168.100.154 -U desenv -d zyra_9232 -c "\dt"
```

**Senha:** `Desenv*123`

### 2. Testar conexão com Redis

```bash
# Usando redis-cli (se instalado)
redis-cli -h 192.168.100.154 -p 6379 ping

# Ou usando container temporário
podman run --rm -it redis:latest \
  redis-cli -h 192.168.100.154 -p 6379 ping
```

Deve retornar: `PONG`

### 3. Subir a API

```bash
# Com docker-compose
podman-compose -f docker-compose.dev.yaml up -d

# Ou manualmente
podman run -d \
  --name evolution_dev \
  -p 8080:8080 \
  --env-file .env \
  -v $(pwd)/instances:/evolution/instances \
  evolution-api:dev
```

### 4. Verificar logs de inicialização

```bash
# Logs em tempo real
podman logs -f evolution_dev

# Últimas 100 linhas
podman logs --tail 100 evolution_dev
```

**Procurar por:**
- ✅ `Database connection established`
- ✅ `Redis cache connected`
- ✅ `Server listening on port 8080`
- ❌ Erros de conexão

### 5. Testar API

```bash
# Health check
curl http://localhost:8080/health

# Manager (UI)
# Abrir no navegador: http://localhost:8080/manager

# Criar instância de teste (substituir API_KEY)
curl -X POST http://localhost:8080/instance/create \
  -H "apikey: sua_api_key_aqui" \
  -H "Content-Type: application/json" \
  -d '{
    "instanceName": "teste_dev",
    "qrcode": true
  }'
```

---

## 🔧 Comandos Úteis

### Gerenciar Container

```bash
# Ver status
podman ps | grep evolution

# Parar
podman stop evolution_dev

# Iniciar
podman start evolution_dev

# Reiniciar
podman restart evolution_dev

# Remover
podman rm -f evolution_dev

# Ver uso de recursos
podman stats evolution_dev
```

### Logs e Debug

```bash
# Logs completos
podman logs evolution_dev

# Últimas linhas
podman logs --tail 50 evolution_dev

# Logs em tempo real com filtro
podman logs -f evolution_dev | grep ERROR

# Entrar no container
podman exec -it evolution_dev /bin/bash

# Verificar variáveis de ambiente
podman exec evolution_dev env | grep DATABASE
```

### Rebuild Rápido

```bash
# 1. Parar e remover container
podman rm -f evolution_dev

# 2. Rebuild imagem
podman build -t evolution-api:dev .

# 3. Subir novamente
podman-compose -f docker-compose.dev.yaml up -d
```

### Limpar tudo

```bash
# Parar containers
podman-compose -f docker-compose.dev.yaml down

# Remover imagem
podman rmi evolution-api:dev

# Limpar volumes (CUIDADO: apaga instâncias)
podman volume rm evolution-dev_instances evolution-dev_logs
```

---

## 🐛 Troubleshooting

### 1. Erro: "Cannot connect to database"

**Sintoma:**
```
Error: connect ECONNREFUSED 192.168.100.154:5432
```

**Soluções:**
1. Verificar firewall do servidor 192.168.100.154
   ```bash
   # No servidor PostgreSQL
   sudo ufw allow from <seu_ip> to any port 5432
   ```

2. Verificar `pg_hba.conf` permite conexões externas
   ```bash
   # No servidor PostgreSQL
   sudo nano /etc/postgresql/15/main/pg_hba.conf
   # Adicionar:
   host    all             all             0.0.0.0/0               md5
   ```

3. Verificar `postgresql.conf`
   ```bash
   # No servidor PostgreSQL
   sudo nano /etc/postgresql/15/main/postgresql.conf
   # Verificar:
   listen_addresses = '*'
   ```

4. Reiniciar PostgreSQL
   ```bash
   sudo systemctl restart postgresql
   ```

### 2. Erro: "Cannot connect to Redis"

**Sintoma:**
```
Error: connect ECONNREFUSED 192.168.100.154:6379
```

**Soluções:**
1. Verificar se Redis está rodando
   ```bash
   # No servidor Redis
   systemctl status redis
   ```

2. Verificar bind address
   ```bash
   # No servidor Redis
   sudo nano /etc/redis/redis.conf
   # Comentar ou alterar:
   bind 0.0.0.0
   protected-mode no
   ```

3. Reiniciar Redis
   ```bash
   sudo systemctl restart redis
   ```

### 3. Build falha com erro de memória

**Solução:**
```bash
# Aumentar limite de memória do Podman
podman build --memory=4g -t evolution-api:dev .
```

### 4. Container inicia e para imediatamente

**Debug:**
```bash
# Ver logs completos
podman logs evolution_dev

# Verificar se processo está rodando
podman top evolution_dev

# Verificar health check
podman inspect evolution_dev | grep -A 10 Health
```

### 5. Porta 8080 já em uso

**Solução:**
```bash
# Encontrar processo usando porta 8080
lsof -i :8080
# ou
netstat -tulpn | grep 8080

# Matar processo
kill -9 <PID>

# Ou usar porta diferente no .env
SERVER_PORT=8081
```

---

## 📊 Checklist de Deploy Dev

### Pré-Deploy
- [ ] `.env` criado e configurado
- [ ] Conexão PostgreSQL testada
- [ ] Conexão Redis testada
- [ ] Firewall liberado (se necessário)
- [ ] `docker-compose.dev.yaml` criado

### Build
- [ ] `podman build` executado com sucesso
- [ ] Imagem `evolution-api:dev` criada
- [ ] Sem erros no build

### Deploy
- [ ] Container iniciado
- [ ] Logs não mostram erros fatais
- [ ] Health check passa
- [ ] API responde em http://localhost:8080

### Validação
- [ ] Manager acessível
- [ ] Criar instância de teste funciona
- [ ] QR Code é gerado
- [ ] Mensagens são salvas no banco
- [ ] Cache Redis funciona

---

## 🎯 Próximos Passos

Após deploy dev funcionando:

1. **Testar customizações implementadas:**
   - SimpleMutex no whatsappNumber
   - Error recovery (forçar erro fatal)
   - Import Chatwoot com números BR
   - Upload de mídia (se S3 habilitado)

2. **Monitorar recursos:**
   ```bash
   podman stats evolution_dev
   ```

3. **Backup antes de testes destrutivos:**
   ```bash
   # Backup de instâncias
   tar -czf instances_backup.tar.gz instances/
   ```

4. **Preparar para staging:**
   - Documentar diferenças dev vs staging
   - Criar pipeline de CI/CD (se necessário)
   - Configurar variáveis de ambiente staging

---

## 📝 Notas Importantes

- ⚠️ **Nunca use credenciais de produção em dev**
- ⚠️ **Database `zyra_9232` é compartilhado** - tome cuidado com testes destrutivos
- ⚠️ **Redis também é compartilhado** - use `CACHE_REDIS_PREFIX_KEY=evolution_dev`
- 🔒 **Gere nova `AUTHENTICATION_API_KEY` para dev**
- 📊 **Monitore consumo de recursos** do servidor 192.168.100.154

---

## 🆘 Suporte

Se encontrar problemas:

1. Verificar logs: `podman logs -f evolution_dev`
2. Verificar conectividade de rede
3. Verificar docs de migração: `docs/migracao-passo-a-passo.md`
4. Revisar customizações: `docs/pending-fix.md`

**Arquivos de referência:**
- `docs/.env.example` - Configurações de produção
- `docs/migracao-config.md` - Customizações aplicadas
- `docs/evolution-upgrade-claude.md` - Análise técnica da migração
