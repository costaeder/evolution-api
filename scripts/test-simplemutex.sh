#!/bin/bash
# Test SimpleMutex - Concurrent calls to whatsappNumbers

set -e

API_URL="${API_URL:-http://192.168.100.154:27002}"
API_KEY="${API_KEY:-b89a64e758697d5bbb5b481611965e34}"
INSTANCE="${INSTANCE:-Zyra9232}"
CONCURRENT="${CONCURRENT:-5}"

echo "🔒 Teste SimpleMutex - Chamadas Concorrentes"
echo "   Instância: $INSTANCE"
echo "   Chamadas: $CONCURRENT"
echo ""

echo "Executando $CONCURRENT chamadas simultâneas..."

for i in $(seq 1 $CONCURRENT); do
  (
    START=$(date +%s%N)
    RESPONSE=$(curl -s -X POST "$API_URL/chat/whatsappNumbers/$INSTANCE" \
      -H "apikey: $API_KEY" \
      -H "Content-Type: application/json" \
      -d '{"numbers": ["5511999999999", "5521888888888"]}')
    END=$(date +%s%N)
    DURATION=$(( (END - START) / 1000000 ))
    echo "[Thread $i] Completed in ${DURATION}ms"
  ) &
done

wait

echo ""
echo "✅ Todas as chamadas concluídas!"
echo ""
echo "📋 Verificar logs do SimpleMutex:"
echo "   podman logs --tail 50 evolution_dev | grep -i mutex"
