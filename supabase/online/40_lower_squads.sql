-- MODO ONLINE — Fase 37: elencos reais das Séries C e D.
--
-- Os clubes das Séries C e D não estão no catálogo do modo Temporadas (só A e B). Os elencos vêm da Wikipédia
-- (scripts/fetch-lower-squads.py → data/squads-lower/*.txt → scripts/build-lower-squads.py → 41_lower_squads_data.sql):
-- nome, número, nacionalidade e posição são os da fonte; nota e idade são estimativas de jogo (nível da série +
-- papel no elenco). Clube sem elenco recente na fonte continua com cartas base geradas. Elencos 'real' (sq) entram
-- como cartas base no nível da série em que o clube está; ao mudar de série, o elenco é refeito no nível novo.

create table if not exists public.on_lower_players(
 club_key text not null references public.on_real_clubs(key) on delete cascade,
 no smallint,
 pos text not null,
 nat text not null default 'BRA',
 name text not null,
 age smallint not null,
 lvl_off smallint not null default 0,
 pos_est boolean not null default false,
 source text,
 as_of text
);
create index if not exists on_lower_players_club on public.on_lower_players(club_key);
alter table public.on_lower_players enable row level security;
revoke all on public.on_lower_players from anon,authenticated;

create or replace function public.on_bot_squad(p_club int,p_seed text) returns void
language plpgsql security definer set search_path=public as $$
declare k public.on_clubs;rc public.on_real_clubs;v_lv int;v_end int;n int:=0;r record;v_id text;
begin
 select * into k from public.on_clubs where id=p_club for update;
 if k.user_id is not null then return;end if;
 select * into rc from public.on_real_clubs where key=k.real_key;
 v_lv:=coalesce((select (series_level->>k.div)::int from public.on_config),60);
 v_end:=k.season_id+5;
 delete from public.on_lots where player_id in(select id from public.on_players where club_id=p_club) and status<>'open';
 update public.on_lots set status='cancelled',settled_at=now() where player_id in(select id from public.on_players where club_id=p_club) and status='open';
 delete from public.on_players where club_id=p_club and id not in(select player_id from public.on_lots);
 update public.on_players set club_id=null where club_id=p_club;
 delete from public.on_lineups where club_id=p_club;
 k.sq:=case when rc.sim_club is not null and k.div in('A','B') then case when k.div='A' then 'star' else 'base' end else 'gen' end;
 update public.on_clubs set sq=k.sq where id=p_club;
 if k.sq in('star','base') then
  for r in select q.id from(
    select p.id,p.position pos,b.rating,row_number() over(partition by p.position='GOL' order by b.rating desc,p.id) rn
    from public.sim_players p join public.sim_player_base b on b.player_id=p.id
    where p.club_id=rc.sim_club and p.career_id is null and p.active
     and not exists(select 1 from public.on_players o where o.src=p.id)) q
   where (q.pos='GOL' and q.rn<=3) or (q.pos<>'GOL' and q.rn<=20)
   order by q.rating desc loop
   n:=n+1;
   v_id:=public.on_real_insert(r.id,p_club,n,v_end);
  end loop;
 elsif exists(select 1 from public.on_lower_players where club_key=k.real_key) then
  -- elenco real das Séries C e D (Wikipédia): cartas base no nível da série; nota estimada pelo papel no elenco
  k.sq:='real';
  update public.on_clubs set sq='real' where id=p_club;
  insert into public.on_players(club_id,name,pos,nat,age,level,pot,ovr,number,wage,contract_end,agg,disc)
  select p_club,x.name,x.pos,x.nat,x.age,x.lvl,least(92,x.lvl+case when x.age<23 then 3 else 0 end),x.lvl,x.no,public.on_wage(x.lvl),v_end,
   35+floor(public.sim_hash01(x.name||':agg')*40)::int,40+floor(public.sim_hash01(x.name||':disc')*45)::int
  from(select l.*,greatest(40,least(85,v_lv+l.lvl_off))::smallint lvl,
    row_number() over(partition by l.pos='GOL' order by coalesce(l.no,99),l.name) rn
   from public.on_lower_players l where l.club_key=k.real_key) x
  where (x.pos='GOL' and x.rn<=3) or (x.pos<>'GOL' and x.rn<=21);
  get diagnostics n=row_count;
  if k.sq='star' then
   -- destaque: o potencial fica pelo menos 5 acima da nota (a carta evolui jogando)
   update public.on_players set tier='destaque',pot=least(95,greatest(pot,level+5)) where club_id=p_club;
  end if;
 end if;
 if n<18 then
  perform public.on_gen_fake(p_club,p_seed||':'||p_club,v_lv,v_end);
  if n>0 then -- completa: tira as geradas que sobram nas posições já cheias
   delete from public.on_players p where p.club_id=p_club and p.src is null
    and p.id in(select x.id from public.on_players x where x.club_id=p_club and x.src is null order by x.number desc limit greatest(0,n+22-23));
  end if;
 end if;
 update public.on_players p set number=x.rn from(select id,row_number() over(order by (pos='GOL') desc,ovr desc,id) rn from public.on_players where club_id=p_club) x
  where p.id=x.id;
 perform public.on_auto_lineup(p_club);
end $$;
