-- Chamada vazia usada pelo app para manter vivas as conexões do PostgREST enquanto alguém joga.
-- O PostgREST fecha conexões paradas (limite máximo de 60 s neste plano) e uma conexão nova replaneja todas as
-- funções: abrir o elenco custava ~900 ms numa conexão nova contra ~120 ms numa aquecida.
-- Não lê nem grava nada.
CREATE OR REPLACE FUNCTION public.keep_warm()
 RETURNS void
 LANGUAGE sql
 STABLE
 SET search_path TO 'public'
AS $function$ select $function$;

REVOKE ALL ON FUNCTION public.keep_warm() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.keep_warm() TO authenticated, service_role;
