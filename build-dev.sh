#!/bin/bash
# build-dev.sh - Build e Deploy para ambiente de desenvolvimento
# Evolution API - custom-2.3.4-0

set -e  # Exit on error

# Cores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo ""
echo -e "${CYAN}================================================${NC}"
echo -e "${CYAN}  Evolution API - Development Build Script${NC}"
echo -e "${CYAN}  Version: custom-2.3.4-0${NC}"
echo -e "${CYAN}================================================${NC}"
echo ""

# 1. Verificar se .env existe
echo -e "${YELLOW}🔍 Verificando arquivo .env...${NC}"
if [ ! -f ".env" ]; then
    echo -e "${RED}❌ Arquivo .env não encontrado!${NC}"
    echo ""
    echo -e "${YELLOW}📝 Para criar o arquivo .env:${NC}"
    echo "   1. Copie: .env.dev.example para .env"
    echo "   2. Edite as variáveis conforme docs/build-dev.md"
    echo "   3. Configure PostgreSQL: 192.168.100.154:5432"
    echo "   4. Configure Redis: 192.168.100.154:6379"
    echo ""
    exit 1
fi

echo -e "${GREEN}✅ Arquivo .env encontrado${NC}"
echo ""

# 2. Verificar variáveis essenciais
echo -e "${YELLOW}🔍 Verificando variáveis essenciais...${NC}"

MISSING=()
if ! grep -q "^DATABASE_CONNECTION_URI=.\\+" .env; then
    MISSING+=("DATABASE_CONNECTION_URI")
fi
if ! grep -q "^CACHE_REDIS_URI=.\\+" .env; then
    MISSING+=("CACHE_REDIS_URI")
fi
if ! grep -q "^AUTHENTICATION_API_KEY=.\\+" .env; then
    MISSING+=("AUTHENTICATION_API_KEY")
fi

if [ ${#MISSING[@]} -gt 0 ]; then
    echo -e "${YELLOW}⚠️  Variáveis faltando ou vazias:${NC}"
    for var in "${MISSING[@]}"; do
        echo -e "   ${RED}- $var${NC}"
    done
    echo ""
    echo -e "${YELLOW}📝 Consulte docs/build-dev.md para configuração completa${NC}"
    echo ""
    read -p "Deseja continuar mesmo assim? (s/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
else
    echo -e "${GREEN}✅ Variáveis essenciais configuradas${NC}"
fi

echo ""

# 3. Verificar se há containers rodando
echo -e "${YELLOW}🔍 Verificando containers existentes...${NC}"
if podman ps -a --format "{{.Names}}" | grep -q "^evolution_dev$"; then
    echo -e "${YELLOW}⚠️  Container 'evolution_dev' já existe${NC}"
    echo ""
    read -p "Deseja remover o container existente? (s/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Ss]$ ]]; then
        echo -e "${YELLOW}🗑️  Removendo container existente...${NC}"
        podman rm -f evolution_dev 2>/dev/null || true
        echo -e "${GREEN}✅ Container removido${NC}"
    fi
fi

echo ""

# 4. Build da imagem
echo -e "${YELLOW}🔨 Iniciando build da imagem Docker...${NC}"
echo ""
echo -e "${CYAN}⏱️  Isso pode levar alguns minutos...${NC}"
echo ""

BUILD_START=$(date +%s)

podman build \
    --tag evolution-api:dev \
    --label "version=custom-2.3.4-0" \
    --label "environment=development" \
    --label "built=$(date '+%Y-%m-%d %H:%M:%S')" \
    --file Dockerfile \
    .

if [ $? -ne 0 ]; then
    echo ""
    echo -e "${RED}❌ Build falhou!${NC}"
    echo ""
    echo -e "${YELLOW}💡 Dicas:${NC}"
    echo "   - Verifique erros acima"
    echo "   - Garanta que tem memória suficiente"
    echo "   - Tente: podman build --memory=4g -t evolution-api:dev ."
    echo ""
    exit 1
fi

BUILD_END=$(date +%s)
BUILD_DURATION=$((BUILD_END - BUILD_START))
BUILD_MIN=$((BUILD_DURATION / 60))
BUILD_SEC=$((BUILD_DURATION % 60))

echo ""
echo -e "${GREEN}✅ Imagem criada com sucesso!${NC}"
echo -e "${CYAN}⏱️  Tempo de build: ${BUILD_MIN}m ${BUILD_SEC}s${NC}"
echo ""

# 5. Verificar imagem
echo -e "${CYAN}📦 Imagens Evolution API:${NC}"
podman images | grep evolution-api | while read line; do
    echo "   $line"
done
echo ""

# 6. Perguntar se quer subir o container
read -p "Deseja subir o container agora? (S/n): " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    echo ""
    echo -e "${YELLOW}🚀 Subindo container...${NC}"

    # Verificar se existe docker-compose.dev.yaml
    if [ -f "docker-compose.dev.yaml" ]; then
        echo "   Usando docker-compose.dev.yaml"
        podman-compose -f docker-compose.dev.yaml up -d
    else
        echo "   Usando comando direto do Podman"
        podman run -d \
            --name evolution_dev \
            --network iadev-shared-net \
            -p 29002:8080 \
            --env-file .env \
            evolution-api:dev
    fi

    if [ $? -ne 0 ]; then
        echo ""
        echo -e "${RED}❌ Falha ao subir container!${NC}"
        echo ""
        exit 1
    fi

    echo ""
    echo -e "${YELLOW}⏳ Aguardando inicialização (15s)...${NC}"
    sleep 15

    echo ""
    echo -e "${CYAN}📊 Status dos containers:${NC}"
    podman ps | grep evolution | while read line; do
        echo "   $line"
    done

    echo ""
    echo -e "${CYAN}📝 Últimas linhas do log:${NC}"
    podman logs --tail 20 evolution_dev | while read line; do
        echo -e "   ${NC}$line"
    done

    echo ""
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}  ✅ Container rodando com sucesso!${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    echo -e "${CYAN}📌 Informações úteis:${NC}"
    echo -e "   🌐 API:     http://localhost:29002"
    echo -e "   🖥️  Manager: http://localhost:29002/manager"
    echo -e "   📊 Logs:    podman logs -f evolution_dev"
    echo -e "   🛑 Parar:   podman stop evolution_dev"
    echo ""
    echo -e "${YELLOW}🔍 Para testar:${NC}"
    echo "   curl http://localhost:29002/health"
    echo ""
else
    echo ""
    echo -e "${YELLOW}📝 Para subir o container manualmente:${NC}"
    echo ""
    if [ -f "docker-compose.dev.yaml" ]; then
        echo "   podman-compose -f docker-compose.dev.yaml up -d"
    else
        echo "   podman run -d --name evolution_dev -p 29002:8080 --env-file .env evolution-api:dev"
    fi
    echo ""
fi

echo ""
echo -e "${GREEN}✨ Build concluído!${NC}"
echo -e "${CYAN}📚 Documentação completa: docs/build-dev.md${NC}"
echo ""
