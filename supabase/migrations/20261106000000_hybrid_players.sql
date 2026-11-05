-- Fase 2 (banco híbrido): jogadores lidos do catálogo; cada carreira grava só o que mudou.
-- mgr_players, cw_players e cw_contracts passam a ser views com os mesmos nomes e colunas.
-- As tabelas reais viram mgr_player_rows, cw_player_rows e cw_contract_rows.
-- Carreiras antigas (cw_runtime.hybrid = false) mantêm todas as linhas e leem exatamente o mesmo.
-- Ver docs/banco-hibrido.md.

begin;

-- 1. Carreira híbrida e clubes que existem no mundo de cada carreira
alter table public.cw_runtime add column if not exists hybrid boolean not null default false;
alter table public.cw_runtime_rules add column if not exists hybrid_default boolean not null default true;
alter table public.cw_runtime alter column hybrid set default true;

create table if not exists public.cw_world_clubs(
 career_id uuid not null references public.careers(id) on delete cascade,
 club_id text not null references public.sim_clubs(id),
 primary key(career_id,club_id));
alter table public.cw_world_clubs enable row level security;
revoke all on public.cw_world_clubs from anon,authenticated;

create or replace function public.cw_is_hybrid(p_career uuid) returns boolean
language sql stable security definer set search_path=public as $$
 select coalesce((select hybrid from public.cw_runtime where career_id=p_career),(select hybrid_default from public.cw_runtime_rules limit 1),false)
$$;

-- 2. Valores iniciais de cada atleta do catálogo (antes copiados para cada carreira)
create or replace function public.cw_base_value(p_rating numeric,p_age numeric,p_pot numeric) returns bigint
language sql immutable as $$
 select round(greatest(250,40000*power(2,(least(p_rating,99)-80)/4.5))
  *case when p_age<21 then 1.3 when p_age<24 then 1.2 when p_age<28 then 1 when p_age<31 then .8 when p_age<33 then .55 else .3 end
  *(1+greatest(0,p_pot-p_rating)*.03))::bigint
$$;

create table if not exists public.sim_player_base(
 player_id text primary key references public.sim_players(id) on delete cascade,
 rating numeric(5,2) not null,
 age0 integer not null,
 age_estimated boolean not null,
 potential integer not null,
 contract_years integer not null,
 salary0 bigint not null,
 role0 text not null);
alter table public.sim_player_base enable row level security;
revoke all on public.sim_player_base from anon,authenticated;

create or replace function public.sim_player_base_refresh() returns integer
language plpgsql security definer set search_path=public as $$
declare n int;
begin
 insert into public.sim_player_base(player_id,rating,age0,age_estimated,potential,contract_years,salary0,role0)
 select x.id,x.rating,x.age0,x.age_estimated,x.potential,x.contract_years,
  greatest(greatest(50,ceil(power(greatest(1,x.rating-45),2)*.65+power(greatest(0,x.rating-75),2)*12))::bigint,
   round(public.cw_base_value(x.rating,x.age0,x.potential)*.0065)::bigint),
  case when x.is_youth then 'prospect' when x.rating>=82 then 'key' when x.rating>=74 then 'starter' else 'rotation' end
 from(select p.id,r.rating,p.is_youth,coalesce(p.age,case when p.is_youth then 19 else 26 end) age0,p.age is null age_estimated,
   least(99,round(r.rating)+case when coalesce(p.age,case when p.is_youth then 19 else 26 end)<23 then 12 else 3 end)::int potential,
   1+(abs(hashtext(p.id)::bigint)%4)::int contract_years
  from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position
  where p.career_id is null)x
 on conflict(player_id) do update set rating=excluded.rating,age0=excluded.age0,age_estimated=excluded.age_estimated,potential=excluded.potential,
  contract_years=excluded.contract_years,salary0=excluded.salary0,role0=excluded.role0;
 get diagnostics n=row_count;
 return n;
end $$;
select public.sim_player_base_refresh();

-- 3. Tabelas reais ganham o sufixo _rows
alter table public.mgr_players rename to mgr_player_rows;
alter table public.mgr_player_rows add column if not exists removed boolean not null default false;
alter table public.cw_players rename to cw_player_rows;
alter table public.cw_contracts rename to cw_contract_rows;
-- A troca de clube passa a ser tratada no gatilho da view (a linha pode nascer já no clube novo).
drop trigger if exists cw_club_change on public.mgr_player_rows;

-- 4. Chaves estrangeiras: o atleta existe no catálogo, mesmo sem linha própria na carreira
alter table public.cw_player_clock drop constraint if exists cw_player_clock_career_id_player_id_fkey;
alter table public.cw_appearances drop constraint if exists cw_appearances_career_id_player_id_fkey;
alter table public.base_card_roster drop constraint if exists base_card_roster_career_id_player_id_fkey;
alter table public.cw_stats_opening drop constraint if exists cw_stats_opening_career_id_player_id_fkey;
alter table public.cw_player_rows drop constraint if exists cw_players_career_id_player_id_fkey;
alter table public.cw_contract_rows drop constraint if exists cw_contracts_career_id_player_id_fkey;
alter table public.cw_negotiations drop constraint if exists cw_negotiations_career_id_player_id_fkey;
alter table public.cw_negotiations drop constraint if exists cw_negotiations_agreed_owner_contract_career_id_fkey;
alter table public.cw_player_dev drop constraint if exists cw_player_dev_career_id_player_id_fkey;
alter table public.cw_loans drop constraint if exists cw_loans_career_id_player_id_fkey;
alter table public.cw_player_clock add constraint cw_player_clock_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.cw_appearances add constraint cw_appearances_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.base_card_roster add constraint base_card_roster_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.cw_stats_opening add constraint cw_stats_opening_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.cw_player_rows add constraint cw_player_rows_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.cw_player_rows add constraint cw_player_rows_career_fk foreign key(career_id) references public.careers(id) on delete cascade;
alter table public.cw_contract_rows add constraint cw_contract_rows_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.cw_negotiations add constraint cw_negotiations_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.cw_player_dev add constraint cw_player_dev_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;
alter table public.cw_player_dev add constraint cw_player_dev_career_fk foreign key(career_id) references public.careers(id) on delete cascade;
alter table public.cw_loans add constraint cw_loans_player_fk foreign key(player_id) references public.sim_players(id) on delete cascade;

-- 5. Views com os nomes antigos
create view public.mgr_players as
 select r.career_id,r.player_id,r.club_id,r.condition,r.rhythm,r.injured_until,r.injury,r.susp,r.yellows
 from public.mgr_player_rows r where not r.removed
 union all
 select wc.career_id,p.id,p.club_id,100::numeric(5,2),(case when p.is_youth then 50 else 70 end)::numeric(5,2),null::integer,null::text,'{}'::jsonb,'{}'::jsonb
 from public.cw_world_clubs wc join public.sim_players p on p.club_id=wc.club_id and p.active and p.career_id is null
 where not exists(select 1 from public.mgr_player_rows r where r.career_id=wc.career_id and r.player_id=p.id);
alter view public.mgr_players alter column condition set default 100;
alter view public.mgr_players alter column rhythm set default 70;
alter view public.mgr_players alter column susp set default '{}'::jsonb;
alter view public.mgr_players alter column yellows set default '{}'::jsonb;

create view public.cw_players as
 select r.career_id,r.player_id,r.age_at_start,r.potential,r.market_value,r.age_estimated,r.morale,r.promised_role,r.transfer_requested,
  r.last_morale_on,r.last_warning_on,r.shirt_number,r.transfer_listed,r.retired_on,r.loan_listed,r.morale_trend
 from public.cw_player_rows r
 union all
 select mp.career_id,b.player_id,b.age0,b.potential,
  public.cw_base_value(b.rating+coalesce(dv.d_rating,0),b.age0+floor((w.today-w.started_on)/365.25),b.potential),
  b.age_estimated,65::numeric,'rotation'::text,false,null::date,null::date,null::smallint,false,null::date,false,0::smallint
 from public.mgr_players mp
 join public.cw_runtime rt on rt.career_id=mp.career_id and rt.hybrid
 join public.sim_player_base b on b.player_id=mp.player_id
 join public.cw_world w on w.career_id=mp.career_id
 left join public.cw_player_dev dv on dv.career_id=mp.career_id and dv.player_id=mp.player_id
 where not exists(select 1 from public.cw_player_rows r where r.career_id=mp.career_id and r.player_id=mp.player_id);
alter view public.cw_players alter column market_value set default 0;
alter view public.cw_players alter column morale set default 65;
alter view public.cw_players alter column promised_role set default 'rotation';
alter view public.cw_players alter column transfer_requested set default false;
alter view public.cw_players alter column transfer_listed set default false;
alter view public.cw_players alter column loan_listed set default false;
alter view public.cw_players alter column morale_trend set default 0;

-- Contrato da IA sem negociação: calculado. Começa no início do mundo e renova em ciclos do mesmo tamanho,
-- sempre terminando em 31/12 (fim da temporada brasileira), como o alinhamento de cw_contract_align_trg.
create view public.cw_contracts as
 select r.id,r.career_id,r.player_id,r.club_id,r.starts_on,r.expires_on,r.ended_on,r.monthly_salary,r.signing_bonus,r.appearance_bonus,
  r.goal_bonus,r.role,r.status,r.arrears,false as computed
 from public.cw_contract_rows r
 union all
 select md5(mp.career_id::text||':'||mp.player_id)::uuid,mp.career_id,mp.player_id,mp.club_id,
  case when k.k=0 then w.started_on else make_date(k.y0+b.contract_years*k.k-1,12,31)+1 end,
  make_date(k.y0+b.contract_years*(k.k+1)-1,12,31),null::date,b.salary0,0::bigint,0::bigint,0::bigint,b.role0,'active'::text,0::bigint,true
 from public.mgr_players mp
 join public.cw_runtime rt on rt.career_id=mp.career_id and rt.hybrid
 join public.sim_player_base b on b.player_id=mp.player_id
 join public.sim_players sp on sp.id=mp.player_id and sp.club_id=mp.club_id
 join public.cw_world w on w.career_id=mp.career_id
 cross join lateral(select extract(year from w.started_on)::int y0,
  greatest(0,ceil((extract(year from w.today)::int-extract(year from w.started_on)::int-b.contract_years+1)::numeric/b.contract_years))::int k) k
 where mp.club_id is not null
  and not exists(select 1 from public.cw_contract_rows r where r.career_id=mp.career_id and r.player_id=mp.player_id);
alter view public.cw_contracts alter column id set default gen_random_uuid();
alter view public.cw_contracts alter column signing_bonus set default 0;
alter view public.cw_contracts alter column appearance_bonus set default 0;
alter view public.cw_contracts alter column goal_bonus set default 0;
alter view public.cw_contracts alter column status set default 'active';
alter view public.cw_contracts alter column arrears set default 0;
alter view public.cw_contracts alter column computed set default false;

revoke all on public.mgr_players,public.cw_players,public.cw_contracts from anon,authenticated;

-- 6. Gatilhos das views: gravam a diferença e apagam a linha quando ela volta ao padrão
create or replace function public.mgr_players_view_trg() returns trigger
language plpgsql security definer set search_path=public as $$
declare hyb boolean;cat text;youth boolean;in_world boolean:=false;
begin
 if tg_op='DELETE' then
  delete from public.cw_player_dev where career_id=old.career_id and player_id=old.player_id;
  select sp.club_id into cat from public.sim_players sp where sp.id=old.player_id and sp.career_id is null and sp.active;
  if cat is not null and exists(select 1 from public.cw_world_clubs wc where wc.career_id=old.career_id and wc.club_id=cat) then
   insert into public.mgr_player_rows(career_id,player_id,club_id,removed) values(old.career_id,old.player_id,null,true)
   on conflict(career_id,player_id) do update set removed=true,club_id=null;
  else
   delete from public.mgr_player_rows where career_id=old.career_id and player_id=old.player_id;
  end if;
  return old;
 end if;
 if tg_op='UPDATE' and (new.career_id<>old.career_id or new.player_id<>old.player_id) then
  raise exception 'mgr_players: troca de chave não suportada';
 end if;
 new.condition:=coalesce(new.condition,100);new.rhythm:=coalesce(new.rhythm,70);
 new.susp:=coalesce(new.susp,'{}');new.yellows:=coalesce(new.yellows,'{}');
 hyb:=public.cw_is_hybrid(new.career_id);
 if hyb then
  select sp.club_id,sp.is_youth into cat,youth from public.sim_players sp where sp.id=new.player_id and sp.career_id is null and sp.active;
  in_world:=cat is not null and exists(select 1 from public.cw_world_clubs wc where wc.career_id=new.career_id and wc.club_id=cat);
 end if;
 if in_world and new.club_id is not distinct from cat and new.condition=100 and new.rhythm=(case when youth then 50 else 70 end)
  and new.injured_until is null and new.injury is null and new.susp='{}'::jsonb and new.yellows='{}'::jsonb then
  delete from public.mgr_player_rows where career_id=new.career_id and player_id=new.player_id;
 else
  insert into public.mgr_player_rows(career_id,player_id,club_id,condition,rhythm,injured_until,injury,susp,yellows,removed)
  values(new.career_id,new.player_id,new.club_id,new.condition,new.rhythm,new.injured_until,new.injury,new.susp,new.yellows,false)
  on conflict(career_id,player_id) do update set club_id=excluded.club_id,condition=excluded.condition,rhythm=excluded.rhythm,
   injured_until=excluded.injured_until,injury=excluded.injury,susp=excluded.susp,yellows=excluded.yellows,removed=false;
 end if;
 if tg_op='UPDATE' and new.club_id is distinct from old.club_id then
  update public.cw_players set transfer_listed=false where career_id=new.career_id and player_id=new.player_id and transfer_listed;
  if new.club_id is not null then perform public.cw_assign_number(new.career_id,new.player_id,new.club_id);end if;
 end if;
 return new;
end $$;
create trigger mgr_players_iud instead of insert or update or delete on public.mgr_players for each row execute function public.mgr_players_view_trg();

create or replace function public.cw_players_view_trg() returns trigger
language plpgsql security definer set search_path=public as $$
declare b public.sim_player_base;w public.cw_world;dr numeric;dflt boolean:=false;
begin
 if tg_op='DELETE' then
  delete from public.cw_player_rows where career_id=old.career_id and player_id=old.player_id;
  return old;
 end if;
 if tg_op='UPDATE' and (new.career_id<>old.career_id or new.player_id<>old.player_id) then
  raise exception 'cw_players: troca de chave não suportada';
 end if;
 new.market_value:=coalesce(new.market_value,0);new.morale:=coalesce(new.morale,65);new.promised_role:=coalesce(new.promised_role,'rotation');
 new.transfer_requested:=coalesce(new.transfer_requested,false);new.transfer_listed:=coalesce(new.transfer_listed,false);
 new.loan_listed:=coalesce(new.loan_listed,false);new.morale_trend:=coalesce(new.morale_trend,0);
 if public.cw_is_hybrid(new.career_id) then
  select * into b from public.sim_player_base where player_id=new.player_id;
  if b.player_id is not null and exists(select 1 from public.mgr_players mp where mp.career_id=new.career_id and mp.player_id=new.player_id) then
   select * into w from public.cw_world where career_id=new.career_id;
   select d_rating into dr from public.cw_player_dev where career_id=new.career_id and player_id=new.player_id;
   dflt:=w.career_id is not null and new.age_at_start=b.age0 and new.potential=b.potential and new.age_estimated=b.age_estimated
    and new.market_value=public.cw_base_value(b.rating+coalesce(dr,0),b.age0+floor((w.today-w.started_on)/365.25),b.potential)
    and new.morale=65 and new.promised_role='rotation' and not new.transfer_requested and new.last_morale_on is null and new.last_warning_on is null
    and new.shirt_number is null and not new.transfer_listed and new.retired_on is null and not new.loan_listed and new.morale_trend=0;
  end if;
 end if;
 if dflt then
  delete from public.cw_player_rows where career_id=new.career_id and player_id=new.player_id;
 else
  insert into public.cw_player_rows(career_id,player_id,age_at_start,potential,market_value,age_estimated,morale,promised_role,transfer_requested,
   last_morale_on,last_warning_on,shirt_number,transfer_listed,retired_on,loan_listed,morale_trend)
  values(new.career_id,new.player_id,new.age_at_start,new.potential,new.market_value,new.age_estimated,new.morale,new.promised_role,new.transfer_requested,
   new.last_morale_on,new.last_warning_on,new.shirt_number,new.transfer_listed,new.retired_on,new.loan_listed,new.morale_trend)
  on conflict(career_id,player_id) do update set age_at_start=excluded.age_at_start,potential=excluded.potential,market_value=excluded.market_value,
   age_estimated=excluded.age_estimated,morale=excluded.morale,promised_role=excluded.promised_role,transfer_requested=excluded.transfer_requested,
   last_morale_on=excluded.last_morale_on,last_warning_on=excluded.last_warning_on,shirt_number=excluded.shirt_number,transfer_listed=excluded.transfer_listed,
   retired_on=excluded.retired_on,loan_listed=excluded.loan_listed,morale_trend=excluded.morale_trend;
 end if;
 return new;
end $$;
create trigger cw_players_iud instead of insert or update or delete on public.cw_players for each row execute function public.cw_players_view_trg();

create or replace function public.cw_contracts_view_trg() returns trigger
language plpgsql security definer set search_path=public as $$
declare r public.cw_contract_rows;d date;
begin
 if tg_op='DELETE' then
  if old.computed then
   -- Contrato calculado não tem linha: registra o encerramento para que ele não volte a aparecer.
   select today into d from public.cw_world where career_id=old.career_id;
   insert into public.cw_contract_rows(id,career_id,player_id,club_id,starts_on,expires_on,ended_on,monthly_salary,role,status)
   values(old.id,old.career_id,old.player_id,old.club_id,old.starts_on,old.expires_on,coalesce(d,old.starts_on),old.monthly_salary,old.role,'ended');
  else
   delete from public.cw_contract_rows where id=old.id;
  end if;
  return old;
 end if;
 if tg_op='INSERT' then
  insert into public.cw_contract_rows(id,career_id,player_id,club_id,starts_on,expires_on,ended_on,monthly_salary,signing_bonus,appearance_bonus,goal_bonus,role,status,arrears)
  values(coalesce(new.id,gen_random_uuid()),new.career_id,new.player_id,new.club_id,new.starts_on,new.expires_on,new.ended_on,new.monthly_salary,
   coalesce(new.signing_bonus,0),coalesce(new.appearance_bonus,0),coalesce(new.goal_bonus,0),new.role,coalesce(new.status,'active'),coalesce(new.arrears,0))
  returning * into r;
 elsif old.computed then
  insert into public.cw_contract_rows(id,career_id,player_id,club_id,starts_on,expires_on,ended_on,monthly_salary,signing_bonus,appearance_bonus,goal_bonus,role,status,arrears)
  values(old.id,new.career_id,new.player_id,new.club_id,new.starts_on,new.expires_on,new.ended_on,new.monthly_salary,
   new.signing_bonus,new.appearance_bonus,new.goal_bonus,new.role,new.status,new.arrears)
  returning * into r;
 else
  update public.cw_contract_rows set career_id=new.career_id,player_id=new.player_id,club_id=new.club_id,starts_on=new.starts_on,expires_on=new.expires_on,
   ended_on=new.ended_on,monthly_salary=new.monthly_salary,signing_bonus=new.signing_bonus,appearance_bonus=new.appearance_bonus,goal_bonus=new.goal_bonus,
   role=new.role,status=new.status,arrears=new.arrears
  where id=old.id returning * into r;
 end if;
 new.id:=r.id;new.career_id:=r.career_id;new.player_id:=r.player_id;new.club_id:=r.club_id;new.starts_on:=r.starts_on;new.expires_on:=r.expires_on;
 new.ended_on:=r.ended_on;new.monthly_salary:=r.monthly_salary;new.signing_bonus:=r.signing_bonus;new.appearance_bonus:=r.appearance_bonus;
 new.goal_bonus:=r.goal_bonus;new.role:=r.role;new.status:=r.status;new.arrears:=r.arrears;new.computed:=false;
 return new;
end $$;
create trigger cw_contracts_iud instead of insert or update or delete on public.cw_contracts for each row execute function public.cw_contracts_view_trg();

-- Carreiras existentes continuam no modo antigo
update public.cw_runtime set hybrid=false;

commit;
