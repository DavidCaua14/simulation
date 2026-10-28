-- EVOLUÇÃO 15: integridade por carreira e calendário equilibrado.
-- Executar depois de 14, em transação. Não apaga resultados nem recria temporadas.
begin;

create unique index if not exists career_seasons_identity_uq on public.career_seasons(id, career_id);
create unique index if not exists mgr_spells_identity_uq on public.mgr_spells(id,career_id);
create unique index if not exists season_fixtures_identity_uq on public.season_fixtures(id, season_id);
create unique index if not exists season_fixtures_pair_uq
 on public.season_fixtures(season_id, competition_id, stage, home_club, away_club);
create unique index if not exists season_fixtures_tie_leg_uq
 on public.season_fixtures(season_id, competition_id, stage, tie_no, leg) where tie_no is not null;

do $$
declare t text;
begin
 foreach t in array array['mgr_matches','mgr_objectives','mgr_messages','mgr_transfers','season_offers','season_transitions'] loop
  if not exists(select 1 from pg_constraint where conname=t||'_season_owner_fk') then
   execute format('alter table public.%I add constraint %I foreign key (%I, career_id) references public.career_seasons(id, career_id)',
                  t,t||'_season_owner_fk',case when t='season_transitions' then 'from_season' else 'season_id' end);
  end if;
 end loop;
 foreach t in array array['mgr_objectives','mgr_coach'] loop
  if not exists(select 1 from pg_constraint where conname=t||'_spell_owner_fk') then
   execute format('alter table public.%I add constraint %I foreign key(spell_id,career_id) references public.mgr_spells(id,career_id)',t,t||'_spell_owner_fk');
  end if;
 end loop;
 if not exists(select 1 from pg_constraint where conname='mgr_matches_fixture_season_fk') then
  alter table public.mgr_matches add constraint mgr_matches_fixture_season_fk
    foreign key(fixture_id,season_id) references public.season_fixtures(id,season_id);
 end if;
end $$;

-- Um clube só pode jogar UMA vez em cada rodada, inclusive como visitante.
-- A chave diferida permite permutar rodadas em uma única transação.
create table if not exists public.season_fixture_slots (
 season_id uuid not null, competition_id text not null, stage text not null, round_no int not null,
 club_id text not null, fixture_id bigint not null references public.season_fixtures(id) on delete cascade,
 primary key(season_id,competition_id,stage,round_no,club_id) deferrable initially deferred
);
alter table public.season_fixture_slots enable row level security;
revoke all on public.season_fixture_slots from public,anon,authenticated;
-- Reconstrução somente deste índice auxiliar; os jogos nunca são apagados.
-- DELETE + INSERT torna a própria migração repetível sem depender de ON CONFLICT em chave diferida.
delete from public.season_fixture_slots;
insert into public.season_fixture_slots
 select season_id,competition_id,stage,round_no,home_club,id from public.season_fixtures
 union all select season_id,competition_id,stage,round_no,away_club,id from public.season_fixtures;

create or replace function public.sim_fixture_integrity()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 if tg_op='UPDATE' and old.status='played' then
  if row(new.season_id,new.competition_id,new.stage,new.round_no,new.group_label,new.tie_no,new.leg,
         new.home_club,new.away_club,new.home_goals,new.away_goals,new.status,new.played_at)
     is distinct from
     row(old.season_id,old.competition_id,old.stage,old.round_no,old.group_label,old.tie_no,old.leg,
         old.home_club,old.away_club,old.home_goals,old.away_goals,old.status,old.played_at)
     or (old.tie_winner is not null and new.tie_winner is distinct from old.tie_winner)
     or (old.home_pens is not null and row(new.home_pens,new.away_pens) is distinct from row(old.home_pens,old.away_pens)) then
   raise exception 'Resultado disputado é imutável: partida %',old.id;
  end if;
 end if;
 if new.home_club=new.away_club then raise exception 'Um clube não pode enfrentar a si mesmo'; end if;
 if new.status='played' and (new.home_goals is null or new.away_goals is null or least(new.home_goals,new.away_goals)<0) then
  raise exception 'Partida encerrada precisa de placar válido';
 end if;
 return new;
end $$;
drop trigger if exists sim_fixture_integrity_trg on public.season_fixtures;
create trigger sim_fixture_integrity_trg before insert or update on public.season_fixtures
 for each row execute function public.sim_fixture_integrity();

create or replace function public.sim_fixture_slots_sync()
returns trigger language plpgsql security definer set search_path=public as $$
begin
 delete from public.season_fixture_slots where fixture_id=new.id;
 insert into public.season_fixture_slots values
 (new.season_id,new.competition_id,new.stage,new.round_no,new.home_club,new.id),
 (new.season_id,new.competition_id,new.stage,new.round_no,new.away_club,new.id);
 return null;
end $$;
drop trigger if exists sim_fixture_slots_trg on public.season_fixtures;
create trigger sim_fixture_slots_trg after insert or update of round_no,home_club,away_club,season_id,competition_id,stage
 on public.season_fixtures for each row execute function public.sim_fixture_slots_sync();

-- Berger: alterna a mesa fixa e inverte as demais mesas em mesas alternadas.
-- O returno começa pela segunda rodada da ida: impede uma sequência de três na virada.
create or replace function public.sim_round_robin(p_teams text[], p_double boolean default true)
returns table(round_no int,home text,away text) language plpgsql as $$
declare n int:=cardinality(p_teams); arr text[]:=p_teams; r int; i int; h text; a text;
begin
 if n is null or n<2 or n%2<>0 or n<>(select count(distinct x) from unnest(p_teams) x) then
  raise exception 'Liga requer lista par, sem clubes repetidos ou nulos';
 end if;
 for r in 1..n-1 loop
  for i in 1..n/2 loop
   h:=arr[i]; a:=arr[n-i+1];
   if (i=1 and r%2=0) or (i>1 and i%2=0) then h:=arr[n-i+1]; a:=arr[i]; end if;
   round_no:=r;home:=h;away:=a;return next;
   if p_double then
    round_no:=n-1+case when n=2 then 1 else ((r-2+n-1)%(n-1))+1 end;
    home:=a;away:=h;return next;
   end if;
  end loop;
  arr:=array[arr[1],arr[n]]||arr[2:n-1];
 end loop;
end $$;

-- Custo de sequências acima de dois jogos no mesmo mando. Usado também para
-- comparar a reparação com o calendário anterior, sem aceitar piora global.
create or replace function public.sim_calendar_cost(p_season uuid,p_comp text,p_stage text,p_rounds int[] default null,p_fixed int default 0)
returns bigint language sql stable set search_path=public as $$
 with games as (
  select x.club,x.venue,case when f.round_no<=p_fixed or p_rounds is null then f.round_no
      else p_fixed+array_position(p_rounds,f.round_no) end as r
  from public.season_fixtures f cross join lateral(values(f.home_club,'h'),(f.away_club,'a')) x(club,venue)
  where f.season_id=p_season and f.competition_id=p_comp and f.stage=p_stage
 ), islands as (
  select *,row_number() over(partition by club order by r)-row_number() over(partition by club,venue order by r) as island from games
 ), runs as(select club,venue,island,count(*) as n from islands group by club,venue,island)
 select coalesce(sum(greatest(n-2,0)*greatest(n-2,0)),0)::bigint from runs
$$;

create table if not exists public.season_schedule_changes (
 fixture_id bigint primary key references public.season_fixtures(id),
 season_id uuid not null references public.career_seasons(id), previous_round int not null,new_round int not null,
 changed_at timestamptz not null default now()
);
alter table public.season_schedule_changes enable row level security;
revoke all on public.season_schedule_changes from public,anon,authenticated;

-- Reordena somente RODADAS INTEIRAMENTE futuras. Uma rodada com partida disputada
-- ou com estado de partida já criado fixa todo o prefixo. IDs, adversários, mando e
-- resultados são preservados; não é possível desfazer uma sequência já disputada.
create or replace function public.sim_rebalance_pending(p_season uuid,p_comp text,p_stage text default 'league')
returns jsonb language plpgsql security definer set search_path=public as $$
declare
 fixed int; round_slots int[]; remaining int[]; chosen int[]:='{}'; best_order int[]; candidate int; best int; score bigint; best_score bigint;
 old_cost bigint; new_cost bigint; r record; state jsonb:='{}'; club text; venue text; previous text; run int; cost bigint; changed int:=0;
begin
 perform 1 from public.careers where id=(select career_id from public.career_seasons where id=p_season) for update;
 perform 1 from public.career_seasons where id=p_season and status='active' for update;
 if not found then return jsonb_build_object('changed',0); end if;
 if coalesce(public.sim_phase(p_comp,p_stage)->>'type','')<>'league' then raise exception 'Reparação disponível apenas para ligas'; end if;
 select coalesce(max(f.round_no),0) into fixed from public.season_fixtures f
 where f.season_id=p_season and f.competition_id=p_comp and f.stage=p_stage
 and (f.status='played' or exists(select 1 from public.mgr_matches m where m.fixture_id=f.id));
 select array_agg(distinct round_no order by round_no) into remaining from public.season_fixtures
 where season_id=p_season and competition_id=p_comp and stage=p_stage and round_no>fixed;
 if cardinality(remaining) is null then return jsonb_build_object('changed',0); end if;
 -- Só permuta números de rodada existentes: não cria rodadas extras.
 round_slots:=remaining;best_order:=remaining; old_cost:=public.sim_calendar_cost(p_season,p_comp,p_stage); new_cost:=old_cost;
 if old_cost=0 then return jsonb_build_object('changed',0,'before',0,'after',0);end if;
 -- Busca local: trocas de rodadas reduzem estritamente o custo; termina em ótimo local.
 -- Não há sorteio global nem acesso a dados de outras temporadas/carreiras.
 for pass in 1..10 loop
  best_score:=new_cost;
  for i in 1..cardinality(remaining)-1 loop
   for j in i+1..cardinality(remaining) loop
    chosen:=best_order;candidate:=chosen[i];chosen[i]:=chosen[j];chosen[j]:=candidate;
    score:=public.sim_calendar_cost(p_season,p_comp,p_stage,chosen,fixed);
    if score<best_score then best_score:=score;remaining:=chosen; end if;
   end loop;
  end loop;
  exit when best_score>=new_cost;
  best_order:=remaining;new_cost:=best_score;
  exit when new_cost=0;
 end loop;
 if new_cost>=old_cost then return jsonb_build_object('changed',0,'before',old_cost,'after',old_cost); end if;
 -- Chave diferida protege os clubes durante a troca atômica de rodadas.
 insert into public.season_schedule_changes(fixture_id,season_id,previous_round,new_round)
 select id,season_id,round_no,round_slots[array_position(best_order,round_no)]
 from public.season_fixtures where season_id=p_season and competition_id=p_comp and stage=p_stage and round_no>fixed
 and round_no<>round_slots[array_position(best_order,round_no)]
 on conflict(fixture_id) do update set new_round=excluded.new_round,changed_at=now();
 update public.season_fixtures set round_no=round_slots[array_position(best_order,round_no)]
 where season_id=p_season and competition_id=p_comp and stage=p_stage and round_no>fixed
 and round_no<>round_slots[array_position(best_order,round_no)];
 get diagnostics changed=row_count;
 return jsonb_build_object('changed',changed,'before',old_cost,'after',new_cost,'fixed_through',fixed);
end $$;

-- Funções internas: não ficam disponíveis a usuários, mesmo por RPC manual.
revoke all on function public.sim_fixture_integrity(),public.sim_fixture_slots_sync(),
 public.sim_calendar_cost(uuid,text,text,int[],int),public.sim_rebalance_pending(uuid,text,text) from public,anon,authenticated;
commit;
