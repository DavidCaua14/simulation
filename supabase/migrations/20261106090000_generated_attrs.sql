-- Atributos do catálogo calculados na hora (Fase 1 do universo em níveis).
--
-- Os atributos importados por scripts/build-squads.mjs são estimativa: posição + nível + variação
-- determinística por jogador (hash do id). Em vez de guardar 16 números por atleta, o catálogo
-- guarda só a posição usada e o nível (`sim_players.attr_pos`, `sim_players.attr_level`), e a view
-- `sim_player_attrs` recalcula os mesmos valores, idênticos aos antigos.
--
-- `sim_player_attr_rows` continua guardando o que não dá para calcular: atributos curados à mão
-- (estimated = false), jovens da base (method = 'regen') e qualquer edição feita pela view.
-- Linha própria sempre vence o valor calculado.

-- 1) Hash igual ao hash01 do build-squads.mjs (FNV-1a de 32 bits + mistura final), para ids ASCII.
create or replace function public.sim_hash01(p text) returns double precision
language plpgsql immutable strict parallel safe set search_path=public as $$
declare h bigint:=2166136261;i int;
begin
 for i in 1..length(p) loop
  h:=(h # ascii(substr(p,i,1)))&4294967295;
  h:=(h*16777619)&4294967295;
 end loop;
 h:=h # (h>>13);
 h:=(h*1540483477)&4294967295;
 h:=h # (h>>15);
 return h/4294967296.0;
end $$;

-- 2) Perfil de cada posição: deslocamento de cada atributo em relação ao nível (TEMPLATE do build-squads.mjs).
-- Ordem dos atributos: gk_reflexes, gk_handling, gk_positioning, marking, tackling, positioning, heading,
-- passing, vision, technique, stamina, finishing, off_ball, pace, dribbling, strength.
create table if not exists public.sim_attr_template(
 pos text primary key,
 d smallint[] not null check (array_length(d,1)=16)
);
alter table public.sim_attr_template enable row level security;
insert into public.sim_attr_template(pos,d) values
 ('GOL',array[6,4,4,-38,-38,-30,-28,-16,-20,-22,-14,-48,-46,-24,-36,-6]::smallint[]),
 ('ZAG',array[-52,-52,-52,6,6,6,7,-6,-12,-10,-2,-26,-20,-6,-16,5]::smallint[]),
 ('LD',array[-52,-52,-52,1,2,0,-7,-1,-6,-3,6,-18,-5,6,-2,-4]::smallint[]),
 ('LE',array[-52,-52,-52,1,2,0,-7,-1,-6,-3,6,-18,-5,6,-2,-4]::smallint[]),
 ('VOL',array[-52,-52,-52,4,5,4,-2,1,-3,-2,5,-16,-12,-6,-8,3]::smallint[]),
 ('MC',array[-52,-52,-52,-3,-1,-1,-7,5,3,3,5,-9,-4,-4,-1,-2]::smallint[]),
 ('MEI',array[-52,-52,-52,-16,-14,-12,-12,5,7,6,-1,-4,2,-3,4,-6]::smallint[]),
 ('PD',array[-52,-52,-52,-18,-16,-16,-12,-2,-4,3,2,-3,3,8,6,-6]::smallint[]),
 ('PE',array[-52,-52,-52,-18,-16,-16,-12,-2,-4,3,2,-3,3,8,6,-6]::smallint[]),
 ('ATA',array[-52,-52,-52,-24,-22,-20,2,-8,-9,-2,-4,8,6,1,-1,3]::smallint[])
on conflict (pos) do update set d=excluded.d;

-- 3) Gerador: atributo = clamp(nível + perfil da posição + round((hash(atributo:id) - 0,5) * 10), 12, 96).
-- O nível já inclui o ajuste que o build-squads.mjs faz para a nota na posição principal bater com o nível.
create or replace function public.sim_attr_gen(p_id text,p_pos text,p_level int)
returns table(gk_reflexes smallint,gk_handling smallint,gk_positioning smallint,marking smallint,tackling smallint,
 positioning smallint,heading smallint,passing smallint,vision smallint,technique smallint,stamina smallint,
 finishing smallint,off_ball smallint,pace smallint,dribbling smallint,strength smallint)
language plpgsql immutable strict parallel safe set search_path=public as $$
declare t smallint[];v smallint[]:='{}';i int;
 names constant text[]:=array['gk_reflexes','gk_handling','gk_positioning','marking','tackling','positioning','heading',
  'passing','vision','technique','stamina','finishing','off_ball','pace','dribbling','strength'];
begin
 select x.d into t from public.sim_attr_template x where x.pos=p_pos;
 if t is null then return;end if;
 for i in 1..16 loop
  v:=v||greatest(12,least(96,p_level+t[i]+floor((public.sim_hash01(names[i]||':'||p_id)-.5)*10+.5)::int))::smallint;
 end loop;
 return query select v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8],v[9],v[10],v[11],v[12],v[13],v[14],v[15],v[16];
end $$;
revoke all on function public.sim_hash01(text) from public,anon,authenticated;
revoke all on function public.sim_attr_gen(text,text,int) from public,anon,authenticated;

-- 4) Nível e posição usados pelo gerador. Nulo = atleta sem atributos calculados (só linha própria).
alter table public.sim_players add column if not exists attr_pos text references public.sim_attr_template(pos);
alter table public.sim_players add column if not exists attr_level smallint check (attr_level between 1 and 99);

-- 5) Preenche nível e posição a partir dos atributos estimados atuais (só onde reproduz os 16 valores).
do $$
begin
 if to_regclass('public.sim_player_attr_rows') is not null then return;end if;
 with a as (select x.player_id,p.position,j.ord::int i,j.v::int v
   from public.sim_player_attrs x join public.sim_players p on p.id=x.player_id
   cross join lateral unnest(array[x.gk_reflexes,x.gk_handling,x.gk_positioning,x.marking,x.tackling,x.positioning,x.heading,
    x.passing,x.vision,x.technique,x.stamina,x.finishing,x.off_ball,x.pace,x.dribbling,x.strength]) with ordinality j(v,ord)
   where x.estimated and x.method<>'regen' and p.position in(select pos from public.sim_attr_template)),
 b as (select a.*,t.d[a.i]+floor((public.sim_hash01((array['gk_reflexes','gk_handling','gk_positioning','marking','tackling','positioning','heading',
   'passing','vision','technique','stamina','finishing','off_ball','pace','dribbling','strength'])[a.i]||':'||a.player_id)-.5)*10+.5)::int base
   from a join public.sim_attr_template t on t.pos=a.position),
 k as (select player_id,mode() within group(order by v-base) k from b where v>12 and v<96 group by 1),
 ok as (select b.player_id,max(b.position) pos,max(k.k) k from b join k using(player_id) group by b.player_id
   having bool_and(b.v=greatest(12,least(96,k.k+b.base))))
 update public.sim_players p set attr_pos=ok.pos,attr_level=ok.k from ok where p.id=ok.player_id;
end $$;

-- 6) Tabela vira "linhas próprias"; a view com o nome antigo junta linhas próprias + calculados.
do $$
begin
 if to_regclass('public.sim_player_attr_rows') is not null then return;end if;
 alter table public.sim_player_attrs rename to sim_player_attr_rows;
 alter index public.sim_player_attrs_pkey rename to sim_player_attr_rows_pkey;
end $$;

-- Um atributo calculado (mesma conta do sim_attr_gen), para usar coluna a coluna na view.
create or replace function public.sim_attr_calc(p_id text,p_attr text,p_level int,p_delta int) returns smallint
language sql immutable strict parallel safe set search_path=public as $$
 select greatest(12,least(96,p_level+p_delta+floor((public.sim_hash01(p_attr||':'||p_id)-.5)*10+.5)::int))::smallint
$$;
revoke all on function public.sim_attr_calc(text,text,int,int) from public,anon,authenticated;

-- Sem UNION: o planejador junta pelo id e só calcula os atletas que sobram da consulta (um elenco, uma escalação).
create or replace view public.sim_player_attrs as
select p.id player_id,
 coalesce(r.gk_reflexes,public.sim_attr_calc(p.id,'gk_reflexes',p.attr_level,t.d[1])) gk_reflexes,
 coalesce(r.gk_handling,public.sim_attr_calc(p.id,'gk_handling',p.attr_level,t.d[2])) gk_handling,
 coalesce(r.gk_positioning,public.sim_attr_calc(p.id,'gk_positioning',p.attr_level,t.d[3])) gk_positioning,
 coalesce(r.marking,public.sim_attr_calc(p.id,'marking',p.attr_level,t.d[4])) marking,
 coalesce(r.tackling,public.sim_attr_calc(p.id,'tackling',p.attr_level,t.d[5])) tackling,
 coalesce(r.positioning,public.sim_attr_calc(p.id,'positioning',p.attr_level,t.d[6])) positioning,
 coalesce(r.heading,public.sim_attr_calc(p.id,'heading',p.attr_level,t.d[7])) heading,
 coalesce(r.passing,public.sim_attr_calc(p.id,'passing',p.attr_level,t.d[8])) passing,
 coalesce(r.vision,public.sim_attr_calc(p.id,'vision',p.attr_level,t.d[9])) vision,
 coalesce(r.technique,public.sim_attr_calc(p.id,'technique',p.attr_level,t.d[10])) technique,
 coalesce(r.stamina,public.sim_attr_calc(p.id,'stamina',p.attr_level,t.d[11])) stamina,
 coalesce(r.finishing,public.sim_attr_calc(p.id,'finishing',p.attr_level,t.d[12])) finishing,
 coalesce(r.off_ball,public.sim_attr_calc(p.id,'off_ball',p.attr_level,t.d[13])) off_ball,
 coalesce(r.pace,public.sim_attr_calc(p.id,'pace',p.attr_level,t.d[14])) pace,
 coalesce(r.dribbling,public.sim_attr_calc(p.id,'dribbling',p.attr_level,t.d[15])) dribbling,
 coalesce(r.strength,public.sim_attr_calc(p.id,'strength',p.attr_level,t.d[16])) strength,
 coalesce(r.estimated,true) estimated,
 coalesce(r.method,'v1: força do clube (sim_clubs.strength) + papel no elenco (camisa/capitão/base) + perfil da posição + variação determinística por jogador') method,
 coalesce(r.updated_at,p.imported_at) updated_at,
 coalesce(r.aggression,50::smallint) aggression,
 coalesce(r.discipline,60::smallint) discipline
from public.sim_players p
left join public.sim_player_attr_rows r on r.player_id=p.id
left join public.sim_attr_template t on t.pos=p.attr_pos
where r.player_id is not null or p.attr_level is not null;
revoke all on public.sim_player_attrs from anon,authenticated;

-- Gravar na view grava linha própria (vence o calculado). Apagar remove a linha própria e o cálculo.
create or replace function public.sim_player_attrs_write() returns trigger
language plpgsql security definer set search_path=public as $$
begin
 if tg_op='DELETE' then
  delete from public.sim_player_attr_rows where player_id=old.player_id;
  update public.sim_players set attr_level=null,attr_pos=null where id=old.player_id and attr_level is not null;
  return old;
 end if;
 insert into public.sim_player_attr_rows(player_id,gk_reflexes,gk_handling,gk_positioning,marking,tackling,positioning,heading,
  passing,vision,technique,stamina,finishing,off_ball,pace,dribbling,strength,estimated,method,updated_at,aggression,discipline)
 values(new.player_id,new.gk_reflexes,new.gk_handling,new.gk_positioning,new.marking,new.tackling,new.positioning,new.heading,
  new.passing,new.vision,new.technique,new.stamina,new.finishing,new.off_ball,new.pace,new.dribbling,new.strength,
  coalesce(new.estimated,true),new.method,coalesce(new.updated_at,now()),coalesce(new.aggression,50),coalesce(new.discipline,60))
 on conflict(player_id) do update set gk_reflexes=excluded.gk_reflexes,gk_handling=excluded.gk_handling,
  gk_positioning=excluded.gk_positioning,marking=excluded.marking,tackling=excluded.tackling,positioning=excluded.positioning,
  heading=excluded.heading,passing=excluded.passing,vision=excluded.vision,technique=excluded.technique,stamina=excluded.stamina,
  finishing=excluded.finishing,off_ball=excluded.off_ball,pace=excluded.pace,dribbling=excluded.dribbling,strength=excluded.strength,
  estimated=excluded.estimated,method=excluded.method,updated_at=now(),aggression=excluded.aggression,discipline=excluded.discipline;
 return new;
end $$;
revoke all on function public.sim_player_attrs_write() from public,anon,authenticated;
drop trigger if exists sim_player_attrs_write on public.sim_player_attrs;
create trigger sim_player_attrs_write instead of insert or update or delete on public.sim_player_attrs
 for each row execute function public.sim_player_attrs_write();

-- 7) Apaga as linhas estimadas que o cálculo reproduz exatamente.
delete from public.sim_player_attr_rows r using public.sim_players p,
 lateral public.sim_attr_gen(p.id,p.attr_pos,p.attr_level) g
where p.id=r.player_id and p.attr_level is not null and r.estimated and r.method<>'regen'
 and (r.gk_reflexes,r.gk_handling,r.gk_positioning,r.marking,r.tackling,r.positioning,r.heading,r.passing,r.vision,
  r.technique,r.stamina,r.finishing,r.off_ball,r.pace,r.dribbling,r.strength,r.aggression,r.discipline)
 =(g.gk_reflexes,g.gk_handling,g.gk_positioning,g.marking,g.tackling,g.positioning,g.heading,g.passing,g.vision,
  g.technique,g.stamina,g.finishing,g.off_ball,g.pace,g.dribbling,g.strength,50::smallint,60::smallint);

-- 8) cw_eff_attrs devolvia o tipo da tabela; agora devolve o tipo da view (mesmas colunas).
drop function if exists public.cw_eff_attrs(uuid,text);
create or replace function public.cw_eff_attrs(p_career uuid, p_player text)
 RETURNS public.sim_player_attrs
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
 select row(
  a.player_id,
  case when d.d ? 'gk_reflexes' then greatest(1,least(99,round(a.gk_reflexes+(d.d->>'gk_reflexes')::numeric)))::smallint else a.gk_reflexes end,
  case when d.d ? 'gk_handling' then greatest(1,least(99,round(a.gk_handling+(d.d->>'gk_handling')::numeric)))::smallint else a.gk_handling end,
  case when d.d ? 'gk_positioning' then greatest(1,least(99,round(a.gk_positioning+(d.d->>'gk_positioning')::numeric)))::smallint else a.gk_positioning end,
  case when d.d ? 'marking' then greatest(1,least(99,round(a.marking+(d.d->>'marking')::numeric)))::smallint else a.marking end,
  case when d.d ? 'tackling' then greatest(1,least(99,round(a.tackling+(d.d->>'tackling')::numeric)))::smallint else a.tackling end,
  case when d.d ? 'positioning' then greatest(1,least(99,round(a.positioning+(d.d->>'positioning')::numeric)))::smallint else a.positioning end,
  case when d.d ? 'heading' then greatest(1,least(99,round(a.heading+(d.d->>'heading')::numeric)))::smallint else a.heading end,
  case when d.d ? 'passing' then greatest(1,least(99,round(a.passing+(d.d->>'passing')::numeric)))::smallint else a.passing end,
  case when d.d ? 'vision' then greatest(1,least(99,round(a.vision+(d.d->>'vision')::numeric)))::smallint else a.vision end,
  case when d.d ? 'technique' then greatest(1,least(99,round(a.technique+(d.d->>'technique')::numeric)))::smallint else a.technique end,
  case when d.d ? 'stamina' then greatest(1,least(99,round(a.stamina+(d.d->>'stamina')::numeric)))::smallint else a.stamina end,
  case when d.d ? 'finishing' then greatest(1,least(99,round(a.finishing+(d.d->>'finishing')::numeric)))::smallint else a.finishing end,
  case when d.d ? 'off_ball' then greatest(1,least(99,round(a.off_ball+(d.d->>'off_ball')::numeric)))::smallint else a.off_ball end,
  case when d.d ? 'pace' then greatest(1,least(99,round(a.pace+(d.d->>'pace')::numeric)))::smallint else a.pace end,
  case when d.d ? 'dribbling' then greatest(1,least(99,round(a.dribbling+(d.d->>'dribbling')::numeric)))::smallint else a.dribbling end,
  case when d.d ? 'strength' then greatest(1,least(99,round(a.strength+(d.d->>'strength')::numeric)))::smallint else a.strength end,
  a.estimated,
  a.method,
  a.updated_at,
  case when d.d ? 'aggression' then greatest(1,least(99,round(a.aggression+(d.d->>'aggression')::numeric)))::smallint else a.aggression end,
  case when d.d ? 'discipline' then greatest(1,least(99,round(a.discipline+(d.d->>'discipline')::numeric)))::smallint else a.discipline end)::public.sim_player_attrs
 from public.sim_player_attrs a left join public.cw_player_dev d on d.career_id=p_career and d.player_id=p_player
 where a.player_id=p_player
$function$
;
revoke all on function public.cw_eff_attrs(uuid,text) from public,anon,authenticated;
grant execute on function public.cw_eff_attrs(uuid,text) to service_role;

-- 9) sim_refresh_ratings: calcula os atributos de cada atleta uma vez (antes recalculava por peso de posição).
create or replace function public.sim_refresh_ratings() returns integer
language plpgsql security definer set search_path to 'public' as $function$
declare v_n int;
begin
delete from public.sim_player_pos_ratings;
insert into public.sim_player_pos_ratings (player_id, pos, rating, eff)
with a as materialized (select x.player_id, to_jsonb(x) j from public.sim_player_attrs x)
select p.id, w.pos,
round(sum(w.weight * (a.j ->> w.attr)::numeric) / sum(w.weight), 2),
round(sum(w.weight * (a.j ->> w.attr)::numeric) / sum(w.weight)
* greatest(coalesce(max(f.fit), 0.5), case when w.pos = any (p.secondary_positions) then 0.97 else 0 end), 2)
from public.sim_players p
join a on a.player_id = p.id
join public.sim_role_weights w on true
left join public.sim_position_fit f on f.from_pos = p.position and f.to_pos = w.pos
group by p.id, w.pos, p.secondary_positions;
get diagnostics v_n = row_count;
return v_n;
end;
$function$;
