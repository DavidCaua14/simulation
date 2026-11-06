-- Lances do treinador só são avaliados depois da partida dele (2026-11-06).
-- Antes: ao tocar em JOGAR, a preparação avançava os dias até o jogo e o clube vendedor/atleta já respondia
-- (e-mail e aviso "Veja o e-mail" antes do pontapé). Agora, enquanto houver partida do treinador por jogar,
-- os lances dele (initiator='user', status club_pending/player_pending) ficam em espera durante o avanço dos dias.
-- No apito final, a resposta sai na hora e a mensagem chega à caixa de entrada ao voltar ao Início.
-- Sem partida pendente (entressafra, temporada encerrada, sem clube) o prazo normal de resposta continua valendo.

alter function public.cw_market_tick(uuid) rename to cw_market_tick_before_v70;

create or replace function public.cw_market_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date;own text;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 if own is not null and current_setting('cw.release_user_bids',true) is distinct from 'on'
    and exists(select 1 from public.season_fixtures f join public.career_seasons s on s.id=f.season_id
               where s.career_id=p_career and s.status='active' and f.status='pending' and own in(f.home_club,f.away_club)) then
  -- Em espera até o fim da próxima partida; o prazo acompanha para a proposta não expirar enquanto espera.
  update public.cw_negotiations set reply_on=greatest(reply_on,d+1),expires_on=greatest(expires_on,d+1)
   where career_id=p_career and initiator='user' and buyer_club=own and status in('club_pending','player_pending') and reply_on<=d;
 end if;
 perform public.cw_market_tick_before_v70(p_career);
end $function$;

-- Apito final da partida do treinador: libera e avalia os lances em espera no mesmo dia.
create or replace function public.cw_release_user_bids(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare d date;own text;
begin
 if not exists(select 1 from public.cw_world where career_id=p_career) then return;end if;
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 if own is null then return;end if;
 update public.cw_negotiations set reply_on=d,expires_on=greatest(expires_on,public.cw_deadline(d))
  where career_id=p_career and initiator='user' and buyer_club=own and status in('club_pending','player_pending') and reply_on>d;
 if not found then return;end if;
 perform set_config('cw.release_user_bids','on',true);
 perform public.cw_market_tick(p_career);
 perform set_config('cw.release_user_bids','off',true);
end $function$;

create or replace function public.cw_user_match_bids_trg()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
 perform public.cw_release_user_bids(new.career_id);
 return null;
end $function$;

drop trigger if exists cw_user_match_bids on public.mgr_matches;
create trigger cw_user_match_bids after update of summary on public.mgr_matches
 for each row when (old.summary is null and new.summary is not null and new.user_side is not null)
 execute function public.cw_user_match_bids_trg();

revoke all on function public.cw_market_tick(uuid) from public, anon, authenticated;
revoke all on function public.cw_market_tick_before_v70(uuid) from public, anon, authenticated;
revoke all on function public.cw_release_user_bids(uuid) from public, anon, authenticated;
revoke all on function public.cw_user_match_bids_trg() from public, anon, authenticated;
