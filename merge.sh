#!/usr/bin/env bash
set -euo pipefail

# 0) Só aborta se realmente existir um merge pendente
if [ -f "$(git rev-parse --git-dir)/MERGE_HEAD" ]; then
  git merge --abort
fi

# 1) Configure identity (se ainda não tiver)
git config user.email >/dev/null 2>&1 || \
  git config --global user.email "eder.almeida.costa@gmail.com"
git config user.name  >/dev/null 2>&1 || \
  git config --global user.name  "Eder"

# 2) Atualiza main
git fetch origin
git checkout main
git pull origin main

# 3) Merge sem commit
git merge --no-commit --no-ff custom-2.2.3 || true

# 4) Cria pasta de patches
OUT_DIR=ai_diffs
mkdir -p "$OUT_DIR"

# 5) Para cada arquivo em conflito, gera um patch separado
while IFS= read -r f; do
  # troca "/" por "_" de forma portátil
  safe_name=$(printf '%s' "$f" | tr '/' '_').patch
  git diff custom-2.2.3..main -- "$f" \
    > "$OUT_DIR/$safe_name"
done < <(git diff --name-only --diff-filter=U)

# 6) Validação opcional
for p in "$OUT_DIR"/*.patch; do
  if ! git apply --check "$p"; then
    echo "⚠️  Falha ao aplicar $p"
  fi
done

# 7) Se quiser, volta a um estado limpo (opcional)
git merge --abort || true

echo "✔️ Patches gerados em $OUT_DIR/"
