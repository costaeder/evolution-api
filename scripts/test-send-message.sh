#!/bin/bash
# Test script - Send test message via Evolution API

set -e

API_URL="${API_URL:-http://192.168.100.154:27002}"
API_KEY="${API_KEY:-b89a64e758697d5bbb5b481611965e34}"
INSTANCE="${INSTANCE:-Zyra9232}"

# Check if number was provided
if [ -z "$1" ]; then
  echo "❌ Uso: $0 <número_destino> [mensagem]"
  echo ""
  echo "Exemplos:"
  echo "  $0 554199243740"
  echo "  $0 554199243740 'Mensagem personalizada'"
  echo ""
  exit 1
fi

TARGET="$1"
MESSAGE="${2:-🤖 Teste Evolution API v2.3.4-0\nMensagem de teste automático\nData: $(date '+%Y-%m-%d %H:%M:%S')}"

echo "📤 Enviando mensagem de teste..."
echo "   Destino: $TARGET"
echo "   Instância: $INSTANCE"
echo ""

RESPONSE=$(curl -s -X POST "$API_URL/message/sendText/$INSTANCE" \
  --header "apikey: $API_KEY" \
  --header "Content-Type: application/json" \
  --data "{
    \"number\": \"$TARGET\",
    \"text\": \"$MESSAGE\"
  }")

echo "Resposta:"
echo "$RESPONSE" | jq .

if echo "$RESPONSE" | jq -e '.key.id' > /dev/null 2>&1; then
  echo ""
  echo "✅ Mensagem enviada com sucesso!"
  echo "   ID: $(echo "$RESPONSE" | jq -r '.key.id')"
else
  echo ""
  echo "❌ Erro ao enviar mensagem"
  exit 1
fi
