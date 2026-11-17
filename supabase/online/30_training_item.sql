-- MODO ONLINE — Fase 28: Apito de Ouro (item de treino de elite). Por enquanto só para o administrador.
-- Comprado com diamantes na Loja (aba Itens). No Elenco, na ficha do jogador, "Usar Apito de Ouro" leva o jogador
-- na hora à nota máxima (o potencial), sem gastar condição nem treino do dia.
-- Preço: 300 diamantes por unidade, uma por compra, até 3 guardadas (on_config.item_price e item_max).
--  · Referência: a sequência diária rende no máximo 750 diamantes por semana (300 no dia 5 e 450 no dia 7); o resto da
--    loja custa de 5 a 100. O item é o mais caro do jogo: dá para ter um a cada uma ou duas semanas de jogo.
--  · O mesmo ganho pelo treino pede dezenas de sessões extras (2 diamantes cada no pacote de 50), dias de espera e
--    condição gasta; perto do potencial o treino quase não rende. O item pula tudo isso, por isso o preço alto.
-- O estoque é da conta (user_id), como os diamantes: passa de uma temporada para a outra.
-- Liberado só para quem public.is_admin() aceita (o e-mail do dono do jogo). Quando abrir para todos, basta trocar
-- on_item_gate().

alter table public.on_config add column if not exists item_price int not null default 300 check (item_price>0);
alter table public.on_config add column if not exists item_max smallint not null default 3 check (item_max>0);

create table if not exists public.on_items(
 user_id uuid not null,
 item text not null check (item in('golden_whistle')),
 qty int not null default 0 check (qty>=0),
 primary key(user_id,item)
);
alter table public.on_items enable row level security;
revoke all on public.on_items from anon,authenticated;

create table if not exists public.on_item_uses(
 id bigint generated always as identity primary key,
 user_id uuid not null,
 item text not null,
 club_id int,
 player_id text,
 before numeric(4,1),
 after numeric(4,1),
 at timestamptz not null default now()
);
alter table public.on_item_uses enable row level security;
revoke all on public.on_item_uses from anon,authenticated;

-- Quem pode ver e usar os itens.
create or replace function public.on_item_gate() returns boolean
language sql stable security definer set search_path=public as $$ select coalesce(public.is_admin(),false) $$;

-- Itens da conta: estoque, preço e diamantes. Fora do portão devolve só {enabled:false}.
create or replace function public.online_items() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare cfg public.on_config;k public.careers;
begin
 if auth.uid() is null or not public.on_item_gate() then return jsonb_build_object('enabled',false);end if;
 select * into cfg from public.on_config;
 select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1;
 return jsonb_build_object('enabled',true,'diamonds',coalesce(k.diamonds,0),
  'items',jsonb_build_object('golden_whistle',jsonb_build_object(
   'qty',coalesce((select qty from public.on_items where user_id=auth.uid() and item='golden_whistle'),0),
   'price',cfg.item_price,'max',cfg.item_max)));
end $$;

-- Compra uma unidade com diamantes.
create or replace function public.online_item_buy(p_item text default 'golden_whistle') returns jsonb
language plpgsql security definer set search_path=public as $$
declare cfg public.on_config;k public.careers;v_qty int;
begin
 if auth.uid() is null or not public.on_item_gate() then raise exception 'Item indisponível';end if;
 if p_item is distinct from 'golden_whistle' then raise exception 'Item inválido';end if;
 select * into cfg from public.on_config;
 select x.* into k from public.careers x where x.user_id=auth.uid() order by (x.status='active') desc,x.created_at desc limit 1 for update;
 if k.id is null then raise exception 'Conta sem carreira';end if;
 select qty into v_qty from public.on_items where user_id=auth.uid() and item=p_item for update;
 if coalesce(v_qty,0)>=cfg.item_max then raise exception 'Você já tem % guardados. Use um antes de comprar outro',cfg.item_max;end if;
 if k.diamonds<cfg.item_price then raise exception 'Diamantes insuficientes';end if;
 perform set_config('econ.reason','online_item',true);
 perform set_config('econ.ref',p_item,true);
 update public.careers set diamonds=diamonds-cfg.item_price where id=k.id;
 perform set_config('econ.reason','',true);
 perform set_config('econ.ref','',true);
 insert into public.on_items(user_id,item,qty) values(auth.uid(),p_item,1)
  on conflict(user_id,item) do update set qty=public.on_items.qty+1;
 return public.online_items();
end $$;

-- Usa o Apito de Ouro num jogador do elenco: a nota vai ao potencial. Os pontos de treino que faltam entram nos grupos
-- de atributo da posição (defesa, passe, ataque, físico), então a carta acompanha. Condição e treinos do dia não mudam.
create or replace function public.online_item_use(p_player text,p_item text default 'golden_whistle') returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs;p public.on_players;v_line text;v_need int;v_order int[];v_w numeric[]:=array[.4,.3,.2,.1];
 v_add int[]:=array[0,0,0,0];v_left int;i int;v_g smallint[];v_ovr numeric;
begin
 if auth.uid() is null or not public.on_item_gate() then raise exception 'Item indisponível';end if;
 if p_item is distinct from 'golden_whistle' then raise exception 'Item inválido';end if;
 c:=public.on_me(true);
 select * into p from public.on_players where id=p_player and club_id=c.id for update;
 if p.id is null then raise exception 'Jogador fora do seu elenco';end if;
 if public.on_in_live(p.id) then raise exception 'Quem está jogando agora não treina';end if;
 if p.ovr>=p.pot then raise exception '% já está na nota máxima',p.name;end if;
 if coalesce((select qty from public.on_items where user_id=auth.uid() and item=p_item for update),0)<=0 then
  raise exception 'Você não tem Apito de Ouro. Compre na Loja';
 end if;
 -- pontos de grupo que faltam: cada ponto vale 0,5 de nota (on_ovr)
 v_need:=ceil(2*(p.pot-p.level))::int-(select coalesce(sum(x),0) from unnest(p.g) x)::int;
 select line into v_line from public.sim_positions where code=p.pos;
 v_order:=case v_line when 'GK' then array[1,4,2,3] when 'DEF' then array[1,4,2,3] when 'MID' then array[2,1,3,4] else array[3,2,4,1] end;
 if v_need>0 then
  v_left:=v_need;
  for i in 1..4 loop
   v_add[v_order[i]]:=floor(v_need*v_w[i])::int;
   v_left:=v_left-v_add[v_order[i]];
  end loop;
  v_add[v_order[1]]:=v_add[v_order[1]]+v_left;
 end if;
 v_g:=array(select (coalesce(p.g[s.n],0)+v_add[s.n])::smallint from generate_series(1,4) s(n) order by s.n);
 v_ovr:=public.on_ovr(p.level,p.pot,v_g);
 update public.on_players set g=v_g,ovr=v_ovr where id=p.id;
 update public.on_items set qty=qty-1 where user_id=auth.uid() and item=p_item;
 insert into public.on_item_uses(user_id,item,club_id,player_id,before,after) values(auth.uid(),p_item,c.id,p.id,p.ovr,v_ovr);
 insert into public.on_news(club_id,kind,text) values(c.id,'train',p.name||' fez o treino de elite (Apito de Ouro) e chegou à nota '||round(v_ovr)||'.');
 return jsonb_build_object('player',jsonb_build_object('id',p.id,'name',p.name,'before',p.ovr,'ovr',v_ovr,'pot',p.pot),
  'items',public.online_items()->'items');
end $$;

revoke all on function public.on_item_gate() from public,anon,authenticated;
revoke all on function public.online_items(),public.online_item_buy(text),public.online_item_use(text,text) from public,anon;
grant execute on function public.online_items(),public.online_item_buy(text),public.online_item_use(text,text) to authenticated;
