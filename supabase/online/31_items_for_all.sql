-- MODO ONLINE — Fase 29: Apito de Ouro liberado para todos os técnicos.
-- O portão do item (on_item_gate) passa a aceitar qualquer usuário logado. Preço, limite de compra e regras de uso seguem
-- os da Fase 28 (30_training_item.sql). A distribuição de 7 apitos vai pelo aviso da caixa de entrada
-- (supabase/evolution/76_inbox_item_rewards.sql), resgatado por cada técnico.
create or replace function public.on_item_gate() returns boolean
language sql stable security definer set search_path=public as $$ select auth.uid() is not null $$;
revoke all on function public.on_item_gate() from public,anon,authenticated;
