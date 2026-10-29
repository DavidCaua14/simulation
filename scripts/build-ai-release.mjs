import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
// Gera supabase/releases/ia_equilibrio.sql (evolução 34) para colar no SQL Editor depois de mensagens.sql (33).
// O arquivo é UM ÚNICO comando (bloco DO): instalação, conferência dos dados e verificação acontecem juntas.
// Se o editor executar só um trecho, o comando fica incompleto e nada roda; se rodar, é tudo ou nada.
const root = resolve(import.meta.dirname, '..')
const body = readFileSync(resolve(root, 'supabase/evolution/34_ai_balance.sql'), 'utf8')
  .trim()
  .replace(/^(--.*\n)*begin;\s*/i, '')
  .replace(/\s*commit;\s*$/i, '')
  .replace(/^notify pgrst,'reload schema';$/m, "perform pg_notify('pgrst','reload schema');")
if (/\$install\$/.test(body)) throw new Error('A migração não pode conter a marca $install$')
const fingerprint = `select jsonb_build_object(
   'careers',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.careers c),
   'results',(select md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'),
   'live',(select md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'),
   'squads',(select md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p),
   'contracts',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c),
   'clubs',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c),
   'negotiations',(select md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n),
   'messages',(select md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages),
   'morale',(select md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players))`
const out = `-- Gerado por scripts/build-ai-release.mjs: evolução 34 (equilíbrio da IA: satisfação, mercado, propostas e contratos).
-- Requer as evoluções 31, 32 e 33. Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Não altera dados existentes: só substitui funções e adiciona um gatilho para contratos novos. Ao final compara as
-- impressões digitais de carreiras, resultados, partidas ao vivo, elencos, contratos, caixas, negociações, mensagens
-- e satisfação; se alguma mudar, o comando é desfeito por inteiro.
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('ia-equilibrio-v34'));
 if to_regprocedure('public.mgr_hub_before_v33()') is null then raise exception 'Instale antes a evolução 33 (supabase/releases/mensagens.sql); nada foi alterado';end if;
 ${fingerprint} into antes;

-- ===================== evolução 34 =====================
${body}

 ${fingerprint} into depois;
 select string_agg(k,', ') into mudou from jsonb_object_keys(antes) k where antes->k is distinct from depois->k;
 if mudou is not null then raise exception 'Abortado: dados de usuários mudariam (%); nada foi alterado',mudou;end if;
 if to_regprocedure('public.cw_foreign_hiring(text,date)') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: equilíbrio da IA ativo; dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('public.cw_foreign_hiring(text,date)') is not null then 'Instalação concluída: equilíbrio da IA ativo; dados dos usuários preservados.' else 'Não instalado' end as resultado;
`
writeFileSync(resolve(root, 'supabase/releases/ia_equilibrio.sql'), out)
console.log('supabase/releases/ia_equilibrio.sql')
