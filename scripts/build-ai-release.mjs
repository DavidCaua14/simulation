import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
// Gera supabase/releases/ia_equilibrio.sql (evolução 34) para colar no SQL Editor depois de mensagens.sql (33).
const root = resolve(import.meta.dirname, '..')
const body = readFileSync(resolve(root, 'supabase/evolution/34_ai_balance.sql'), 'utf8').trim().replace(/^(--.*\n)*begin;\s*/i, '').replace(/\s*commit;\s*$/i, '')
const out = `-- Gerado por scripts/build-inbox-release.mjs: evolução 34 (equilíbrio da IA: satisfação, mercado, propostas e contratos).
-- Requer as evoluções 31, 32 e 33 (elenco_contratos.sql e mensagens.sql). Cole tudo no SQL Editor e execute de uma vez.
-- Transação única: qualquer erro desfaz tudo. Pode ser executado de novo. A manutenção não é alterada.
-- Garantia: compara carreiras, resultados, partidas ao vivo, elencos, contratos, caixas, negociações e mensagens
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
create temp table v34_careers on commit drop as select id,to_jsonb(c) as original from public.careers c;
create temp table v34_results on commit drop as select id,to_jsonb(f) as original from public.season_fixtures f where status='played';
create temp table v34_live on commit drop as select fixture_id,to_jsonb(m) as original from public.mgr_matches m where status='live';
create temp table v34_squads on commit drop as select career_id,player_id,to_jsonb(p) as original from public.mgr_players p;
create temp table v34_contracts on commit drop as select id,to_jsonb(c) as original from public.cw_contracts c;
create temp table v34_clubs on commit drop as select career_id,club_id,to_jsonb(c) as original from public.cw_clubs c;
create temp table v34_negotiations on commit drop as select id,to_jsonb(n) as original from public.cw_negotiations n;
create temp table v34_messages on commit drop as select id,career_id,kind,title,body,club_id,read,day_no from public.mgr_messages;
create temp table v34_morale on commit drop as select career_id,player_id,morale,transfer_requested,promised_role from public.cw_players;

${body}

do $preserved$ begin
 if exists(select 1 from v34_careers b left join public.careers c using(id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: uma carreira mudaria';end if;
 if exists(select 1 from v34_results b left join public.season_fixtures f using(id) where b.original is distinct from to_jsonb(f)) then raise exception 'Abortado: um resultado mudaria';end if;
 if exists(select 1 from v34_live b left join public.mgr_matches m using(fixture_id) where b.original is distinct from to_jsonb(m)) then raise exception 'Abortado: uma partida ao vivo mudaria';end if;
 if exists(select 1 from v34_squads b left join public.mgr_players p using(career_id,player_id) where b.original is distinct from to_jsonb(p)) then raise exception 'Abortado: um elenco mudaria';end if;
 if exists(select 1 from v34_contracts b left join public.cw_contracts c using(id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: um contrato mudaria';end if;
 if exists(select 1 from v34_clubs b left join public.cw_clubs c using(career_id,club_id) where b.original is distinct from to_jsonb(c)) then raise exception 'Abortado: um caixa de clube mudaria';end if;
 if exists(select 1 from v34_negotiations b left join public.cw_negotiations n using(id) where b.original is distinct from to_jsonb(n)) then raise exception 'Abortado: uma negociação mudaria';end if;
 if exists(select 1 from v34_messages b left join public.mgr_messages m using(id) where row(b.career_id,b.kind,b.title,b.body,b.club_id,b.read,b.day_no) is distinct from row(m.career_id,m.kind,m.title,m.body,m.club_id,m.read,m.day_no)) then raise exception 'Abortado: uma mensagem existente mudaria';end if;
 if exists(select 1 from v34_morale b left join public.cw_players p using(career_id,player_id) where row(b.morale,b.transfer_requested,b.promised_role) is distinct from row(p.morale,p.transfer_requested,p.promised_role)) then raise exception 'Abortado: uma satisfação mudaria';end if;
 if to_regprocedure('public.cw_foreign_hiring(text,date)') is null then raise exception 'Instalação incompleta';end if;
end $preserved$;
commit;
select 'Instalação concluída: equilíbrio da IA ativo; dados dos usuários preservados.' as resultado;
`
writeFileSync(resolve(root, 'supabase/releases/ia_equilibrio.sql'), out)
console.log('supabase/releases/ia_equilibrio.sql')
