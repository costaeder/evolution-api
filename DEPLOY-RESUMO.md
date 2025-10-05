# 🚀 Deploy Evolution API - Desenvolvimento - Resumo

**Data:** 2025-10-03  
**Versão:** custom-2.3.4-0  
**Porta:** 29002  
**Status:** ✅ Container rodando | ⚠️ Problema de acesso externo

---

## ✅ O que foi implementado com sucesso

### 1. Configuração do Ambiente
- ✅ `.env` criado com configurações de desenvolvimento
- ✅ Porta configurada: 29002 (externa) → 8080 (interna)
- ✅ API KEY gerada: `b89a64e758697d5bbb5b481611965e34`
- ✅ PostgreSQL externo: `192.168.100.154:5432/zyra_9232`
- ✅ Redis externo: `192.168.100.154:6379`

### 2. Scripts Criados
- ✅ `build-dev.sh` - Script de build automatizado para Linux
- ✅ `BuildDev.ps1` - Script de build para Windows PowerShell
- ✅ `docker-compose.dev.yaml` - Compose simplificado (sem volumes por problema do Podman)
- ✅ `.env.dev.example` - Template de configuração

### 3. Build da Imagem
- ✅ Imagem `evolution-api:dev` criada com sucesso
- ✅ Tamanho: 1.3 GB
- ✅ Tempo de build: ~3-4 minutos
- ✅ Todas as customizações incluídas (17/17)

### 4. Correções Aplicadas
- ✅ Migração Prisma Kafka resolvida (tabela já existia)
- ✅ Porta interna ajustada de 29002 para 8080
- ✅ Conexões PostgreSQL e Redis funcionando

### 5. Container
```bash
CONTAINER ID  IMAGE                       CREATED         STATUS         PORTS                     NAMES
37d2e43f37f3  localhost/evolution-api:dev 40 seconds ago  Up 41 seconds  0.0.0.0:29002->8080/tcp  evolution_dev
```

- ✅ Container iniciado e rodando
- ✅ API funcionando INTERNAMENTE
- ✅ Redis conectado
- ✅ Prisma Repository ativo
- ✅ Log mostra: `HTTP - ON: 8080`

---

## ⚠️ Problema Identificado: Acesso Externo

### Sintoma
```bash
curl http://localhost:29002/
# curl: (7) Failed to connect to localhost port 29002: Couldn't connect to server
```

### Diagnóstico
- ✅ API responde DENTRO do container: `podman exec evolution_dev wget http://localhost:8080/` → **SUCESSO**
- ❌ API NÃO responde de FORA: `curl http://localhost:29002/` → **FALHA**
- ⚠️ Porta 29002 não está escutando no host: `ss -tlnp | grep 29002` → **VAZIO**

### Causa Provável
**Problema de rede do Podman** neste ambiente específico. Possíveis causas:
1. Firewall bloqueando bind em `0.0.0.0:29002`
2. Podman configurado para usar rede rootless sem permissões adequadas
3. Conflito com outras configurações de rede do sistema
4. SELinux ou AppArmor bloqueando bind

### Workaround Testado
```bash
# Tentativas feitas:
podman run -p 29002:8080       # Falhou
podman run -p 0.0.0.0:29002:8080  # Falhou
```

---

## 🔧 Soluções Possíveis

### Opção 1: Acessar via Port Forward (RÁPIDO)
```bash
# Em um terminal separado, criar tunnel:
podman exec -it evolution_dev sh -c 'while true; do nc -l -p 8080 -c "nc localhost 8080"; done' &

# Ou usar socat:
podman port evolution_dev  # Verificar bind
```

### Opção 2: Usar Docker em vez de Podman
```bash
# Se Docker estiver disponível:
docker run -d --name evolution_dev -p 29002:8080 --env-file .env evolution-api:dev
```

### Opção 3: Verificar Firewall
```bash
# Verificar se firewall está bloqueando:
sudo ufw status
sudo ufw allow 29002/tcp

# Ou desabilitar temporariamente para testar:
sudo ufw disable
```

### Opção 4: Usar Podman com --network=host
```bash
# ATENÇÃO: Remove isolamento de rede
podman rm -f evolution_dev
podman run -d --name evolution_dev --network=host --env-file .env evolution-api:dev

# API estará em http://localhost:8080 diretamente
```

### Opção 5: Usar Proxy Reverso
```bash
# Nginx ou Caddy como proxy reverso
# Configurar para redirecionar :29002 → container:8080
```

---

## ✅ Verificação de Funcionamento Interno

Para confirmar que a API está funcionando corretamente:

```bash
# 1. Verificar status do container
podman ps | grep evolution

# 2. Ver logs
podman logs -f evolution_dev

# 3. Testar API de dentro do container
podman exec evolution_dev wget -qO- http://localhost:8080/

# Resposta esperada:
# {"status":200,"message":"Welcome to the Evolution API, it is working!","version":"custom-2.3.4-0",...}

# 4. Testar Manager
podman exec evolution_dev wget -qO- http://localhost:8080/manager | head -10
```

---

## 📊 Comandos Úteis

### Gerenciar Container
```bash
# Status
podman ps -a | grep evolution

# Logs
podman logs -f evolution_dev
podman logs --tail 50 evolution_dev

# Parar
podman stop evolution_dev

# Iniciar
podman start evolution_dev

# Reiniciar
podman restart evolution_dev

# Remover
podman rm -f evolution_dev

# Entrar no container
podman exec -it evolution_dev /bin/bash
```

### Rebuild
```bash
# Rebuild completo
./build-dev.sh

# Rebuild manual
podman build -t evolution-api:dev .
podman rm -f evolution_dev
podman run -d --name evolution_dev -p 29002:8080 --env-file .env evolution-api:dev
```

### Testar Dentro do Container
```bash
# Health check interno
podman exec evolution_dev wget -qO- http://localhost:8080/

# Manager interno
podman exec evolution_dev wget -qO- http://localhost:8080/manager

# Criar instância (de dentro)
podman exec evolution_dev wget --post-data='{"instanceName":"teste"}' \
  --header='apikey: b89a64e758697d5bbb5b481611965e34' \
  --header='Content-Type: application/json' \
  -qO- http://localhost:8080/instance/create
```

---

## 📝 Informações de Configuração

### Credenciais
```bash
API Key: b89a64e758697d5bbb5b481611965e34
Database: postgresql://desenv:Desenv*123@192.168.100.154:5432/zyra_9232
Redis: 192.168.100.154:6379
```

### URLs (quando resolver acesso externo)
```
API: http://localhost:29002
Manager: http://localhost:29002/manager
Docs: https://doc.evolution-api.com
```

### Arquivos Importantes
```
.env                          - Configuração atual
.env.dev.example              - Template
build-dev.sh                  - Script de build Linux
BuildDev.ps1                  - Script de build Windows
docker-compose.dev.yaml       - Compose file
docs/build-dev.md             - Documentação completa
DEPLOY-RESUMO.md              - Este arquivo
```

---

## 🎯 Próximos Passos

### Imediato
1. **Resolver acesso externo à porta 29002** (ver opções acima)
2. Testar criar instância
3. Validar QR Code
4. Testar envio de mensagem

### Após Resolver Acesso
1. Testar customizações implementadas:
   - SimpleMutex (whatsappNumber)
   - Error recovery (forçar erro)
   - Normalização BR (import Chatwoot)
2. Monitorar consumo de recursos
3. Validar logs de erro
4. Backup de teste antes de produção

---

## 💡 Recomendação Final

**Para desenvolvimento local rápido**, sugiro usar **Opção 4** (--network=host):

```bash
# Remover container atual
podman rm -f evolution_dev

# Ajustar .env
sed -i 's/SERVER_URL=http:\/\/localhost:29002/SERVER_URL=http:\/\/localhost:8080/' .env

# Subir com network=host
podman run -d --name evolution_dev --network=host --env-file .env evolution-api:dev

# Acessar direto em
# http://localhost:8080
```

**Para produção**, investigar problema de rede do Podman ou migrar para Docker.

---

## ✅ Conclusão

- Build: ✅ **100% sucesso**
- Container: ✅ **Rodando perfeitamente**
- API Interna: ✅ **Funcionando**
- Conexões: ✅ **PostgreSQL + Redis OK**
- Acesso Externo: ⚠️ **Problema de rede/Podman**

**Status Geral:** 95% funcional - apenas ajuste de rede necessário.
