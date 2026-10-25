-- =====================================================================
-- EVOLUÇÃO 12 — AMIGOS E CONVITES
--
-- * Convite por username (o mesmo apelido único da carreira; sem diferenciar maiúsculas/minúsculas, como o índice
--   careers_nickname_unique_idx). Não convida a si mesmo, não duplica convite nem amizade (índice único do PAR,
--   em qualquer direção). Se o outro já tinha te convidado, enviar = aceitar.
-- * Busca segura: só o username EXATO; a resposta não revela nada além de "existe/não existe" (sem lista de nomes,
--   sem e-mail, sem id).
-- * Limite de convites por hora (anti-spam) e de pendentes.
-- * Perfil do amigo: somente leitura, só para amigos, respeitando a privacidade dele (profile_build da evolução 11).
-- * Tempo real: a tabela entra na publicação do Supabase Realtime (cada um só recebe as próprias linhas pela RLS).
-- Rode depois de evolution/11. Idempotente.
-- =====================================================================
create table if not exists public.friendships (
  id           uuid primary key default gen_random_uuid(),
  requester    uuid not null references public.careers (id) on delete cascade,
  addressee    uuid not null references public.careers (id) on delete cascade,
  status       text not null default 'pending' check (status in ('pending', 'accepted', 'declined', 'cancelled', 'removed')),
  created_at   timestamptz not null default now(),
  responded_at timestamptz,
  check (requester <> addressee)
);
-- um convite pendente OU uma amizade por par, em qualquer direção
create unique index if not exists friendships_pair_uq on public.friendships (least(requester, addressee), greatest(requester, addressee))
  where status in ('pending', 'accepted');
create index if not exists friendships_requester_idx on public.friendships (requester, status);
create index if not exists friendships_addressee_idx on public.friendships (addressee, status);

create table if not exists public.friends_config (
  id                 boolean primary key default true check (id),
  max_requests_hour  int not null default 20 check (max_requests_hour between 1 and 500),
  max_pending_sent   int not null default 50 check (max_pending_sent between 1 and 1000),
  max_friends        int not null default 200 check (max_friends between 1 and 5000)
);
insert into public.friends_config (id) values (true) on conflict (id) do nothing;

alter table public.friendships    enable row level security;
alter table public.friends_config enable row level security;
revoke all on public.friendships, public.friends_config from anon, authenticated;
-- leitura só das próprias linhas (necessária para o Realtime avisar o app); escrita só pelas funções
grant select (id, requester, addressee, status, created_at, responded_at) on public.friendships to authenticated;
drop policy if exists "own_friendships" on public.friendships;
create policy "own_friendships" on public.friendships for select to authenticated
  using (exists (select 1 from public.careers c where c.user_id = auth.uid() and c.id in (requester, addressee)));

do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
     and not exists (select 1 from pg_publication_tables where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = 'friendships') then
    alter publication supabase_realtime add table public.friendships;
  end if;
end $$;

-- ---------------------------------------------------------------------
-- Funções
-- ---------------------------------------------------------------------
create or replace function public.friend_card(p_career uuid)
returns jsonb language sql stable security definer set search_path = public as $$
  -- resumo público para listas (mesmas regras de privacidade do perfil)
  select jsonb_strip_nulls(jsonb_build_object(
    'nickname', c.nickname, 'country', c.country, 'level', c.level, 'photo_id', c.photo_id, 'avatar', p.avatar_data,
    'club_id', case when coalesce((p.privacy ->> 'show_career')::boolean, true) then coalesce(m.club_id, c.club_id) end,
    'frame', public.cosmetic_json(p.frame_id), 'emblem', public.cosmetic_json(p.emblem_id)))
    from public.careers c
    left join public.player_profiles p on p.career_id = c.id
    left join public.mgr_coach m on m.career_id = c.id
   where c.id = p_career;
$$;

create or replace function public.friend_me()
returns uuid language plpgsql stable security definer set search_path = public as $$
declare v uuid;
begin
  select id into v from public.careers where user_id = auth.uid() and status = 'active';
  if v is null then raise exception 'Carreira ativa não encontrada'; end if;
  return v;
end;
$$;

-- Convidar por username. Devolve {status: 'sent' | 'accepted', nickname}.
create or replace function public.friend_request(p_username text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_me   public.careers;
  v_to   public.careers;
  v_cfg  public.friends_config;
  v_f    public.friendships;
  v_name text := trim(coalesce(p_username, ''));
begin
  v_me := public.sim_lock_career();          -- serializa os pedidos do mesmo usuário
  select * into v_cfg from public.friends_config;
  if length(v_name) < 3 or length(v_name) > 32 then raise exception using errcode = 'P0404', message = 'Usuário não encontrado.'; end if;
  select * into v_to from public.careers where lower(nickname) = lower(v_name) and status = 'active';
  if not found then raise exception using errcode = 'P0404', message = 'Usuário não encontrado.'; end if;
  if v_to.id = v_me.id then raise exception 'Você não pode convidar a si mesmo.'; end if;

  -- trava o par (os dois lados enviando ao mesmo tempo não criam dois convites)
  perform pg_advisory_xact_lock(hashtext('friend:' || least(v_me.id, v_to.id)::text || greatest(v_me.id, v_to.id)::text));
  select * into v_f from public.friendships
   where least(requester, addressee) = least(v_me.id, v_to.id) and greatest(requester, addressee) = greatest(v_me.id, v_to.id)
     and status in ('pending', 'accepted');
  if found then
    if v_f.status = 'accepted' then raise exception using errcode = 'P0409', message = 'Vocês já são amigos.'; end if;
    if v_f.requester = v_me.id then raise exception using errcode = 'P0409', message = 'Você já enviou um convite para este jogador.'; end if;
    -- ele já tinha me convidado: aceitar
    update public.friendships set status = 'accepted', responded_at = now() where id = v_f.id;
    return jsonb_build_object('status', 'accepted', 'nickname', v_to.nickname, 'id', v_f.id);
  end if;

  if (select count(*) from public.friendships where requester = v_me.id and created_at > now() - interval '1 hour') >= v_cfg.max_requests_hour then
    raise exception 'Muitos convites em pouco tempo. Tente de novo mais tarde.';
  end if;
  if (select count(*) from public.friendships where requester = v_me.id and status = 'pending') >= v_cfg.max_pending_sent then
    raise exception 'Você tem convites demais esperando resposta. Cancele alguns antes.';
  end if;
  if (select count(*) from public.friendships where v_me.id in (requester, addressee) and status = 'accepted') >= v_cfg.max_friends then
    raise exception 'Você chegou ao limite de amigos.';
  end if;

  insert into public.friendships (requester, addressee) values (v_me.id, v_to.id) returning * into v_f;
  return jsonb_build_object('status', 'sent', 'nickname', v_to.nickname, 'id', v_f.id);
end;
$$;

-- Aceitar/recusar um convite RECEBIDO
create or replace function public.friend_respond(p_id uuid, p_accept boolean)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.friend_me(); v_f public.friendships;
begin
  select * into v_f from public.friendships where id = p_id and addressee = v_me for update;
  if not found then raise exception 'Convite não encontrado.'; end if;
  if v_f.status <> 'pending' then
    raise exception '%', case v_f.status when 'accepted' then 'Este convite já foi aceito.' when 'declined' then 'Este convite já foi recusado.'
                              else 'Este convite não está mais disponível.' end;
  end if;
  update public.friendships set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now() where id = v_f.id;
  return jsonb_build_object('status', case when p_accept then 'accepted' else 'declined' end,
                            'nickname', (select nickname from public.careers where id = v_f.requester));
end;
$$;

-- Cancelar um convite ENVIADO (ainda pendente)
create or replace function public.friend_cancel(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.friend_me(); v_f public.friendships;
begin
  select * into v_f from public.friendships where id = p_id and requester = v_me for update;
  if not found then raise exception 'Convite não encontrado.'; end if;
  if v_f.status <> 'pending' then raise exception 'Este convite não está mais pendente.'; end if;
  update public.friendships set status = 'cancelled', responded_at = now() where id = v_f.id;
  return jsonb_build_object('status', 'cancelled');
end;
$$;

-- Desfazer amizade (qualquer um dos dois)
create or replace function public.friend_remove(p_id uuid)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.friend_me(); v_f public.friendships;
begin
  select * into v_f from public.friendships where id = p_id and v_me in (requester, addressee) for update;
  if not found or v_f.status <> 'accepted' then raise exception 'Amizade não encontrada.'; end if;
  update public.friendships set status = 'removed', responded_at = now() where id = v_f.id;
  return jsonb_build_object('status', 'removed');
end;
$$;

-- Tudo da tela de amigos: amigos, convites recebidos, enviados e recusas recentes dos meus convites
create or replace function public.friends_overview()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare v_me uuid := public.friend_me();
begin
  return jsonb_build_object(
    'friends', coalesce((select jsonb_agg(public.friend_card(case when f.requester = v_me then f.addressee else f.requester end)
                                          || jsonb_build_object('id', f.id, 'since', f.responded_at) order by lower(c.nickname))
                           from public.friendships f join public.careers c on c.id = case when f.requester = v_me then f.addressee else f.requester end
                          where f.status = 'accepted' and v_me in (f.requester, f.addressee)), '[]'::jsonb),
    'incoming', coalesce((select jsonb_agg(public.friend_card(f.requester) || jsonb_build_object('id', f.id, 'at', f.created_at) order by f.created_at desc)
                            from public.friendships f where f.addressee = v_me and f.status = 'pending'), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(public.friend_card(f.addressee) || jsonb_build_object('id', f.id, 'at', f.created_at) order by f.created_at desc)
                            from public.friendships f where f.requester = v_me and f.status = 'pending'), '[]'::jsonb),
    'declined', coalesce((select jsonb_agg(jsonb_build_object('id', f.id, 'nickname', c.nickname, 'at', f.responded_at) order by f.responded_at desc)
                            from public.friendships f join public.careers c on c.id = f.addressee
                           where f.requester = v_me and f.status = 'declined' and f.responded_at > now() - interval '7 days'), '[]'::jsonb));
end;
$$;

-- Perfil público de um AMIGO (somente leitura). Quem não é amigo não vê.
create or replace function public.friend_profile(p_username text)
returns jsonb language plpgsql security definer set search_path = public as $$
declare v_me uuid := public.friend_me(); v_to uuid; v_f public.friendships;
begin
  select id into v_to from public.careers where lower(nickname) = lower(trim(coalesce(p_username, ''))) and status = 'active';
  if v_to is null then raise exception 'Usuário não encontrado.'; end if;
  if v_to <> v_me then
    select * into v_f from public.friendships where status = 'accepted'
       and least(requester, addressee) = least(v_me, v_to) and greatest(requester, addressee) = greatest(v_me, v_to);
    if not found then raise exception 'Só amigos podem ver este perfil.'; end if;
  end if;
  perform public.profile_ensure(v_to);
  perform public.badges_refresh(v_to);        -- as insígnias do amigo ficam em dia (regras do servidor)
  return public.profile_build(v_to, false) || jsonb_build_object('friend_since', v_f.responded_at, 'friendship_id', v_f.id);
end;
$$;

revoke all on function public.friend_card(uuid), public.friend_me() from public, anon, authenticated;
revoke all on function public.friend_request(text), public.friend_respond(uuid, boolean), public.friend_cancel(uuid), public.friend_remove(uuid),
  public.friends_overview(), public.friend_profile(text) from public, anon;
grant execute on function public.friend_request(text), public.friend_respond(uuid, boolean), public.friend_cancel(uuid), public.friend_remove(uuid),
  public.friends_overview(), public.friend_profile(text) to authenticated;
