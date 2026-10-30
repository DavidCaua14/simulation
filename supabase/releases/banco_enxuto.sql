-- Gerado por scripts/build-editor-release.mjs a partir de 38_storage_diet.sql: banco enxuto (salários da IA agrupados e dados auxiliares antigos removidos).
-- Requer o modo Temporadas com mundo paralelo (supabase/releases/carreira_completa.sql). Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Ao final compara as impressões digitais de carreiras, resultados, partidas ao vivo, elencos, contratos, caixas, negociações, mensagens
-- e satisfação; se alguma mudar, o comando é desfeito por inteiro.
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('38_storage_diet.sql'));
 if to_regprocedure('public.cw_settle_month(uuid,date)') is null then raise exception 'Requer o modo Temporadas com mundo paralelo (supabase/releases/carreira_completa.sql); nada foi alterado';end if;
 select jsonb_build_object(
   'careers',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.careers c),
   'results',(select md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'),
   'live',(select md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'),
   'squads',(select md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p),
   'contracts',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c),
   'clubs',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c),
   'negotiations',(select md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n),
   'messages',(select md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages),
   'morale',(select md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players)) into antes;

-- ===================== 38_storage_diet.sql =====================
create table if not exists public.cw_settled_months(
 career_id uuid not null references public.careers(id) on delete cascade,month date not null,settled_at timestamptz not null default now(),
 primary key(career_id,month));
alter table public.cw_settled_months enable row level security;
revoke all on public.cw_settled_months from public,anon,authenticated;

do $$ begin
 if to_regprocedure('public.cw_settle_month_before_v38(uuid,date)') is null then
  alter function public.cw_settle_month(uuid,date) rename to cw_settle_month_before_v38;
 end if;
end $$;

-- Compacta um mês já pago de uma carreira e apaga dados auxiliares que não servem mais.
create or replace function public.cw_compact_month(p_career uuid,p_month date)
returns void language plpgsql security definer set search_path=public as $$
#variable_conflict use_column
declare tag text:=to_char(p_month,'YYYY-MM');today date;r record;
begin
 select w.today into today from public.cw_world w where w.career_id=p_career;
 for r in
  select f.club_id,count(*) n,sum(f.amount) total,max(f.on_date) on_date,
   (array_agg(f.cash_after order by f.id desc))[1] cash_after,
   sum(coalesce((f.metadata->>'paid')::bigint,0)) paid,sum(coalesce((f.metadata->>'owed')::bigint,0)) owed
  from public.cw_finance f
  where f.career_id=p_career and f.kind='wages' and f.reference like '%:'||tag
   and f.club_id is distinct from (select club_id from public.mgr_coach where career_id=p_career)
   and not exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=f.club_id)
  group by f.club_id
 loop
  insert into public.cw_finance(career_id,club_id,on_date,kind,amount,cash_after,reference,description,metadata)
  values(p_career,r.club_id,r.on_date,'wages',r.total,r.cash_after,'club:'||tag,'Folha salarial do mês ('||r.n||' atletas)',
   jsonb_build_object('contracts',r.n,'paid',r.paid,'owed',r.owed,'compacted',true))
  on conflict (career_id,club_id,kind,reference) do nothing;
  delete from public.cw_finance f where f.career_id=p_career and f.club_id=r.club_id and f.kind='wages' and f.reference like '%:'||tag and f.reference<>'club:'||tag;
 end loop;
 if today is not null then
  delete from public.cw_ai_days where career_id=p_career and on_date<today-1;
  delete from public.cw_club_dates where career_id=p_career and due_on<today-3;
 end if;
 delete from public.cw_appearances a using public.career_seasons cs
  where a.career_id=p_career and cs.id=a.season_id and cs.status<>'active'
   and a.club_id is distinct from (select club_id from public.mgr_coach where career_id=p_career)
   and not exists(select 1 from public.cw_coach_contracts cc where cc.career_id=p_career and cc.club_id=a.club_id);
end $$;

create or replace function public.cw_settle_month(p_career uuid,p_month date)
returns void language plpgsql security definer set search_path=public as $$
begin
 if exists(select 1 from public.cw_settled_months where career_id=p_career and month=p_month) then return;end if;
 perform public.cw_settle_month_before_v38(p_career,p_month);
 insert into public.cw_settled_months(career_id,month) values(p_career,p_month) on conflict do nothing;
 perform public.cw_compact_month(p_career,p_month);
end $$;

revoke all on function public.cw_settle_month(uuid,date),public.cw_settle_month_before_v38(uuid,date),public.cw_compact_month(uuid,date) from public,anon,authenticated;

-- Uma vez agora: marca os meses já pagos e compacta o histórico de todas as carreiras.
insert into public.cw_settled_months(career_id,month)
select distinct f.career_id,to_date(f.reference,'YYYY-MM') from public.cw_finance f
where f.kind='commercial' and f.reference ~ '^\d{4}-\d{2}$' on conflict do nothing;

do $$ declare r record;begin
 for r in select career_id,month from public.cw_settled_months order by career_id,month loop
  perform public.cw_compact_month(r.career_id,r.month);
 end loop;
end $$;

analyze public.cw_finance;analyze public.cw_appearances;analyze public.cw_ai_days;analyze public.cw_club_dates;
perform pg_notify('pgrst','reload schema');

 select jsonb_build_object(
   'careers',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.careers c),
   'results',(select md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'),
   'live',(select md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'),
   'squads',(select md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p),
   'contracts',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c),
   'clubs',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c),
   'negotiations',(select md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n),
   'messages',(select md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages),
   'morale',(select md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players)) into depois;
 select string_agg(k,', ') into mudou from jsonb_object_keys(antes) k where antes->k is distinct from depois->k;
 if mudou is not null then raise exception 'Abortado: dados de usuários mudariam (%); nada foi alterado',mudou;end if;
 if to_regprocedure('public.cw_compact_month(uuid,date)') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: banco enxuto (salários da IA agrupados e dados auxiliares antigos removidos); dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('public.cw_compact_month(uuid,date)') is not null then 'Instalação concluída: banco enxuto (salários da IA agrupados e dados auxiliares antigos removidos); dados dos usuários preservados.' else 'Não instalado' end as resultado;
