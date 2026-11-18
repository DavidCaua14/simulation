-- Premiação de campeão da Liga e da Copa Online pela caixa de entrada (supabase/online/32_competition_prizes.sql).
-- A premiação de avisos e comunicados passa a aceitar também XP e as insígnias de campeão (honor_first_league,
-- honor_first_cup, honor_league, honor_cup). No resgate: XP soma na carreira; a insígnia (on_honors) vai para o perfil.

create or replace function public.inbox_reward_clean(p jsonb)
returns jsonb language sql immutable set search_path=public,pg_temp as $$
 select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) from(
  select k,to_jsonb(least(case when k='golden_whistle' then 50 when k like 'honor_%' then 1 when k='xp' then 100000 else 1000000 end,greatest(0,(p->>k)::numeric))::int) v
  from unnest(array['coins','diamonds','bonus_energy','golden_whistle','xp','honor_first_league','honor_first_cup','honor_league','honor_cup']) k
  where p ? k and (p->>k) ~ '^\d+(\.\d+)?$' and (p->>k)::numeric>0) x
$$;

create or replace function public.inbox_reward_text(p jsonb)
returns text language sql immutable set search_path=public,pg_temp as $$
 select nullif(concat_ws(' · ',
  case when (p->>'coins')::int>0 then to_char((p->>'coins')::int,'FM999G999G999')||' moedas' end,
  case when (p->>'diamonds')::int>0 then (p->>'diamonds')||' diamantes' end,
  case when (p->>'bonus_energy')::int>0 then (p->>'bonus_energy')||' de energia' end,
  case when (p->>'golden_whistle')::int>0 then (p->>'golden_whistle')||' Apitos de Ouro' end,
  case when (p->>'xp')::int>0 then (p->>'xp')||' de XP' end,
  case when p ?| array['honor_first_league','honor_first_cup','honor_league','honor_cup'] then 'insígnia de campeão' end),'')
$$;

create or replace function public.inbox_claim(p_type text,p_id text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare car uuid:=public.cw_current_career();rw jsonb;k text;a public.announcements;n public.player_notices;v_user uuid;
begin
 if car is null then raise exception 'Carreira ativa não encontrada';end if;
 select user_id into v_user from public.careers where id=car for update;
 if p_type='announcement' then
  select * into a from public.announcements where id::text=p_id and cancelled_at is null and starts_at<=now() and ends_at>now();
  if not found then raise exception 'Aviso encerrado';end if;
  if exists(select 1 from public.announcement_reads where announcement_id=a.id and career_id=car and claimed_at is not null) then
   return jsonb_build_object('ok',true,'replayed',true,'reward',a.reward);end if;
  -- item da conta: uma vez por usuário, mesmo com mais de uma carreira
  if a.reward ? 'golden_whistle' and exists(select 1 from public.announcement_reads r join public.careers c on c.id=r.career_id
    where r.announcement_id=a.id and c.user_id=v_user and r.claimed_at is not null) then
   return jsonb_build_object('ok',true,'replayed',true,'reward',a.reward);end if;
  rw:=a.reward;
  insert into public.announcement_reads(announcement_id,career_id,seen_at,claimed_at) values(a.id,car,now(),now())
  on conflict(announcement_id,career_id) do update set claimed_at=now(),seen_at=coalesce(announcement_reads.seen_at,now());
 elsif p_type='notice' then
  select * into n from public.player_notices where id::text=p_id and career_id=car for update;
  if not found then raise exception 'Mensagem não encontrada';end if;
  if n.claimed_at is not null then return jsonb_build_object('ok',true,'replayed',true,'reward',n.reward);end if;
  rw:=n.reward;
  update public.player_notices set claimed_at=now(),seen_at=coalesce(seen_at,now()) where id=n.id;
 else raise exception 'Item inválido';end if;
 if rw='{}'::jsonb then raise exception 'Este item não tem premiação';end if;
 for k in select jsonb_object_keys(rw) loop
  if k='golden_whistle' then
   insert into public.on_items(user_id,item,qty) values(v_user,k,(rw->>k)::int)
   on conflict(user_id,item) do update set qty=public.on_items.qty+excluded.qty;
  elsif k='xp' then
   update public.careers set xp=xp+(rw->>k)::int where id=car;
  elsif k like 'honor_%' then
   -- insígnia de campeão: passa a aparecer no perfil
   update public.on_honors set claimed_at=now() where id=(select h.id from public.on_honors h where h.user_id=v_user
    and h.comp=case when k like '%league' then 'L' else 'C' end and h.first=(k like 'honor_first_%') and h.claimed_at is null
    order by h.awarded_at limit 1);
  else
   perform public.econ_apply(car,k,(rw->>k)::int,'inbox_reward',p_type||':'||p_id);
  end if;
 end loop;
 return jsonb_build_object('ok',true,'replayed',false,'reward',rw);
end $$;

-- Perfil (o próprio e o de amigos): insígnias de campeão do modo Online, já resgatadas, na vitrine do topo.
do $$ begin
 perform public.on_patch('public.profile_build(uuid,boolean)',
  '''privacy'', case when p_full then priv end));',
  '''honors'', public.on_honors_json(v_c.user_id),
    ''privacy'', case when p_full then priv end));');
end $$;
