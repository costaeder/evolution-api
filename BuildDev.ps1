# BuildDev.ps1 - Build para ambiente de desenvolvimento
# Evolution API - custom-2.3.4-0

$ErrorActionPreference = "Stop"

Write-Host ""
Write-Host "================================================" -ForegroundColor Cyan
Write-Host "  Evolution API - Development Build Script" -ForegroundColor Cyan
Write-Host "  Version: custom-2.3.4-0" -ForegroundColor Cyan
Write-Host "================================================" -ForegroundColor Cyan
Write-Host ""

# 1. Verificar se .env existe
Write-Host "🔍 Verificando arquivo .env..." -ForegroundColor Yellow
if (-Not (Test-Path ".env")) {
    Write-Host "❌ Arquivo .env não encontrado!" -ForegroundColor Red
    Write-Host ""
    Write-Host "📝 Para criar o arquivo .env:" -ForegroundColor Yellow
    Write-Host "   1. Copie: docs/.env.example para .env" -ForegroundColor White
    Write-Host "   2. Edite as variáveis conforme docs/build-dev.md" -ForegroundColor White
    Write-Host "   3. Configure PostgreSQL: 192.168.100.154:5432" -ForegroundColor White
    Write-Host "   4. Configure Redis: 192.168.100.154:6379" -ForegroundColor White
    Write-Host ""
    exit 1
}

Write-Host "✅ Arquivo .env encontrado" -ForegroundColor Green
Write-Host ""

# 2. Verificar variáveis essenciais
Write-Host "🔍 Verificando variáveis essenciais..." -ForegroundColor Yellow

$envContent = Get-Content ".env" -Raw

$requiredVars = @(
    "DATABASE_CONNECTION_URI",
    "CACHE_REDIS_URI",
    "AUTHENTICATION_API_KEY"
)

$missing = @()
foreach ($var in $requiredVars) {
    if ($envContent -notmatch "$var=.+") {
        $missing += $var
    }
}

if ($missing.Count -gt 0) {
    Write-Host "⚠️  Variáveis faltando ou vazias:" -ForegroundColor Yellow
    foreach ($var in $missing) {
        Write-Host "   - $var" -ForegroundColor Red
    }
    Write-Host ""
    Write-Host "📝 Consulte docs/build-dev.md para configuração completa" -ForegroundColor Yellow
    Write-Host ""
    $continuar = Read-Host "Deseja continuar mesmo assim? (S/N)"
    if ($continuar -ne "S" -and $continuar -ne "s") {
        exit 1
    }
} else {
    Write-Host "✅ Variáveis essenciais configuradas" -ForegroundColor Green
}

Write-Host ""

# 3. Verificar se há containers rodando
Write-Host "🔍 Verificando containers existentes..." -ForegroundColor Yellow
$existingContainer = podman ps -a --format "{{.Names}}" | Select-String "evolution_dev"

if ($existingContainer) {
    Write-Host "⚠️  Container 'evolution_dev' já existe" -ForegroundColor Yellow
    Write-Host ""
    $remover = Read-Host "Deseja remover o container existente? (S/N)"
    if ($remover -eq "S" -or $remover -eq "s") {
        Write-Host "🗑️  Removendo container existente..." -ForegroundColor Yellow
        podman rm -f evolution_dev 2>$null
        Write-Host "✅ Container removido" -ForegroundColor Green
    }
}

Write-Host ""

# 4. Build da imagem
Write-Host "🔨 Iniciando build da imagem Docker..." -ForegroundColor Yellow
Write-Host ""
Write-Host "⏱️  Isso pode levar alguns minutos..." -ForegroundColor Cyan
Write-Host ""

$buildStart = Get-Date

podman build `
    --tag evolution-api:dev `
    --label "version=custom-2.3.4-0" `
    --label "environment=development" `
    --label "built=$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" `
    --file Dockerfile `
    .

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "❌ Build falhou!" -ForegroundColor Red
    Write-Host ""
    Write-Host "💡 Dicas:" -ForegroundColor Yellow
    Write-Host "   - Verifique erros acima" -ForegroundColor White
    Write-Host "   - Garanta que tem memória suficiente" -ForegroundColor White
    Write-Host "   - Tente: podman build --memory=4g -t evolution-api:dev ." -ForegroundColor White
    Write-Host ""
    exit 1
}

$buildEnd = Get-Date
$buildDuration = $buildEnd - $buildStart

Write-Host ""
Write-Host "✅ Imagem criada com sucesso!" -ForegroundColor Green
Write-Host "⏱️  Tempo de build: $($buildDuration.Minutes)m $($buildDuration.Seconds)s" -ForegroundColor Cyan
Write-Host ""

# 5. Verificar imagem
Write-Host "📦 Imagens Evolution API:" -ForegroundColor Cyan
podman images | Select-String "evolution-api" | ForEach-Object { Write-Host "   $_" -ForegroundColor White }
Write-Host ""

# 6. Perguntar se quer subir o container
$subirContainer = Read-Host "Deseja subir o container agora? (S/N)"

if ($subirContainer -eq "S" -or $subirContainer -eq "s") {
    Write-Host ""
    Write-Host "🚀 Subindo container..." -ForegroundColor Yellow

    # Verificar se existe docker-compose.dev.yaml
    if (Test-Path "docker-compose.dev.yaml") {
        Write-Host "   Usando docker-compose.dev.yaml" -ForegroundColor Cyan
        podman-compose -f docker-compose.dev.yaml up -d
    } else {
        Write-Host "   Usando comando direto do Podman" -ForegroundColor Cyan
        podman run -d `
            --name evolution_dev `
            -p 8080:8080 `
            --env-file .env `
            -v ${PWD}/instances:/evolution/instances `
            -v ${PWD}/logs:/evolution/logs `
            evolution-api:dev
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Host ""
        Write-Host "❌ Falha ao subir container!" -ForegroundColor Red
        Write-Host ""
        exit 1
    }

    Write-Host ""
    Write-Host "⏳ Aguardando inicialização (15s)..." -ForegroundColor Yellow
    Start-Sleep -Seconds 15

    Write-Host ""
    Write-Host "📊 Status dos containers:" -ForegroundColor Cyan
    podman ps | Select-String "evolution" | ForEach-Object { Write-Host "   $_" -ForegroundColor White }

    Write-Host ""
    Write-Host "📝 Últimas linhas do log:" -ForegroundColor Cyan
    podman logs --tail 20 evolution_dev | ForEach-Object { Write-Host "   $_" -ForegroundColor DarkGray }

    Write-Host ""
    Write-Host "================================================" -ForegroundColor Green
    Write-Host "  ✅ Container rodando com sucesso!" -ForegroundColor Green
    Write-Host "================================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "📌 Informações úteis:" -ForegroundColor Cyan
    Write-Host "   🌐 API:     http://localhost:8080" -ForegroundColor White
    Write-Host "   🖥️  Manager: http://localhost:8080/manager" -ForegroundColor White
    Write-Host "   📊 Logs:    podman logs -f evolution_dev" -ForegroundColor White
    Write-Host "   🛑 Parar:   podman stop evolution_dev" -ForegroundColor White
    Write-Host ""
    Write-Host "🔍 Para testar:" -ForegroundColor Yellow
    Write-Host "   curl http://localhost:8080/health" -ForegroundColor White
    Write-Host ""
} else {
    Write-Host ""
    Write-Host "📝 Para subir o container manualmente:" -ForegroundColor Yellow
    Write-Host ""
    if (Test-Path "docker-compose.dev.yaml") {
        Write-Host "   podman-compose -f docker-compose.dev.yaml up -d" -ForegroundColor White
    } else {
        Write-Host "   podman run -d --name evolution_dev -p 8080:8080 --env-file .env evolution-api:dev" -ForegroundColor White
    }
    Write-Host ""
}

Write-Host ""
Write-Host "✨ Build concluído!" -ForegroundColor Green
Write-Host "📚 Documentação completa: docs/build-dev.md" -ForegroundColor Cyan
Write-Host ""
