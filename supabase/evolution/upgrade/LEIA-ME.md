# Atualização de um banco que JÁ TEM o jogo instalado (produção)

Estes arquivos trazem só a DIFERENÇA de jogadores entre o elenco antigo (48 clubes) e o novo (141 clubes).
Um banco novo não precisa deles: `supabase/manager/02_players_seed.sql` já é o elenco completo.

Ordem para atualizar um banco existente:
1. `evolution/01_schema.sql` e `evolution/02_reference_data.sql`
2. `upgrade/01_players.sql` … `04_players.sql` (insert/update por id — ids antigos preservados, nenhum jogador removido)
3. `upgrade/05_attrs.sql` … `07_attrs.sql` (atributos estimados; não sobrescreve atributos reais)
4. `select public.sim_refresh_ratings();`
5. `manager/05`…, `evolution/03_engine.sql` e `evolution/04_manager.sql`

Tudo é idempotente: rodar de novo produz o mesmo resultado.
