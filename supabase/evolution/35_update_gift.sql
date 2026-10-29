-- EVOLUÇÃO 35: presente da atualização para quem já jogava (testadores) e avatares de lendas no perfil.
-- * Quem tem carreira cadastrada no momento da instalação recebe, uma única vez, ao entrar no jogo:
--   +1000 de XP (sobe um nível), +20 de energia bônus e um avatar de lenda aleatório. Contas novas não recebem nada.
-- * Avatares ganhos ficam no perfil e podem ser usados como foto ('avatar:<id>'), só por quem os possui.
-- Aditiva: tabelas novas, uma regra de foto ampliada e funções novas/embrulhadas. Não altera dados existentes
-- (o XP e a energia só mudam quando o próprio jogador entra e recebe o presente).
begin;

create table if not exists public.avatar_catalog (
 id text primary key check (id ~ '^[a-z0-9_-]{1,30}$'),label text not null,active boolean not null default true,sort_order int not null default 0
);
insert into public.avatar_catalog(id,label,sort_order) values
 ('lenda-cristiano','Lenda · Cristiano Ronaldo',1),('lenda-neymar','Lenda · Neymar',2),
 ('lenda-ronaldinho','Lenda · Ronaldinho',3),('lenda-zlatan','Lenda · Zlatan',4)
on conflict (id) do nothing;

create table if not exists public.player_avatars (
 career_id uuid not null references public.careers(id) on delete cascade,avatar_id text not null references public.avatar_catalog(id),
 source text not null,granted_at timestamptz not null default now(),primary key(career_id,avatar_id)
);
-- Presente da atualização: quem pode receber (fotografado na instalação) e quando recebeu/viu.
create table if not exists public.release_gifts (
 release_id text not null,career_id uuid not null references public.careers(id) on delete cascade,
 eligible_at timestamptz not null default now(),claimed_at timestamptz,seen_at timestamptz,
 level_before int,level_after int,avatar_id text,primary key(release_id,career_id)
);
-- Só na PRIMEIRA instalação: reexecutar o script não inclui contas criadas depois.
do $$ begin
 if not exists(select 1 from public.release_gifts where release_id='2026-temporadas-v2') then
  insert into public.release_gifts(release_id,career_id) select '2026-temporadas-v2',c.id from public.careers c on conflict do nothing;
 end if;
end $$;

alter table public.avatar_catalog enable row level security;
alter table public.player_avatars enable row level security;
alter table public.release_gifts enable row level security;
revoke all on public.avatar_catalog,public.player_avatars,public.release_gifts from public,anon,authenticated;

-- Foto de perfil: também aceita um avatar ganho.
do $$ declare c text;begin
 for c in select conname from pg_constraint where conrelid='public.player_profiles'::regclass and contype='c' and pg_get_constraintdef(oid) like '%avatar_data%' loop
  execute format('alter table public.player_profiles drop constraint %I',c);
 end loop;
 alter table public.player_profiles add constraint player_profiles_avatar_data_check check (avatar_data is null or avatar_data ~ '^preset:[a-z0-9_-]{1,20}$'
  or avatar_data ~ '^avatar:[a-z0-9_-]{1,30}$' or (avatar_data like 'data:image/jpeg;base64,%' and length(avatar_data)<=90000));
 if to_regprocedure('public.profile_set_avatar_before_v35(text)') is null then alter function public.profile_set_avatar(text) rename to profile_set_avatar_before_v35;end if;
 if to_regprocedure('public.profile_me_before_v35()') is null then alter function public.profile_me() rename to profile_me_before_v35;end if;
end $$;

create or replace function public.profile_set_avatar(p_data text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_c public.careers;
begin
 if p_data is null or p_data !~ '^avatar:' then return public.profile_set_avatar_before_v35(p_data);end if;
 select * into v_c from public.careers where user_id=auth.uid() and status='active';
 if not found then raise exception 'Carreira ativa não encontrada';end if;
 if not exists(select 1 from public.player_avatars where career_id=v_c.id and avatar_id=substr(p_data,8)) then raise exception 'Você ainda não tem este avatar';end if;
 perform public.profile_ensure(v_c.id);
 update public.player_profiles set avatar_data=p_data,updated_at=now() where career_id=v_c.id;
 return jsonb_build_object('ok',true);
end $$;

create or replace function public.profile_me()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb:=public.profile_me_before_v35();car uuid;
begin
 select id into car from public.careers where user_id=auth.uid() and status='active';
 return r||jsonb_build_object('avatars',(select coalesce(jsonb_agg(jsonb_build_object('id',a.id,'label',a.label,'granted_at',pa.granted_at,'source',pa.source) order by pa.granted_at,a.sort_order),'[]')
  from public.player_avatars pa join public.avatar_catalog a on a.id=pa.avatar_id where pa.career_id=car));
end $$;

-- Recebe o presente da atualização (uma vez). Retorna o que foi dado e se a tela de novidades ainda precisa aparecer.
create or replace function public.release_gift_claim()
returns jsonb language plpgsql security definer set search_path=public as $$
declare v_c public.careers;g public.release_gifts;av text;lvl int;comp jsonb;
begin
 select * into v_c from public.careers where user_id=auth.uid() and status='active' for update;
 if not found then return jsonb_build_object('eligible',false);end if;
 select * into g from public.release_gifts where release_id='2026-temporadas-v2' and career_id=v_c.id for update;
 if not found then return jsonb_build_object('eligible',false);end if;
 if g.claimed_at is null then
  lvl:=v_c.level;
  update public.careers set xp=xp+1000 where id=v_c.id;
  perform public.econ_apply(v_c.id,'bonus_energy',20,'release_gift','2026-temporadas-v2');
  select id into av from public.avatar_catalog a where active and not exists(select 1 from public.player_avatars p where p.career_id=v_c.id and p.avatar_id=a.id) order by random() limit 1;
  if av is not null then insert into public.player_avatars(career_id,avatar_id,source) values(v_c.id,av,'release_gift') on conflict do nothing;end if;
  update public.release_gifts set claimed_at=now(),level_before=lvl,level_after=(select level from public.careers where id=v_c.id),avatar_id=av
   where release_id=g.release_id and career_id=v_c.id returning * into g;
  if to_regclass('public.mgr_messages') is not null then
   insert into public.mgr_messages(career_id,season_id,day_no,kind,title,body)
   select v_c.id,(select id from public.career_seasons where career_id=v_c.id and status='active' order by season_no desc limit 1),
    coalesce((select day_no from public.career_seasons where career_id=v_c.id and status='active' order by season_no desc limit 1),0),'system',
    'Novidades da temporada','Obrigado por testar! Você ganhou 1.000 de XP, 20 de energia e um avatar de lenda. As cartas Destaque, Épica e Lenda viraram moedas e energia. Veja como o modo Temporadas funciona agora na tela de novidades (Perfil → Novidades).';
  end if;
 end if;
 select coalesce(jsonb_agg(jsonb_build_object('tier',tier,'qty',qty,'coins',coins,'diamonds',diamonds,'energy',energy)),'[]') into comp
  from(select tier,sum(qty)::int qty,sum(coins)::int coins,sum(diamonds)::int diamonds,sum(energy)::int energy from public.base_card_compensations where career_id=v_c.id group by tier) x;
 return jsonb_build_object('eligible',true,'release','2026-temporadas-v2','show',g.seen_at is null,'xp',1000,'energy',20,
  'level_before',g.level_before,'level_after',g.level_after,'level',(select level from public.careers where id=v_c.id),
  'avatar',(select jsonb_build_object('id',a.id,'label',a.label) from public.avatar_catalog a where a.id=g.avatar_id),
  'compensation',comp);
end $$;

create or replace function public.release_gift_seen()
returns jsonb language plpgsql security definer set search_path=public as $$
begin
 update public.release_gifts set seen_at=coalesce(seen_at,now())
  where release_id='2026-temporadas-v2' and career_id=(select id from public.careers where user_id=auth.uid() and status='active') and claimed_at is not null;
 return jsonb_build_object('ok',true);
end $$;

revoke all on function public.profile_set_avatar_before_v35(text),public.profile_me_before_v35() from public,anon,authenticated;
revoke all on function public.profile_set_avatar(text),public.profile_me(),public.release_gift_claim(),public.release_gift_seen() from public,anon;
grant execute on function public.profile_set_avatar(text),public.profile_me(),public.release_gift_claim(),public.release_gift_seen() to authenticated;
notify pgrst,'reload schema';
commit;
