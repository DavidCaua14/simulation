-- MODO ONLINE — Fase 20: mercado cheio a cada hora.
-- Um destaque e uma lenda por janela de 5 horas era pouco. Agora, toda hora com o mercado aberto:
--  • 5 cartas base (até 80), em posições diferentes, sempre com algo que vale a disputa:
--    faixa 1: 78 a 80 · faixa 2: 75 a 78 · faixa 3: 72 a 75 com até 27 anos ·
--    faixa 4: promessa (até 23 anos, 66 a 74, potencial 6+ acima) · faixa 5: joia (até 21 anos, 60 a 74, potencial 10+ acima);
--  • 5 destaques (81 ou mais) e 5 lendas, também em posições diferentes. Abrem na hora e vão até a virada da hora.
-- Quantidades em on_config: featured_count (base, até 5), star_count (destaques) e legend_count (lendas).
-- Sem lances, o jogador é apagado e volta a ficar livre no catálogo (on_lot_settle), então o catálogo não esgota.
-- Bots continuam fora de destaque e lenda.

alter table public.on_config add column if not exists star_count smallint not null default 5;
alter table public.on_config add column if not exists legend_count smallint not null default 5;
alter table public.on_config alter column featured_count set default 5;
update public.on_config set featured_count=5 where featured_count<5;

-- Posição menos usada entre as já ofertadas (p_taken); empate decidido pela semente.
create or replace function public.on_pick_pos(p_seed text,p_taken text[]) returns text
language sql stable set search_path=public as $$
 select x from unnest(array['GOL','LD','ZAG','LE','VOL','MC','MEI','PD','PE','ATA']) x
 order by (select count(*) from unnest(coalesce(p_taken,'{}'::text[])) t where t=x),public.sim_hash01(p_seed||':'||x)
 limit 1
$$;

-- Carta base da faixa p_tier (1 a 5) na posição p_pos (outra posição se não houver ninguém livre nela).
create or replace function public.on_gen_base(p_seed text,p_tier int,p_pos text) returns text
language plpgsql security definer set search_path=public as $$
declare t int:=greatest(1,least(5,p_tier));
 v_lo numeric:=(array[78,75,72,66,60])[t];v_hi numeric:=(array[80.5,78,75,74,74])[t];
 v_age int:=(array[40,40,27,23,21])[t];v_gap int:=(array[0,0,0,6,10])[t];
 v_end int:=(select max(id) from public.on_seasons)+1+floor(public.sim_hash01(p_seed||':ct')*2)::int;
 v_src text;v_id text;
begin
 select p.id into v_src from public.on_pool p
 where not p.legend and p.rating>=v_lo and p.rating<v_hi and p.age<=v_age and p.pot>=round(p.rating)+v_gap
  and not exists(select 1 from public.on_players o where o.src=p.id)
 order by (p.pos is distinct from p_pos)::int,public.sim_hash01(p_seed||':'||p.id) limit 1;
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

-- Destaque (81+) ou lenda na posição p_pos (outra se não houver). Nulo se não houver ninguém livre.
create or replace function public.on_gen_special(p_seed text,p_legend boolean,p_pos text) returns text
language plpgsql security definer set search_path=public as $$
declare v_src text;
begin
 if p_legend then v_src:=coalesce(public.on_real_pick(p_pos,80,100,p_seed,true),public.on_real_pick(null,80,100,p_seed,true));end if;
 if v_src is null then v_src:=coalesce(public.on_real_pick(p_pos,80.5,100,p_seed,false),public.on_real_pick(null,80.5,100,p_seed,false));end if;
 if v_src is null then v_src:=public.on_real_pick(null,80,100,p_seed,true);end if;
 if v_src is null then return null;end if;
 return public.on_real_insert(v_src,null,null,(select max(id) from public.on_seasons)+2,true);
end $$;

-- Relógio do mercado: toda hora, cartas base, destaques e lendas abertos até a virada da hora.
create or replace function public.on_market_tick(p_now timestamptz,p_new_day boolean) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;r record;t int;i int;pid text;k int;v_bid bigint;v_end timestamptz;v_close timestamptz;
 v_epoch bigint:=floor(extract(epoch from p_now))::bigint;sp record;v_taken text[];
begin
 select * into s from public.on_seasons where status='live';
 if s.id is null then return;end if;
 select * into cfg from public.on_config;
 v_close:=(public.on_market_hours(p_now)->>'closes_at')::timestamptz;
 for r in select l.id from public.on_lots l where l.season_id=s.id and l.status='open' and l.ends_at<=p_now order by l.ends_at limit 60 loop
  perform public.on_lot_settle(r.id,p_now);
 end loop;
 -- leilão do mercado marcado para depois do fechamento: sai (o jogador sem clube vai junto)
 delete from public.on_players p using public.on_lots l where l.player_id=p.id and l.season_id=s.id and l.status='open' and l.seller is null
  and l.best_club is null and p.club_id is null and l.opens_at>=(public.on_market_hours(l.opens_at)->>'closes_at')::timestamptz;
 if not public.on_market_open(p_now) then return;end if; -- mercado fechado
 v_end:=case when cfg.featured_minutes=60 then date_trunc('hour',p_now+interval '15 minutes')+interval '1 hour'
  else p_now+cfg.featured_minutes*interval '1 minute' end;
 v_end:=least(v_end,v_close);
 -- fim do dia: não abre leilão de poucos minutos
 if v_end>=p_now+interval '15 minutes' then
 -- cartas base: uma por faixa, cada uma numa posição diferente das já ofertadas
 for t in 1..least(cfg.featured_count,5) loop
  continue when exists(select 1 from public.on_lots x where x.season_id=s.id and x.status='open' and x.featured=t);
  v_taken:=array(select p.pos from public.on_lots x join public.on_players p on p.id=x.player_id
   where x.season_id=s.id and x.status='open' and x.seller is null and x.featured between 1 and 5);
  pid:=public.on_gen_base(s.seed||':f:'||t||':'||v_epoch,t,public.on_pick_pos(s.seed||':fp:'||t||':'||v_epoch,v_taken));
  insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
  select s.id,pid,public.on_start_price(p),p_now,v_end,v_end+cfg.lot_extend_max,t from public.on_players p where p.id=pid;
 end loop;
 -- destaques (9) e lendas (8): completa star_count e legend_count, em posições diferentes
 for sp in select * from(values(9,false,cfg.star_count),(8,true,cfg.legend_count)) v(feat,legend,n) loop
  for i in 1..sp.n-(select count(*) from public.on_lots x where x.season_id=s.id and x.status='open' and x.featured=sp.feat) loop
   v_taken:=array(select p.pos from public.on_lots x join public.on_players p on p.id=x.player_id
    where x.season_id=s.id and x.status='open' and x.featured=sp.feat);
   pid:=public.on_gen_special(s.seed||':sp:'||sp.feat||':'||i||':'||v_epoch,sp.legend,
    public.on_pick_pos(s.seed||':spp:'||sp.feat||':'||i||':'||v_epoch,v_taken));
   exit when pid is null;
   insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end,featured)
   select s.id,pid,public.on_start_price(p),p_now,v_end,v_end+cfg.lot_extend_max,sp.feat from public.on_players p where p.id=pid;
  end loop;
 end loop;
 end if;
 -- bots: entram na disputa só quando um técnico já deu lance, nos últimos 3 minutos; destaque e lenda ficam fora
 for r in select l.*,public.on_value(p.ovr,p.age,p.pot) v from public.on_lots l join public.on_players p on p.id=l.player_id
  where l.season_id=s.id and l.status='open' and l.featured<8 and l.opens_at<=p_now and l.ends_at>p_now and l.ends_at<=p_now+interval '3 minutes'
   and l.best_club is not null and exists(select 1 from public.on_clubs h where h.id=l.best_club and h.user_id is not null)
   and random()<.5 loop
  v_bid:=r.best_bid+greatest(500,ceil(r.best_bid*.05))::bigint;
  -- cada bot tem interesse e teto próprios (on_bot_limit)
  select c.id into k from public.on_clubs c where c.season_id=s.id and c.user_id is null and c.id is distinct from r.best_club
   and c.id is distinct from r.seller and c.debt=0 and c.cash-c.reserved>=v_bid and (select count(*) from public.on_players x where x.club_id=c.id)<26
   and public.on_bot_limit(c.id,r.id,r.player_id)>=v_bid
   order by random() limit 1;
  continue when k is null;
  begin perform public.on_bid_as(k,r.id,v_bid,p_now);exception when others then null;end;
 end loop;
end $$;

-- Na tela: lendas primeiro, depois destaques, cada grupo pela ordem de fechamento.
do $$ begin
 perform public.on_patch('public.on_market()',
  'jsonb_agg(public.on_lot_json(l,c.id) order by l.opens_at,l.featured desc)',
  'jsonb_agg(public.on_lot_json(l,c.id) order by l.featured,l.opens_at,l.ends_at,l.id)');
end $$;

-- Especiais do regime antigo ainda travados (abririam mais tarde, um por janela): saem sem lances, com o jogador.
delete from public.on_players p using public.on_lots l
 where l.player_id=p.id and l.status='open' and l.featured>=8 and l.seller is null and l.best_club is null
  and p.club_id is null and l.opens_at>now();

revoke all on function public.on_pick_pos(text,text[]),public.on_gen_base(text,int,text),public.on_gen_special(text,boolean,text),
 public.on_market_tick(timestamptz,boolean) from public,anon,authenticated;
