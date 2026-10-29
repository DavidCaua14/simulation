import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
// Gera supabase/releases/ia_equilibrio.sql (evolução 34) para colar no SQL Editor depois de mensagens.sql (33).
const root = resolve(import.meta.dirname, '..')
const body = readFileSync(resolve(root, 'supabase/evolution/34_ai_balance.sql'), 'utf8').trim().replace(/^(--.*\n)*begin;\s*/i, '').replace(/\s*commit;\s*$/i, '')
const out = `-- Gerado por scripts/build-inbox-release.mjs: evolução 34 (equilíbrio da IA: satisfação, mercado, propostas e contratos).
-- Requer as evoluções 31, 32 e 33 (elenco_contratos.sql e mensagens.sql). Cole tudo no SQL Editor e execute de uma vez.
-- Transação única: qualquer erro desfaz tudo. Pode ser executado de novo. A manutenção não é alterada.
-- Rode o arquivo INTEIRO (sem selecionar um trecho). Garantia: compara carreiras, resultados, partidas ao vivo, elencos, contratos, caixas, negociações e mensagens
-- existentes com o estado de antes; se algum dado de usuário mudar, a transação inteira é desfeita.
-- Não altera nenhum dado existente: só substitui funções e adiciona um gatilho para contratos novos.
begin;
set local statement_timeout='120s';
set local lock_timeout='10s';
select pg_advisory_xact_lock(hashtext('ia-equilibrio-v34'));
do $preflight$ begin
 if to_regprocedure('public.mgr_hub_before_v33()') is null then raise exception 'Instale antes supabase/releases/mensagens.sql (evolução 33); nada foi alterado';end if;
 if to_regclass('public.mgr_messages') is null or to_regprocedure('public.mgr_hub()') is null then raise exception 'Estrutura da carreira não encontrada; nada foi alterado';end if;
end $preflight$;
-- Impressões digitais dos dados de usuários antes da instalação (tabela auxiliar apagada no fim).
create table if not exists public.cw_release_check(item text primary key,hash text);
delete from public.cw_release_check;
insert into public.cw_release_check
select 'careers',md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.careers c
union all select 'results',md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'
union all select 'live',md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'
union all select 'squads',md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p
union all select 'contracts',md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c
union all select 'clubs',md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c
union all select 'negotiations',md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n
union all select 'messages',md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages
union all select 'morale',md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players;

${body}

do $preserved$ declare changed text;begin
 select string_agg(b.item,', ') into changed from public.cw_release_check b join (
  select 'careers' item,md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) hash from public.careers c
  union all select 'results',md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'
  union all select 'live',md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'
  union all select 'squads',md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p
  union all select 'contracts',md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c
  union all select 'clubs',md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c
  union all select 'negotiations',md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n
  union all select 'messages',md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages
  union all select 'morale',md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players) a using(item)
  where a.hash is distinct from b.hash;
 if changed is not null then raise exception 'Abortado: dados de usuários mudariam (%)',changed;end if;
 if to_regprocedure('public.cw_foreign_hiring(text,date)') is null then raise exception 'Instalação incompleta';end if;
end $preserved$;
drop table public.cw_release_check;
commit;
select 'Instalação concluída: equilíbrio da IA ativo; dados dos usuários preservados.' as resultado;
`
writeFileSync(resolve(root, 'supabase/releases/ia_equilibrio.sql'), out)
console.log('supabase/releases/ia_equilibrio.sql')
