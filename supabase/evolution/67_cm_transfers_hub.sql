-- Evolução 67 — Transferências no formato do CM17: pré-seleção de atletas observados.
-- A aba "Mundo" vira Transferências (busca, pré-seleção, olheiros, negociações e lista de venda); notícias chegam
-- pela Caixa de entrada e as finanças ficam no Clube (só frontend). Aqui entra apenas a lista de pré-seleção.
begin;

create table if not exists public.cw_shortlist(
 career_id uuid not null references public.careers(id) on delete cascade,
 player_id text not null references public.sim_players(id),
 added_on timestamptz not null default now(),
 primary key(career_id,player_id));
alter table public.cw_shortlist enable row level security;
revoke all on public.cw_shortlist from public,anon,authenticated;

create or replace function public.career_shortlist_toggle(p_player text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car public.careers;on_list boolean;
begin
 car:=public.mgr_lock();
 if not exists(select 1 from public.sim_players where id=p_player and active) then raise exception 'Atleta não encontrado';end if;
 delete from public.cw_shortlist where career_id=car.id and player_id=p_player;
 if not found then
  if (select count(*) from public.cw_shortlist where career_id=car.id)>=50 then raise exception 'A pré-seleção aceita até 50 atletas.';end if;
  insert into public.cw_shortlist(career_id,player_id) values(car.id,p_player);on_list:=true;
 else on_list:=false;end if;
 return jsonb_build_object('ok',true,'shortlisted',on_list);
end $$;

create or replace function public.career_shortlist()
returns jsonb language plpgsql stable security definer set search_path=public as $$
declare car uuid:=public.cw_current_career();w public.cw_world;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select * into w from public.cw_world where career_id=car;
 return(select coalesce(jsonb_agg(to_jsonb(x) order by x.overall desc,x.id),'[]') from(
  select sp.id,sp.full_name name,sp.short_name,sp.position,e.club_id,sp.nationality,round(pr.rating) overall,
   coalesce(cp.age_at_start,sp.age,case when sp.is_youth then 19 else 26 end)+coalesce(floor((w.today-w.started_on)/365.25)::int,0) age,
   public.cw_player_value(car,sp.id) value,ct.monthly_salary,ct.expires_on,true shortlisted
  from public.cw_shortlist s join public.sim_players sp on sp.id=s.player_id
  join public.sim_player_pos_ratings pr on pr.player_id=sp.id and pr.pos=sp.position
  left join public.cw_players cp on cp.career_id=car and cp.player_id=sp.id
  cross join lateral(select public.cw_effective_player_club(car,sp.id) club_id)e
  left join public.cw_contracts ct on ct.career_id=car and ct.player_id=sp.id and ct.status='active'
  where s.career_id=car)x);
end $$;

revoke all on function public.career_shortlist_toggle(text),public.career_shortlist() from public,anon;
grant execute on function public.career_shortlist_toggle(text),public.career_shortlist() to authenticated;
notify pgrst,'reload schema';
commit;
