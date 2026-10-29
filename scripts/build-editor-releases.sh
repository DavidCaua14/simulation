#!/bin/sh
# Regera os scripts de colar no SQL Editor (um único comando cada; ver scripts/build-editor-release.mjs).
set -e
cd "$(dirname "$0")/.."
node scripts/build-editor-release.mjs 34_ai_balance.sql supabase/releases/ia_equilibrio.sql 'public.mgr_hub_before_v33()' 'public.cw_foreign_hiring(text,date)' 'equilíbrio da IA ativo' 'Requer a evolução 33 (supabase/releases/mensagens.sql)'
node scripts/build-editor-release.mjs 35_update_gift.sql supabase/releases/presentes_atualizacao.sql 'public.cw_foreign_hiring(text,date)' 'public.release_gift_claim()' 'presentes da atualização e avatares ativos' 'Requer a evolução 34 (supabase/releases/ia_equilibrio.sql)'
