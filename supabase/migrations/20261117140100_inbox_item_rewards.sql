-- Premiação de itens pela caixa de entrada e aviso de lançamento do Apito de Ouro.
-- A premiação de avisos e comunicados passa a aceitar golden_whistle (Apito de Ouro, modo Online) além de moedas,
-- diamantes e energia. No resgate, o item entra no estoque da conta (on_items, por user_id).
-- Aviso de lançamento: 7 Apitos de Ouro para cada técnico, com o tutorial de uso e de como conseguir mais.

create or replace function public.inbox_reward_clean(p jsonb)
returns jsonb language sql immutable set search_path=public,pg_temp as $$
 select coalesce(jsonb_object_agg(k,v),'{}'::jsonb) from(
  select k,to_jsonb(least(case when k='golden_whistle' then 50 else 1000000 end,greatest(0,(p->>k)::numeric))::int) v
  from unnest(array['coins','diamonds','bonus_energy','golden_whistle']) k
  where p ? k and (p->>k) ~ '^\d+(\.\d+)?$' and (p->>k)::numeric>0) x
$$;

create or replace function public.inbox_reward_text(p jsonb)
returns text language sql immutable set search_path=public,pg_temp as $$
 select nullif(concat_ws(' · ',
  case when (p->>'coins')::int>0 then to_char((p->>'coins')::int,'FM999G999G999')||' moedas' end,
  case when (p->>'diamonds')::int>0 then (p->>'diamonds')||' diamantes' end,
  case when (p->>'bonus_energy')::int>0 then (p->>'bonus_energy')||' de energia' end,
  case when (p->>'golden_whistle')::int>0 then (p->>'golden_whistle')||' Apitos de Ouro' end),'')
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
  else
   perform public.econ_apply(car,k,(rw->>k)::int,'inbox_reward',p_type||':'||p_id);
  end if;
 end loop;
 return jsonb_build_object('ok',true,'replayed',false,'reward',rw);
end $$;

-- Aviso de lançamento (id fixo: reaplicar não duplica). Vale por 30 dias para todos resgatarem.
insert into public.announcements(id,title,body,starts_at,ends_at,reward)
values('5a1d0e00-0000-4000-8000-0000a91d0001','Novidade: Apito de Ouro',
'Chegou o Apito de Ouro, o treino de elite do Modo Online! Ele leva um jogador do seu elenco na hora à nota máxima (o potencial dele), sem gastar condição e sem usar os treinos do dia.

Para comemorar, você ganha 7 Apitos de Ouro. Toque em Resgatar.

COMO USAR
1. Entre no Modo Online e abra Elenco.
2. Vá na aba Jogadores e toque no jogador que quer evoluir.
3. Na ficha dele, toque em Apito de Ouro e depois em Usar e treinar.
4. Espere o treino terminar: o jogador volta com o nível máximo atingido.
Dica: use em jovens com potencial alto — é onde o apito rende mais.

COMO CONSEGUIR MAIS
1. Abra a Loja e vá na aba Itens (aparece para quem tem clube no Modo Online).
2. Cada Apito de Ouro custa 300 diamantes. A compra libera quando você tiver menos de 3 guardados.
3. Diamantes vêm da sequência diária (300 no dia 5 e 450 no dia 7), de eventos e de avisos como este.',
 now(),now()+interval '30 days','{"golden_whistle":7}'::jsonb)
on conflict(id) do nothing;
