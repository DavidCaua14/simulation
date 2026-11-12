-- MODO ONLINE — Fase 15: escalações dos dois times de um jogo (vestiário e partida).
-- Antes do pontapé mostra a escalação salva de cada clube; com a partida aberta mostra quem está em campo agora
-- (substituições e mudanças de posição incluídas). Só titulares e formação: o banco do adversário não aparece.
create or replace function public.on_fixture_lineups(p_fixture bigint) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();f public.on_fixtures;m public.on_matches;v_out jsonb:='{}';i int;v_club int;k public.on_clubs;l public.on_lineups;
begin
 select * into f from public.on_fixtures where id=p_fixture and season_id=c.season_id;
 if f.id is null then raise exception 'Jogo não encontrado';end if;
 select * into m from public.on_matches where fixture_id=f.id;
 for i in 0..1 loop
  v_club:=case when i=0 then f.home else f.away end;
  select * into k from public.on_clubs where id=v_club;
  if m.fixture_id is not null and exists(select 1 from public.on_match_players where fixture_id=f.id) then
   v_out:=v_out||jsonb_build_object(case when i=0 then 'home' else 'away' end,jsonb_build_object(
    'club',jsonb_build_object('id',k.id,'name',k.name,'short',k.short,'colors',k.colors,'bot',k.user_id is null),
    'formation',m.state->'formation'->>i,'live',true,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',mp.player_id,'name',mp.name,'number',mp.number,'pos',mp.nat_pos,'ovr',mp.ovr,
      'cond',round(mp.cond),'slot',mp.slot,'yellow',mp.yellow,'starter',mp.starter) order by mp.slot)
     from public.on_match_players mp where mp.fixture_id=f.id and mp.club_id=v_club and mp.status='on' and mp.slot is not null),'[]'::jsonb)));
  else
   select * into l from public.on_lineups where club_id=v_club;
   if l.club_id is null then
    perform public.on_auto_lineup(v_club);
    select * into l from public.on_lineups where club_id=v_club;
   end if;
   v_out:=v_out||jsonb_build_object(case when i=0 then 'home' else 'away' end,jsonb_build_object(
    'club',jsonb_build_object('id',k.id,'name',k.name,'short',k.short,'colors',k.colors,'bot',k.user_id is null),
    'formation',l.formation,'live',false,
    'players',coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'number',p.number,'pos',p.pos,'sec',p.sec,'ovr',p.ovr,
      'cond',p.cond,'slot',e.key,'yellow',0,'starter',true) order by e.key)
     from jsonb_each_text(l.slots) e join public.on_players p on p.id=e.value and p.club_id=v_club),'[]'::jsonb)));
  end if;
 end loop;
 return v_out||jsonb_build_object('fixture',f.id,'my_side',case when c.id=f.home then 'h' when c.id=f.away then 'a' end,'server_now',now());
end $$;
revoke all on function public.on_fixture_lineups(bigint) from public,anon;
grant execute on function public.on_fixture_lineups(bigint) to authenticated;
