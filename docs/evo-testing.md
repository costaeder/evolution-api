# Evolution API - Guia de Testes

**Versão:** custom-2.3.4-0
**Ambiente:** Desenvolvimento
**Data:** 2025-10-03

---

## 📋 Informações de Acesso

### API Evolution
```bash
# Acesso externo (navegador/apps)
URL: http://192.168.100.154:27002
Manager: http://192.168.100.154:27002/manager
API Key: b89a64e758697d5bbb5b481611965e34

# Acesso interno (dentro da rede iadev-shared-net)
URL: http://evolution_dev:8080
```

### Instância Ativa
```
Nome: Zyra9232
ID: e4248a38-a1a7-41a6-bbdc-835c72ab3994
Número: 5511980549232
Status: open
```

### Dados de Teste
```bash
# Grupo de teste
GROUP_ID="120363405010325191@g.us"
GROUP_NAME="Grupo de teste"

# Contatos de teste (use apenas para testes controlados)
CONTACT_1="554399833034@s.whatsapp.net"  # elizabethferpenha
CONTACT_2="554199243740@s.whatsapp.net"  # Letícia Machado
```

---

## 🔍 Testes Básicos

### 1. Verificar Status da API

```bash
# Teste de conectividade
curl -s http://192.168.100.154:27002/ | jq .

# Resposta esperada:
# {
#   "status": 200,
#   "message": "Welcome to the Evolution API, it is working!",
#   "version": "custom-2.3.4-0"
# }
```

### 2. Listar Instâncias

```bash
curl -s http://192.168.100.154:27002/instance/fetchInstances \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" | jq '.[0] | {name, connectionStatus, number}'

# Resposta esperada:
# {
#   "name": "Zyra9232",
#   "connectionStatus": "open",
#   "number": "11980549232"
# }
```

### 3. Verificar Estado da Conexão

```bash
curl -s http://192.168.100.154:27002/instance/connectionState/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" | jq .

# Resposta esperada:
# {
#   "instance": {
#     "instanceName": "Zyra9232",
#     "state": "open"
#   }
# }
```

---

## 📤 Testes de Envio de Mensagens

### 1. Enviar Mensagem de Texto (Contato)

```bash
curl -X POST http://192.168.100.154:27002/message/sendText/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" \
  --header "Content-Type: application/json" \
  --data '{
    "number": "554199243740",
    "text": "🤖 Teste Evolution API - custom-2.3.4-0\nMensagem enviada via API\nData: 2025-10-03"
  }' | jq .
```

### 2. Enviar Mensagem para Grupo

```bash
curl -X POST http://192.168.100.154:27002/message/sendText/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" \
  --header "Content-Type: application/json" \
  --data '{
    "number": "120363405010325191",
    "text": "🧪 Teste de mensagem para grupo\nEvolution API v2.3.4\nTeste automatizado"
  }' | jq .
```

### 3. Enviar Imagem

```bash
# Criar imagem de teste base64
echo "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" > /tmp/test.b64

curl -X POST http://192.168.100.154:27002/message/sendMedia/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" \
  --header "Content-Type: application/json" \
  --data '{
    "number": "554199243740",
    "mediatype": "image",
    "mimetype": "image/png",
    "caption": "🖼️ Teste de envio de imagem",
    "media": "https://via.placeholder.com/150"
  }' | jq .
```

### 4. Verificar Mensagens Recebidas

```bash
curl -s http://192.168.100.154:27002/chat/findMessages/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" \
  --header "Content-Type: application/json" \
  --data '{
    "where": {
      "key": {
        "remoteJid": "554199243740@s.whatsapp.net"
      }
    },
    "limit": 5
  }' | jq '.[] | {message: .message.conversation, timestamp}'
```

---

## 🧪 Testes de Customizações

### 1. Teste SimpleMutex (whatsappNumbers)

**Objetivo:** Verificar se chamadas simultâneas não causam race conditions

```bash
#!/bin/bash
# test-simplemutex.sh

API_URL="http://192.168.100.154:27002"
API_KEY="b89a64e758697d5bbb5b481611965e34"
INSTANCE="Zyra9232"

echo "🔒 Testando SimpleMutex com 5 chamadas simultâneas..."

for i in {1..5}; do
  curl -X POST "$API_URL/chat/whatsappNumbers/$INSTANCE" \
    -H "apikey: $API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"numbers": ["5511999999999", "5521888888888"]}' &
done

wait

echo ""
echo "✅ Verificar logs para confirmar SimpleMutex:"
echo "podman logs --tail 50 evolution_dev | grep -i mutex"
```

**Verificar nos logs:**
```bash
podman logs --tail 100 evolution_dev | grep -iE "(mutex|acquiring|releasing)"
```

### 2. Teste Error Recovery (Controlled Suicide)

**Objetivo:** Verificar se a API se recupera de erros fatais

```bash
# Monitorar contador de erros fatais
podman logs -f evolution_dev | grep -iE "(fatal|error count|threshold)"

# Em outra janela, forçar cenários de erro (opcional)
# Verificar se após 3 erros fatais o processo reinicia
```

**Configuração atual:**
```bash
EXIT_ON_FATAL=true
FATAL_ERROR_THRESHOLD=3
```

### 3. Teste Cache TTL Defaults

**Objetivo:** Verificar se cache está funcionando corretamente

```bash
# Fazer mesma requisição 2x seguidas e verificar tempo de resposta
time curl -s http://192.168.100.154:27002/instance/fetchInstances \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" > /dev/null

time curl -s http://192.168.100.154:27002/instance/fetchInstances \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" > /dev/null

# Segunda chamada deve ser mais rápida (cache hit)
```

### 4. Teste Normalização BR (Números Legados)

**Objetivo:** Verificar se números BR com 8 dígitos são normalizados para 9

```bash
# Enviar para número com 8 dígitos (formato antigo)
curl -X POST http://192.168.100.154:27002/message/sendText/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" \
  --header "Content-Type: application/json" \
  --data '{
    "number": "11980549232",
    "text": "Teste normalização número BR"
  }' | jq .

# Verificar logs para ver normalização
podman logs --tail 50 evolution_dev | grep -i normaliz
```

---

## 🔌 Testes de Integrações

### 1. Chatwoot

```bash
# Verificar configuração do Chatwoot
curl -s http://192.168.100.154:27002/chatwoot/find/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" | jq .

# Resposta esperada:
# {
#   "enabled": true,
#   "url": "http://iadev-004.tail9bfafd.ts.net:3000",
#   "nameInbox": "Zyra9232",
#   "importMessages": true,
#   "daysLimitImportMessages": 7
# }
```

### 2. RabbitMQ

```bash
# Verificar configuração do RabbitMQ
curl -s http://192.168.100.154:27002/rabbitmq/find/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" | jq .

# Verificar se mensagens estão sendo enviadas ao RabbitMQ
# (Monitorar filas no RabbitMQ Management: http://192.168.100.154:15672)
```

### 3. Proxy

```bash
# Verificar se proxy está ativo
curl -s http://192.168.100.154:27002/instance/fetchInstances \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" | \
  jq '.[0].Proxy | {enabled, host, port}'

# Resposta esperada:
# {
#   "enabled": true,
#   "host": "chat-server.escaladaonline.com.br",
#   "port": "12501"
# }
```

---

## 📊 Teste de Carga (Básico)

### Envio em Lote

```bash
#!/bin/bash
# test-bulk-send.sh

API_URL="http://192.168.100.154:27002"
API_KEY="b89a64e758697d5bbb5b481611965e34"
INSTANCE="Zyra9232"
TARGET="554199243740"

echo "📤 Enviando 10 mensagens em sequência..."

for i in {1..10}; do
  echo "Enviando mensagem $i/10..."
  curl -s -X POST "$API_URL/message/sendText/$INSTANCE" \
    -H "apikey: $API_KEY" \
    -H "Content-Type: application/json" \
    -d "{
      \"number\": \"$TARGET\",
      \"text\": \"🔢 Mensagem de teste em lote #$i de 10\"
    }" | jq -r '.key.id // "ERRO"'

  sleep 2  # Aguardar 2s entre mensagens
done

echo "✅ Envio concluído!"
```

---

## 🔍 Monitoramento

### Logs em Tempo Real

```bash
# Ver todos os logs
podman logs -f evolution_dev

# Filtrar erros
podman logs -f evolution_dev | grep -iE "(error|fatal|exception)"

# Filtrar mensagens enviadas
podman logs -f evolution_dev | grep -i "sendText"

# Filtrar Chatwoot
podman logs -f evolution_dev | grep -i chatwoot

# Filtrar conexão WhatsApp
podman logs -f evolution_dev | grep -iE "(connected|disconnect|qr)"
```

### Status do Container

```bash
# Status geral
podman ps --filter name=evolution_dev --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"

# Uso de recursos
podman stats evolution_dev --no-stream

# Inspecionar configuração
podman inspect evolution_dev --format '{{.Config.Env}}' | tr ',' '\n' | grep -E "(DATABASE|CACHE|CHATWOOT)"
```

### Verificar Banco de Dados

```bash
# Contar mensagens da instância
PGPASSWORD='Desenv*123' psql -h 192.168.100.154 -p 5432 -U desenv -d zyra_9232 -c \
  "SELECT COUNT(*) FROM public.\"Message\" WHERE \"instanceId\" = 'e4248a38-a1a7-41a6-bbdc-835c72ab3994';"

# Ver últimas mensagens
PGPASSWORD='Desenv*123' psql -h 192.168.100.154 -p 5432 -U desenv -d zyra_9232 -c \
  "SELECT \"messageTimestamp\", \"pushName\", substring(body, 1, 50) as message
   FROM public.\"Message\"
   WHERE \"instanceId\" = 'e4248a38-a1a7-41a6-bbdc-835c72ab3994'
   ORDER BY \"messageTimestamp\" DESC
   LIMIT 5;"
```

---

## ✅ Checklist de Testes

### Funcionalidades Básicas
- [ ] API responde corretamente (/)
- [ ] Listar instâncias (fetchInstances)
- [ ] Verificar estado da conexão (connectionState)
- [ ] Enviar mensagem de texto para contato
- [ ] Enviar mensagem de texto para grupo
- [ ] Enviar imagem
- [ ] Receber mensagens
- [ ] Listar contatos
- [ ] Listar grupos

### Customizações v2.3.4
- [ ] SimpleMutex funcionando (sem race conditions)
- [ ] Cache TTL defaults ativos
- [ ] Error recovery configurado (3 tentativas)
- [ ] Normalização BR funcionando
- [ ] Source maps em produção

### Integrações
- [ ] Chatwoot habilitado e respondendo
- [ ] RabbitMQ enviando eventos
- [ ] Proxy configurado e ativo
- [ ] Database salvando dados
- [ ] Redis cache funcionando

### Performance
- [ ] API responde em < 2s
- [ ] Cache acelerando requisições
- [ ] Sem vazamentos de memória
- [ ] Logs sem erros críticos
- [ ] Container estável após 1h

---

## 🚨 Troubleshooting

### Container não inicia

```bash
# Verificar logs de erro
podman logs evolution_dev --tail 100

# Verificar se porta está ocupada
ss -tlnp | grep 27002

# Reiniciar container
podman-compose -f docker-compose.dev.yaml restart
```

### API não responde

```bash
# Verificar status do container
podman ps -a | grep evolution

# Verificar se instância está conectada
podman logs evolution_dev | grep -i "CONNECTED TO WHATSAPP"

# Testar conectividade interna
podman exec evolution_dev wget -qO- http://localhost:8080/
```

### Mensagens não enviam

```bash
# Verificar estado da conexão
curl -s http://192.168.100.154:27002/instance/connectionState/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" | jq .

# Verificar logs de erro ao enviar
podman logs evolution_dev | grep -iE "(sendText|error)"

# Reconectar instância (se necessário)
curl -X POST http://192.168.100.154:27002/instance/connect/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34"
```

### Chatwoot não funciona

```bash
# Verificar se Chatwoot está habilitado globalmente
podman exec evolution_dev env | grep CHATWOOT_ENABLED
# Deve retornar: CHATWOOT_ENABLED=true

# Verificar configuração da instância
curl -s http://192.168.100.154:27002/chatwoot/find/Zyra9232 \
  --header "apikey: b89a64e758697d5bbb5b481611965e34" | jq .

# Verificar logs do Chatwoot
podman logs evolution_dev | grep -i chatwoot
```

---

## 📚 Referências

- [Documentação Evolution API](https://doc.evolution-api.com)
- [Repositório Evolution API](https://github.com/EvolutionAPI/evolution-api)
- [Build Dev](./build-dev.md)
- [Deploy Final](../DEPLOY-FINAL.md)

---

## 📝 Notas Importantes

1. **Não envie spam:** Use números de teste autorizados
2. **Respeite limites:** WhatsApp tem limites de taxa
3. **Monitore logs:** Sempre verifique erros após testes
4. **Backup primeiro:** Antes de testes destrutivos
5. **Use grupos de teste:** Não teste em grupos de produção

---

**Última atualização:** 2025-10-03
**Responsável:** DevOps Team
