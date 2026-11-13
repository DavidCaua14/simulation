-- MODO ONLINE — Fase 21: catálogo maior e lendas que evoluem.
--  • Lendas são lendas do futebol (em atividade ou não), não só aposentados. on_legends ganha pot: a lenda
--    evolui no treino até ele, e o pot pode passar de 100 (Messi 98 → 107). As lendas antigas ganham pot também:
--    nota + 9 (96+), + 7 (92+), + 6 (88+) ou + 5.
--  • on_catalog_extra: jogadores reais que faltavam no catálogo do jogo (sim_players), só para o modo online:
--    destaques de ligas fora do catálogo e jogadores conhecidos do Brasileirão. Se o mesmo nome aparecer em
--    sim_players, vale o de sim_players (o extra some do on_pool).
--  • Cartas base: as faixas 2, 3 e 4 preferem jogadores da Série A do Brasil (sim_clubs.tier = 'serie_a' ou
--    extra marcado br), para o Brasileirão aparecer toda hora no mercado.

alter table public.on_legends add column if not exists pot smallint;
update public.on_legends set pot=rating+case when rating>=96 then 9 when rating>=92 then 7 when rating>=88 then 6 else 5 end
 where pot is null or pot<rating;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='on_legends_pot_check') then
  alter table public.on_legends add constraint on_legends_pot_check check (pot is null or pot between rating and 110);
 end if;
end $$;

create table if not exists public.on_catalog_extra(
 id text primary key check (id like 'ex-%'),
 name text not null,
 pos text not null references public.sim_positions(code),
 sec text[] not null default '{}',
 nat text not null,
 rating smallint not null check (rating between 50 and 95),
 age smallint not null check (age between 16 and 45),
 pot smallint not null,
 br boolean not null default false,
 check (pot between rating and 99)
);
alter table public.on_catalog_extra enable row level security;
revoke all on public.on_catalog_extra from anon,authenticated;

-- Catálogo do modo: reais do jogo, extras (sem repetir nome do jogo) e lendas com o pot próprio.
create or replace view public.on_pool as
 select p.id,coalesce(nullif(p.short_name,''),p.full_name) name,p.position pos,coalesce(p.secondary_positions,'{}') sec,
  coalesce(p.nationality,'BRA') nat,coalesce(b.rating,p.attr_level)::numeric rating,
  coalesce(b.age0,p.age,25)::int age,coalesce(b.potential,p.attr_level+2)::int pot,false legend
 from public.sim_players p left join public.sim_player_base b on b.player_id=p.id
 where p.career_id is null and p.active and coalesce(b.rating,p.attr_level) is not null
 union all
 select e.id,e.name,e.pos,e.sec,e.nat,e.rating::numeric,e.age::int,e.pot::int,false from public.on_catalog_extra e
 where not exists(select 1 from public.sim_players s where s.career_id is null and s.active
  and (lower(s.full_name)=lower(e.name) or lower(s.short_name)=lower(e.name)))
 union all
 select l.id,l.name,l.pos,l.sec,l.nat,l.rating::numeric,30,coalesce(l.pot,l.rating)::int,true from public.on_legends l;
revoke all on public.on_pool from anon,authenticated;

-- Jogador do Brasileirão (Série A): clube do catálogo ou extra marcado.
create or replace function public.on_is_br(p_id text) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.sim_players s join public.sim_clubs c on c.id=s.club_id where s.id=p_id and c.tier='serie_a')
  or exists(select 1 from public.on_catalog_extra e where e.id=p_id and e.br)
$$;

-- Lenda pode passar de 95 de potencial (até 110).
do $$ begin
 perform public.on_patch('public.on_real_insert(text,integer,integer,integer,boolean,integer,integer)',
  'greatest(a.lvl,least(95,p.pot))::smallint',
  'greatest(a.lvl,least(case when p.legend then 110 else 95 end,p.pot))::smallint');
end $$;

-- Carta base da faixa p_tier (1 a 5) na posição p_pos. Faixas 2, 3 e 4 preferem o Brasileirão.
create or replace function public.on_gen_base(p_seed text,p_tier int,p_pos text) returns text
language plpgsql security definer set search_path=public as $$
declare t int:=greatest(1,least(5,p_tier));
 v_lo numeric:=(array[78,75,72,66,60])[t];v_hi numeric:=(array[80.5,78,75,74,74])[t];
 v_age int:=(array[40,40,27,23,21])[t];v_gap int:=(array[0,0,0,6,10])[t];v_br boolean:=t in(2,3,4);
 v_end int:=(select max(id) from public.on_seasons)+1+floor(public.sim_hash01(p_seed||':ct')*2)::int;
 v_src text;v_id text;
begin
 select p.id into v_src from public.on_pool p
 where not p.legend and p.rating>=v_lo and p.rating<v_hi and p.age<=v_age and p.pot>=round(p.rating)+v_gap
  and not exists(select 1 from public.on_players o where o.src=p.id)
 order by case when v_br and not public.on_is_br(p.id) then 2 else 0 end+(p.pos is distinct from p_pos)::int,
  public.sim_hash01(p_seed||':'||p.id) limit 1;
 v_src:=coalesce(v_src,public.on_real_pick(p_pos,v_lo,v_hi,p_seed),public.on_real_pick(null,v_lo,v_hi,p_seed));
 if v_src is not null then
  v_id:=public.on_real_insert(v_src,null,null,v_end);
  update public.on_players set star=level>=80 where id=v_id;
  return v_id;
 end if;
 -- catálogo sem ninguém livre na faixa: jogador gerado com o mesmo perfil
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,agg,disc,star)
 select null,public.cw_regen_name('BRA',p_seed),coalesce(p_pos,'MC'),a.age,a.lvl,
  least(94,a.lvl+v_gap+floor(public.sim_hash01(p_seed||':pot')*6)::int),
  a.lvl,public.on_wage(a.lvl),v_end,35+floor(public.sim_hash01(p_seed||':agg')*40)::int,40+floor(public.sim_hash01(p_seed||':disc')*45)::int,a.lvl>=80
 from(select 18+floor(public.sim_hash01(p_seed||':age')*(least(v_age,32)-17))::int age,
  floor(v_lo+public.sim_hash01(p_seed||':lvl')*(least(v_hi,80.5)-v_lo))::int lvl) a
 returning id into v_id;
 return v_id;
end $$;

-- Lendas já contratadas passam a evoluir até o pot novo.
update public.on_players p set pot=l.pot from public.on_legends l where p.src=l.id and p.legend and p.pot<l.pot;

revoke all on function public.on_is_br(text),public.on_gen_base(text,int,text) from public,anon,authenticated;
