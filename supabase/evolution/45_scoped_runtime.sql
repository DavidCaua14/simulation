-- Calendário local e operações recuperáveis. A instalação não altera saves existentes.
begin;
create table if not exists public.cw_runtime_rules(
 id boolean primary key default true check(id),foreign_reputation numeric not null default 55,
 foreign_credibility numeric not null default 45,market_interval int not null default 3 check(market_interval between 1 and 14),
 catalog_version text not null default '2026-10-31',enabled boolean not null default true);
insert into public.cw_runtime_rules(id) values(true) on conflict do nothing;
create table if not exists public.cw_runtime(
 career_id uuid primary key references public.careers(id),catalog_version text not null,
 enabled boolean not null default true,version bigint not null default 0,activated_at timestamptz not null default now(),
 attention_ack text,last_market_on date,last_recovery_day int,seed uuid not null default gen_random_uuid(),deferred_live boolean not null default false);
alter table public.cw_runtime add column if not exists deferred_live boolean not null default false;
create table if not exists public.cw_operations(
 career_id uuid not null references public.careers(id),request_id uuid not null,kind text not null,
 parameters jsonb not null,result jsonb not null,created_at timestamptz not null default now(),
 primary key(career_id,request_id));
create table if not exists public.cw_attention_acks(
 career_id uuid not null references public.careers(id),decision_key text not null,created_at timestamptz not null default now(),
 primary key(career_id,decision_key));
create table if not exists public.cw_runtime_metrics(
 career_id uuid primary key references public.careers(id),calls bigint not null default 0,
 total_ms numeric not null default 0,max_ms numeric not null default 0,matches bigint not null default 0,days bigint not null default 0);
create table if not exists public.cw_catalog_versions(
 version text primary key,created_at timestamptz not null default now(),snapshot jsonb not null);
insert into public.cw_catalog_versions(version,snapshot)
select catalog_version,jsonb_build_object('clubs',(select jsonb_agg(to_jsonb(c) order by id) from public.sim_clubs c),
 'players',(select jsonb_agg(to_jsonb(p) order by id) from public.sim_players p),
 'competitions',(select jsonb_agg(to_jsonb(c) order by id) from public.sim_competitions c),
 'attributes',(select jsonb_agg(to_jsonb(a) order by player_id) from public.sim_player_attrs a),
 'ratings',(select jsonb_agg(to_jsonb(r) order by player_id,pos) from public.sim_player_pos_ratings r))
from public.cw_runtime_rules on conflict do nothing;
do $$ declare t text;begin
 foreach t in array array['cw_runtime_rules','cw_runtime','cw_operations','cw_attention_acks','cw_runtime_metrics','cw_catalog_versions'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from public,anon,authenticated',t);
 end loop;
end $$;

create or replace function public.cw_read_career()
returns public.careers language plpgsql stable security definer set search_path=public as $$
declare c public.careers;k int;
begin
 select * into c from public.careers where user_id=(select auth.uid()) and status='active';
 if not found then raise exception 'Carreira ativa não encontrada';end if;
 if now()>=c.energy_reset_at+interval '5 hours' then
 k:=floor(extract(epoch from(now()-c.energy_reset_at))/18000)::int;
 c.energy:=greatest(c.energy,10);c.energy_reset_at:=c.energy_reset_at+k*interval '5 hours';
 end if;
 return c;
end $$;

create or replace function public.cw_tick_probability(p_daily numeric)
returns numeric language sql stable set search_path=public as $$
 select 1-power(1-greatest(0,least(1,p_daily)),least(14,greatest(1,coalesce(nullif(current_setting('app.cw_tick_days',true),'')::int,1))))
$$;

create or replace function public.cw_runtime_enabled(p_career uuid)
returns boolean language sql stable security definer set search_path=public as $$
 select coalesce((select enabled or (deferred_live and not exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null)) from public.cw_runtime where career_id=p_career),false)
 and (select enabled from public.cw_runtime_rules)
$$;

-- País e sistema doméstico são distintos da região continental.
create or replace function public.cw_domestic_club(p_career uuid,p_club text)
returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.sim_clubs c join public.cw_world w on w.career_id=p_career
 join public.career_seasons s on s.id=w.primary_season where c.id=p_club and c.region=s.region)
$$;

create or replace function public.cw_runtime_ensure(p_career uuid)
returns void language plpgsql security definer set search_path=public as $$
begin
 insert into public.cw_runtime(career_id,catalog_version,enabled,last_recovery_day,deferred_live)
 select p_career,r.catalog_version,not exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null),w.elapsed_days,exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null)
 from public.cw_runtime_rules r join public.cw_world w on w.career_id=p_career on conflict do nothing;
 update public.cw_runtime set enabled=true,deferred_live=false where career_id=p_career and not enabled and deferred_live
 and not exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null);
end $$;

create or replace function public.cw_domestic_clubs(p_career uuid)
returns setof text language sql stable security definer set search_path=public as $$
 select c.id from public.sim_clubs c join public.cw_world w on w.career_id=p_career
 join public.career_seasons s on s.id=w.primary_season where c.region=s.region
$$;

create or replace function public.cw_attention(p_career uuid)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare d date;own text;a jsonb;k text;ack text;
begin
 select w.today,c.club_id,r.attention_ack into d,own,ack from public.cw_world w
 join public.mgr_coach c using(career_id) left join public.cw_runtime r using(career_id) where w.career_id=p_career;
 select j into a from(
 select o.created_at ts,jsonb_build_object('id',o.id,'kind','job','expires_on',o.expires_on,'action','offers',
 'key','job:'||o.id||':'||o.negotiation_round||case when o.expires_on<=d+1 then ':deadline' else '' end) j
 from public.season_offers o where o.career_id=p_career and o.kind='coach' and o.status='pending' and o.expires_on>=d
 union all
 select n.created_on::timestamptz,jsonb_build_object('id',n.id,'kind','negotiation','expires_on',n.expires_on,'action','deals',
 'key','neg:'||n.id||':'||n.status||':'||n.round_no||case when n.expires_on<=d+1 then ':deadline' else '' end)
 from public.cw_negotiations n where n.career_id=p_career and n.expires_on>=d
 and n.status in('seller_review','club_counter','player_counter')
 and (n.initiator in('user','renewal') or n.seller_club=own)
 union all
 select w.today::timestamptz,jsonb_build_object('id',cc.career_id,'kind','coach_contract','expires_on',cc.contract_until,'action','contract',
 'key','contract:'||cc.contract_until||case when cc.contract_until<=d+1 then ':deadline' else '' end)
 from public.cw_coach cc join public.cw_world w using(career_id)
 where cc.career_id=p_career and own is not null and cc.contract_until between d and d+7
 union all
 select ct.starts_on::timestamptz,jsonb_build_object('id',ct.id,'kind','player_contract','expires_on',ct.expires_on,'action','contracts',
 'key','player-contract:'||ct.id||':'||ct.expires_on||case when ct.expires_on<=d+1 then ':deadline' else '' end)
 from public.cw_contracts ct where ct.career_id=p_career and ct.club_id=own and ct.status='active' and ct.expires_on between d and d+7
 and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=ct.player_id and n.status in('agreed','precontract'))
 )x where not exists(select 1 from public.cw_attention_acks a where a.career_id=p_career and a.decision_key=x.j->>'key') order by ts limit 1;
 if a is null then return null;end if;
 return a;
end $$;

create or replace function public.career_attention_ack(p_key text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.careers;a jsonb;
begin
 c:=public.mgr_lock();a:=public.cw_attention(c.id);
 if a is null then return jsonb_build_object('ok',true);end if;
 if a->>'key' is distinct from p_key then raise exception 'A decisão mudou. Atualize a carreira';end if;
 insert into public.cw_attention_acks(career_id,decision_key) values(c.id,p_key) on conflict do nothing;
 update public.cw_runtime set attention_ack=p_key,version=version+1 where career_id=c.id;
 return jsonb_build_object('ok',true);
end $$;

-- Recuperação em lote pelo intervalo exato, materializada apenas quando necessária.
create table if not exists public.cw_player_clock(
 career_id uuid not null,player_id text not null,day_no int not null,
 primary key(career_id,player_id),foreign key(career_id,player_id) references public.mgr_players(career_id,player_id));
alter table public.cw_player_clock enable row level security;
revoke all on public.cw_player_clock from public,anon,authenticated;
create or replace function public.cw_recover_club(p_career uuid,p_club text)
returns void language plpgsql security definer set search_path=public as $$
declare day int;start_day int;
begin
 select w.elapsed_days,coalesce(r.last_recovery_day,w.elapsed_days) into day,start_day
 from public.cw_world w left join public.cw_runtime r using(career_id) where w.career_id=p_career;
 update public.mgr_players p set
 condition=least(100,p.condition+4.3*greatest(0,day-coalesce(c.day_no,start_day))),
 rhythm=greatest(35,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))),
 injury=case when p.injured_until<=day then null else p.injury end,
 injured_until=case when p.injured_until<=day then null else p.injured_until end
 from (select mp.player_id,pc.day_no from public.mgr_players mp left join public.cw_player_clock pc using(career_id,player_id)
 where mp.career_id=p_career and mp.club_id=p_club)c
 where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
 insert into public.cw_player_clock(career_id,player_id,day_no)
 select p_career,player_id,day from public.mgr_players where career_id=p_career and club_id=p_club
 on conflict(career_id,player_id) do update set day_no=excluded.day_no where cw_player_clock.day_no<>excluded.day_no;
end $$;

-- Durable receipts are independent of the existing three-day economy cache.
create or replace function public.cw_operation_get(p_career uuid,p_request uuid,p_kind text,p_params jsonb)
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare o public.cw_operations;
begin
 if p_request is null then raise exception 'Identificador da operação obrigatório';end if;
 select * into o from public.cw_operations where career_id=p_career and request_id=p_request;
 if found and (o.kind<>p_kind or o.parameters<>p_params) then raise exception 'Identificador já usado para outra operação';end if;
 return o.result;
end $$;

-- Carry committed legacy operations across a rolling deployment without applying them twice.
create or replace function public.cw_advance_receipt(p_career uuid,p_request uuid,p_days integer)
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
 r:=public.cw_operation_get(p_career,p_request,'advance',jsonb_build_object('days',p_days));
 if r is not null then return r;end if;
 r:=public.econ_request_get(p_career,p_request,'world_advance');
 if r is null then return null;end if;
 r:=r||jsonb_build_object('state_version',(select version from public.cw_runtime where career_id=p_career));
 insert into public.cw_operations(career_id,request_id,kind,parameters,result) values(p_career,p_request,'advance',jsonb_build_object('days',p_days),r);
 return r;
end $$;
revoke all on function public.cw_advance_receipt(uuid,uuid,integer) from public,anon,authenticated;

create index if not exists cw_negotiation_attention_idx on public.cw_negotiations(career_id,expires_on)
 where status in('seller_review','club_counter','player_counter');
create index if not exists cw_offer_pending_idx on public.season_offers(career_id,expires_on) where status='pending' and kind='coach';
create index if not exists cw_finance_month_idx on public.cw_finance(career_id,on_date);
create index if not exists cw_appearance_club_date_idx on public.cw_appearances(career_id,club_id,on_date);
create index if not exists cw_appearance_clause_idx on public.cw_appearances(career_id,player_id,club_id,on_date) where minutes>0;
create index if not exists cw_commitment_due_idx on public.cw_commitments(career_id,due_on) where status='reserved';

-- Only explicit public endpoints are callable. Helpers remain private to the RPC chain.
revoke all on function public.cw_read_career(),public.cw_runtime_enabled(uuid),public.cw_domestic_club(uuid,text),
 public.cw_runtime_ensure(uuid),public.cw_attention(uuid),public.cw_recover_club(uuid,text),public.cw_operation_get(uuid,uuid,text,jsonb)
 from public,anon,authenticated;
revoke all on function public.career_attention_ack(text) from public,anon;
grant execute on function public.career_attention_ack(text) to authenticated;
revoke all on function public.cw_domestic_clubs(uuid) from public,anon,authenticated;
revoke all on function public.cw_tick_probability(numeric) from public,anon,authenticated;
commit;
