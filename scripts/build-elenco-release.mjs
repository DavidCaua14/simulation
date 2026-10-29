import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
// Gera supabase/releases/elenco_contratos.sql (evoluções 31 + 32) para colar no SQL Editor de um banco que já tem a carreira completa (24–30).
const root = resolve(import.meta.dirname, '..')
const body = (f) => readFileSync(resolve(root, 'supabase/evolution', f), 'utf8').trim().replace(/^(--.*\n)*begin;\s*/i, '').replace(/\s*commit;\s*$/i, '')
const out = `-- Gerado por scripts/build-elenco-release.mjs: evoluções 31 (avanço rápido) e 32 (satisfação, contratos, limite de elenco).
-- Cole tudo no SQL Editor do Supabase e execute de uma vez. É uma transação única: qualquer erro desfaz tudo.
-- Pode ser executado de novo sem duplicar nada. A manutenção (public/maintenance.json e o hook da API) não é alterada.
-- Garantia: ao final, compara carreiras, carteiras, resultados, partidas ao vivo, elencos, contratos e caixas com o
-- estado de antes; se qualquer dado de usuário mudar, a transação inteira é desfeita.
begin;
set local statement_timeout='120s';
set local lock_timeout='10s';
select pg_advisory_xact_lock(hashtext('elenco-contratos-v32'));
do $preflight$ begin
 if to_regclass('public.cw_world') is null or to_regprocedure('public.career_world_advance(integer,uuid)') is null
    or to_regprocedure('public.career_player_search(text,text,text,text,bigint,integer,text)') is null then
  raise exception 'Instale antes a carreira completa (supabase/releases/carreira_completa.sql, evoluções 24–30)';
 end if;
 if to_regprocedure('public.mgr_squad(text)') is null or to_regprocedure('public.mgr_match_payload(bigint,integer)') is null
    or to_regprocedure('public.career_news(bigint)') is null or to_regprocedure('public.career_transfer_bid(text,bigint,integer,bigint,boolean,uuid)') is null
    or to_regprocedure('public.cw_register_transfer(uuid)') is null then
  raise exception 'Funções esperadas da carreira completa não encontradas; nada foi alterado';
 end if;
end $preflight$;
create temp table v32_careers on commit drop as select id,to_jsonb(c) as original from public.careers c;
create temp table v32_results on commit drop as select id,to_jsonb(f) as original from public.season_fixtures f where status='played';
create temp table v32_live on commit drop as select fixture_id,to_jsonb(m) as original from public.mgr_matches m where status='live';
create temp table v32_squads on commit drop as select career_id,player_id,to_jsonb(p) as original from public.mgr_players p;
create temp table v32_contracts on commit drop as select id,to_jsonb(c) as original from public.cw_contracts c;
create temp table v32_clubs on commit drop as select career_id,club_id,to_jsonb(c) as original from public.cw_clubs c;
create temp table v32_morale on commit drop as select career_id,player_id,morale,transfer_requested,promised_role from public.cw_players;

-- ===================== evolução 31 =====================
${body('31_world_advance_speed.sql')}

-- ===================== evolução 32 =====================
${body('32_squad_morale_contracts.sql')}

do $preserved$ begin
 if exists(select 1 from v32_careers b left join public.careers c using(id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: uma carreira mudaria';end if;
 if exists(select 1 from v32_results b left join public.season_fixtures f using(id) where b.original is distinct from to_jsonb(f)) then raise exception 'Abortado: um resultado mudaria';end if;
 if exists(select 1 from v32_live b left join public.mgr_matches m using(fixture_id) where b.original is distinct from to_jsonb(m)) then raise exception 'Abortado: uma partida ao vivo mudaria';end if;
 if exists(select 1 from v32_squads b left join public.mgr_players p using(career_id,player_id) where b.original is distinct from to_jsonb(p)) then raise exception 'Abortado: um elenco mudaria';end if;
 if exists(select 1 from v32_contracts b left join public.cw_contracts c using(id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: um contrato mudaria';end if;
 if exists(select 1 from v32_clubs b left join public.cw_clubs c using(career_id,club_id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: um caixa de clube mudaria';end if;
 if exists(select 1 from v32_morale b left join public.cw_players p using(career_id,player_id) where row(b.morale,b.transfer_requested,b.promised_role) is distinct from row(p.morale,p.transfer_requested,p.promised_role)) then raise exception 'Abortado: uma satisfação mudaria';end if;
 if to_regprocedure('public.mgr_squad_before_v32(text)') is null or position('1200 milliseconds' in (select prosrc from pg_proc where oid=to_regprocedure('public.career_world_advance(integer,uuid)')))=0 then raise exception 'Instalação incompleta';end if;
end $preserved$;
commit;
select 'Instalação concluída: evoluções 31 e 32 ativas; dados dos usuários preservados.' as resultado;
`
writeFileSync(resolve(root, 'supabase/releases/elenco_contratos.sql'), out)
console.log('supabase/releases/elenco_contratos.sql')
