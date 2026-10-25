-- =====================================================================
-- Modo treinador × caixas de cartas (rode DEPOIS de supabase/cards/01_cards.sql)
-- A caixa de vitória passa a considerar o clube que o usuário comandava NAQUELE jogo
-- (coach_club), não o clube atual — importante quando ele troca de clube no meio da temporada.
-- =====================================================================
create or replace function public.card_on_fixture_played()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  v_cs   record;
  v_club text;
  v_my   int;
  v_opp  int;
begin
  if not (coalesce(new.player_match, false) and new.status = 'played' and old.status is distinct from 'played') then
    return new;
  end if;
  select career_id, club_id into v_cs from public.career_seasons where id = new.season_id;
  if not found then return new; end if;
  v_club := coalesce(new.coach_club, v_cs.club_id);
  if new.home_club = v_club then v_my := new.home_goals; v_opp := new.away_goals;
  else v_my := new.away_goals; v_opp := new.home_goals; end if;
  if v_my > v_opp then
    perform public.card_grant_source(v_cs.career_id, 'season_win', new.id::text);
  end if;
  return new;
end;
$$;
revoke all on function public.card_on_fixture_played() from public, anon, authenticated;
