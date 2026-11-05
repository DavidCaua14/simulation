-- Evolução 65 — Moral % como no Championship Manager 17.
-- Sai a "satisfação" (papel prometido, pedido para sair, cobranças por notícia). Fica só a moral de 0 a 100, com seta:
--  * sobe com minutos em campo de acordo com o lugar do atleta no elenco (titulares esperam jogar, reservas menos),
--    com vitórias do clube e com o psicólogo; cai sem minutos, com derrotas e com salários atrasados;
--  * continua pesando no rendimento em campo (cw_morale_factor, evolução 32);
--  * ninguém mais "pede para sair": vender um dos 3 principais exige colocá-lo na lista de transferências.
-- A moral atual de cada atleta é mantida; só a regra de variação muda.
begin;

alter table public.cw_players add column if not exists morale_trend smallint not null default 0;

-- Regra semanal da moral, no lugar do bloco de satisfação do mercado (texto substituído com verificação).
do $$ declare src text;a int;b int;new_block text;begin
 select pg_get_functiondef('public.cw_market_tick_before_v37(uuid)'::regprocedure) into src;
 if src like '%Moral (CM17)%' then return;end if;
 a:=position(' -- Satisfação semanal pelos minutos reais x papel prometido' in src);
 b:=position(' -- Alvos realistas (evolução 40)' in src);
 if a=0 or b=0 or b<a then raise exception 'cw_market_tick_before_v37 diferente do esperado';end if;
 new_block:=$blk$ -- Moral (CM17): minutos conforme o lugar no elenco, resultados do clube e salários em dia. Sem papel prometido.
 for p in select cp.*,mp.club_id,ct.arrears,ct.starts_on from public.cw_players cp join public.mgr_players mp using(career_id,player_id)
  join public.cw_contracts ct on ct.career_id=cp.career_id and ct.player_id=cp.player_id and ct.status='active'
  where cp.career_id=p_career and (not (select public.cw_runtime_enabled(p_career)) or mp.club_id in (select public.cw_domestic_clubs(p_career)) or mp.club_id=own) and (cp.last_morale_on is null or cp.last_morale_on<=d-7) loop
  if d-p.starts_on<28 then update public.cw_players set last_morale_on=d where career_id=p_career and player_id=p.player_id;continue;end if;
  select count(*) into games from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id where fd.career_id=p_career and fd.club_id=p.club_id and f.status='played' and fd.due_on between d-28 and d;
  select count(*) into apps from public.cw_appearances mp where mp.career_id=p_career and mp.player_id=p.player_id and mp.club_id=p.club_id and mp.minutes>=30 and mp.on_date between d-28 and d;
  new_morale:=public.cw_cm_morale_next(p_career,p.club_id,p.player_id,p.morale,games,apps,p.arrears,d);
  update public.cw_players set morale=new_morale,morale_trend=sign(new_morale-p.morale)::smallint,last_morale_on=d,transfer_requested=false,last_warning_on=null
   where career_id=p_career and player_id=p.player_id;
 end loop;
$blk$;
 src:=substr(src,1,a-1)||new_block||substr(src,b);
 execute src;
end $$;

-- Cálculo da moral da semana (separado para testar e reaproveitar).
create or replace function public.cw_cm_morale_next(p_career uuid,p_club text,p_player text,p_morale numeric,p_games int,p_apps int,p_arrears numeric,p_day date)
returns numeric language plpgsql stable security definer set search_path=public as $$
declare rk int;expected numeric;share numeric;delta numeric:=0;w int;l int;
begin
 rk:=coalesce(public.cw_squad_rank(p_career,p_club,p_player),30);
 expected:=case when rk<=11 then .60 when rk<=16 then .30 else .10 end;
 if p_games>=3 then
  share:=p_apps::numeric/p_games;
  delta:=greatest(-6,least(6,round(10*(share-expected))));
  if share>=expected and delta<1 then delta:=1;end if;
 else
  delta:=case when p_morale<60 then 1 when p_morale>70 then -1 else 0 end;
 end if;
 select count(*) filter(where (f.home_club=p_club and f.home_goals>f.away_goals) or (f.away_club=p_club and f.away_goals>f.home_goals)),
        count(*) filter(where (f.home_club=p_club and f.home_goals<f.away_goals) or (f.away_club=p_club and f.away_goals<f.home_goals))
   into w,l
   from public.cw_club_dates fd join public.season_fixtures f on f.id=fd.fixture_id
  where fd.career_id=p_career and fd.club_id=p_club and f.status='played' and fd.due_on between p_day-7 and p_day;
 delta:=delta+greatest(-4,least(4,2*coalesce(w,0)-2*coalesce(l,0)));
 if coalesce(p_arrears,0)>0 then delta:=delta-8;end if;
 return greatest(0,least(100,p_morale+delta));
end $$;

-- Ninguém pede para sair: o pedido antigo é desfeito e a IA só negocia os titulares que você listar.
update public.cw_players set transfer_requested=false,last_warning_on=null where transfer_requested or last_warning_on is not null;

do $$ declare src text;begin
 select pg_get_functiondef('public.cw_market_tick(uuid)'::regprocedure) into src;
 if src like '%wants_out:=coalesce(cp.transfer_listed,false);%' then return;end if;
 if position('wants_out:=coalesce(cp.transfer_requested,false) or coalesce(cp.morale,60)<30;' in src)=0 then raise exception 'cw_market_tick diferente do esperado';end if;
 execute replace(src,'wants_out:=coalesce(cp.transfer_requested,false) or coalesce(cp.morale,60)<30;','wants_out:=coalesce(cp.transfer_listed,false);');
end $$;

create or replace function public.cw_board_veto(p_career uuid,p_club text,p_player text)
returns text language plpgsql stable security definer set search_path=public as $$
declare rk int;cnt int;listed boolean;
begin
 select transfer_listed into listed from public.cw_players where career_id=p_career and player_id=p_player;
 rk:=public.cw_squad_rank(p_career,p_club,p_player);
 select count(*) into cnt from public.mgr_players where career_id=p_career and club_id=p_club;
 if cnt<=18 then return 'A diretoria não autoriza: o elenco ficaria curto demais (mínimo de 18 atletas).';end if;
 if rk<=3 and not coalesce(listed,false) then
  return 'A diretoria não libera um dos três principais atletas do elenco. Para vendê-lo, coloque-o na lista de transferências.';
 end if;
 return null;
end $$;

-- Papel prometido não existe mais.
create or replace function public.career_player_role(p_player text,p_role text)
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 raise exception 'O papel no elenco não existe mais: a moral depende dos minutos em campo e dos resultados.';
end $$;

-- A ficha e a busca mostram a seta da moral.
do $$ declare src text;begin
 select pg_get_functiondef(p.oid) into src from pg_proc p where p.oid='public.cw_patch_players_before_v58(uuid,jsonb,boolean)'::regprocedure;
 if src is null or src like '%morale_trend%' then return;end if;
 if position('''transfer_requested'',cp.transfer_requested,' in src)=0 then raise exception 'cw_patch_players diferente do esperado';end if;
 execute replace(src,'''transfer_requested'',cp.transfer_requested,','''transfer_requested'',false,''morale_trend'',cp.morale_trend,');
end $$;

revoke all on function public.cw_cm_morale_next(uuid,text,text,numeric,int,int,numeric,date) from public,anon,authenticated;
notify pgrst,'reload schema';
commit;
