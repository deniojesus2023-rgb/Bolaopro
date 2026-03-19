#!/bin/bash
# ============================================================
# BolãoPro — Script de Deploy Completo
# Execute na sua máquina local com internet
# ============================================================

set -e

PROJECT_REF="nfqvwegyqtwbuvyfbsbe"
SUPABASE_URL="https://nfqvwegyqtwbuvyfbsbe.supabase.co"
SERVICE_ROLE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5mcXZ3ZWd5cXR3YnV2eWZic2JlIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3Mzg4NTQ1MywiZXhwIjoyMDg5NDYxNDUzfQ.wIhRi2xFrcHMIthzIk_4Yt0YC_jwWkAEa66cg7P5KSQ"

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "============================================="
echo "   BolãoPro — Deploy Automático"
echo "============================================="
echo ""

# ── VERIFICAR SUPABASE CLI ────────────────────────────────────
if ! command -v supabase &> /dev/null; then
  echo -e "${RED}✗ Supabase CLI não encontrado.${NC}"
  echo ""
  echo "Instale com um desses comandos:"
  echo "  macOS:   brew install supabase/tap/supabase"
  echo "  Linux:   https://github.com/supabase/cli/releases/latest"
  echo "  Windows: scoop install supabase"
  echo ""
  exit 1
fi

echo -e "${GREEN}✓ Supabase CLI: $(supabase --version)${NC}"

# ── LOGIN ────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}→ Passo 1/4: Login no Supabase${NC}"
echo "  Acesse: https://app.supabase.com/account/tokens"
echo "  Crie um Access Token e cole abaixo quando solicitado."
echo ""
supabase login

# ── LINK AO PROJETO ──────────────────────────────────────────
echo ""
echo -e "${YELLOW}→ Passo 2/4: Vinculando ao projeto${NC}"
echo "  (quando pedir a senha do banco, é a senha que você definiu no Supabase)"
supabase link --project-ref "$PROJECT_REF" --password "Arthurcorrea13072022!"

# ── EXECUTAR SQL FUNCTIONS ───────────────────────────────────
echo ""
echo -e "${YELLOW}→ Passo 3/4: Criando funções SQL${NC}"
supabase db execute --file funcoes-faltando.sql
echo -e "${GREEN}✓ funcoes-faltando.sql executado${NC}"

supabase db execute --file cron-setup.sql
echo -e "${GREEN}✓ cron-setup.sql executado${NC}"

# ── CONFIGURAR SECRETS DA EDGE FUNCTION ──────────────────────
echo ""
echo -e "${YELLOW}→ Configurando variáveis da Edge Function${NC}"

if [ -z "$API_FOOTBALL_KEY" ]; then
  echo ""
  echo -e "${YELLOW}  Você tem uma chave da API-Football (RapidAPI)?${NC}"
  echo "  Obtenha em: https://rapidapi.com/api-sports/api/api-football"
  echo -n "  Cole sua chave (ou ENTER para pular): "
  read API_FOOTBALL_KEY_INPUT
else
  API_FOOTBALL_KEY_INPUT="$API_FOOTBALL_KEY"
fi

if [ -n "$API_FOOTBALL_KEY_INPUT" ]; then
  supabase secrets set API_FOOTBALL_KEY="$API_FOOTBALL_KEY_INPUT"
  echo -e "${GREEN}✓ API_FOOTBALL_KEY configurada${NC}"
else
  echo -e "${YELLOW}⚠ Pulando API key — jogos reais não serão sincronizados${NC}"
fi

supabase secrets set SUPABASE_SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY"

# ── DEPLOY EDGE FUNCTION ─────────────────────────────────────
echo ""
echo -e "${YELLOW}→ Passo 4/4: Deploy da Edge Function${NC}"
supabase functions deploy sync-matches --no-verify-jwt
echo -e "${GREEN}✓ Edge Function 'sync-matches' deployada${NC}"

# ── VERIFICAR ────────────────────────────────────────────────
echo ""
echo "============================================="
echo -e "${GREEN}  Deploy concluído com sucesso!"
echo ""
echo "  Edge Function:"
echo "  ${SUPABASE_URL}/functions/v1/sync-matches"
echo ""
echo "  Crons configurados:"
echo "  - Sync diário: todo dia 08h00"
echo "  - Sync ao vivo: a cada 5 minutos"
echo "=============================================${NC}"
echo ""
