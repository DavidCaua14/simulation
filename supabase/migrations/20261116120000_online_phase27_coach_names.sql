-- MODO ONLINE — Fase 27: nome do técnico de cada lado na partida.
-- on_match_payload passa a mandar o apelido do técnico (careers.nickname) em home.coach e away.coach; bot fica nulo.
-- A tela mostra os dois técnicos lado a lado, e "offline" quando o adversário não está acompanhando o jogo.
create or replace function public.on_coach_name(p_user uuid) returns text
language sql stable security definer set search_path=public as $$
 select case when p_user is null then null else
  (select c.nickname from public.careers c where c.user_id=p_user order by (c.status='active') desc,c.created_at desc limit 1) end
$$;
revoke all on function public.on_coach_name(uuid) from public,anon,authenticated;

do $$ begin
 perform public.on_patch('public.on_match_payload(bigint,integer,character)',
  '''home'',jsonb_build_object(''id'',h.id,''name'',h.name,''short'',h.short,''colors'',h.colors,''bot'',h.user_id is null)',
  '''home'',jsonb_build_object(''id'',h.id,''name'',h.name,''short'',h.short,''colors'',h.colors,''bot'',h.user_id is null,''coach'',public.on_coach_name(h.user_id))');
 perform public.on_patch('public.on_match_payload(bigint,integer,character)',
  '''away'',jsonb_build_object(''id'',a.id,''name'',a.name,''short'',a.short,''colors'',a.colors,''bot'',a.user_id is null)',
  '''away'',jsonb_build_object(''id'',a.id,''name'',a.name,''short'',a.short,''colors'',a.colors,''bot'',a.user_id is null,''coach'',public.on_coach_name(a.user_id))');
end $$;
