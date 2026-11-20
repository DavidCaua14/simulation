-- MODO ONLINE — Fase 46: estádio pago. O Campo do Interior é o estádio inicial (grátis) de todo clube; os outros
-- modelos são comprados com diamantes, uma vez por conta (valem em todas as temporadas). Comprar já coloca o estádio no
-- clube; trocar entre estádios já comprados é grátis (Clube → Identidade).
alter table public.on_config add column if not exists arena_prices jsonb not null
 default '{"interior":0,"concreto":300,"circulos":500,"praia":800,"arena":1200,"neon":1500}';

create table if not exists public.on_arena_owned(
 user_id uuid not null,
 arena text not null,
 price int not null default 0,
 at timestamptz not null default now(),
 primary key(user_id,arena));
alter table public.on_arena_owned enable row level security;

create or replace function public.on_arena_has(p_user uuid,p_arena text) returns boolean
language sql stable security definer set search_path=public as $$
 select p_arena='interior' or exists(select 1 from public.on_arena_owned o where o.user_id=p_user and o.arena=p_arena) $$;

-- Vitrine: cada modelo com preço, se já é da conta e qual está no clube.
create or replace function public.online_arenas() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);cfg public.on_config;
begin
 select * into cfg from public.on_config;
 return jsonb_build_object(
  'current',coalesce(c.colors->>'arena','interior'),
  'diamonds',(select k.diamonds from public.careers k where k.id=public.on_career_of(c.user_id)),
  'arenas',(select jsonb_agg(jsonb_build_object('id',a,'price',coalesce((cfg.arena_prices->>a)::int,0),
     'owned',public.on_arena_has(c.user_id,a)) order by coalesce((cfg.arena_prices->>a)::int,0),a)
   from unnest(public.on_arenas()) a));
end $$;

create or replace function public.online_arena_buy(p_arena text) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me(true);v_price int;v_car uuid;
begin
 if not (p_arena = any(public.on_arenas())) then raise exception 'Estádio inválido';end if;
 perform pg_advisory_xact_lock(hashtext('arena:'||c.user_id));
 if public.on_arena_has(c.user_id,p_arena) then raise exception 'Esse estádio já é seu';end if;
 v_price:=coalesce((select (arena_prices->>p_arena)::int from public.on_config),0);
 v_car:=public.on_career_of(c.user_id);
 if v_car is null then raise exception 'Conta sem carreira';end if;
 if v_price>0 then
  -- produção: econ_apply (registra a saída no extrato); banco de testes: desconto direto
  if to_regprocedure('public.econ_apply(uuid,text,integer,text,text)') is not null then
   execute 'select public.econ_apply($1,''diamonds'',$2,''online_arena'',$3)' using v_car,-v_price,p_arena;
  else
   if (select diamonds from public.careers where id=v_car for update)<v_price then raise exception 'Diamantes insuficientes.';end if;
   update public.careers set diamonds=diamonds-v_price where id=v_car;
  end if;
 end if;
 insert into public.on_arena_owned(user_id,arena,price) values(c.user_id,p_arena,v_price);
 update public.on_clubs set colors=colors||jsonb_build_object('arena',p_arena) where id=c.id;
 return public.online_arenas();
end $$;

revoke all on function public.online_arenas() from public, anon;
revoke all on function public.online_arena_buy(text) from public, anon;
grant execute on function public.online_arenas() to authenticated;
grant execute on function public.online_arena_buy(text) to authenticated;

-- Identidade: só usa estádio que a conta tem
do $$ begin
 perform public.on_patch('public.on_club_identity(jsonb)',
  '  if not (p->>''arena'' = any(public.on_arenas())) then raise exception ''Estádio inválido'';end if;',
  '  if not (p->>''arena'' = any(public.on_arenas())) then raise exception ''Estádio inválido'';end if;
  if not public.on_arena_has(c.user_id,p->>''arena'') then raise exception ''Compre esse estádio antes de usar'';end if;');
end $$;
