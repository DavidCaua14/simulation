-- Recuperação física proporcional: o jogador recupera 3 pontos por dia mais 6% do que falta para 100.
-- Antes era +4,3 fixo por dia, o que deixava o titular sem rodízio em espiral com pressão alta e jogos a cada 2 dias
-- (desgaste ~28 por jogo contra ~22 de recuperação média). Forma fechada de g dias de c' = c + 3 + 0,06*(100-c):
-- 150 - (150-c)*0,94^g. Exemplos: 72 -> 81 em 2 dias, 89 em 4, 99 em 7; 40 -> 59 em 2 dias, 79 em 7.
CREATE OR REPLACE FUNCTION public.cw_recover_club(p_career uuid, p_club text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare day int;start_day int;own text;
begin
 select w.elapsed_days,coalesce(r.last_recovery_day,w.elapsed_days) into day,start_day
 from public.cw_world w left join public.cw_runtime r using(career_id) where w.career_id=p_career;
 if public.cw_is_hybrid(p_career) then
  select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
  if p_club is not distinct from own then
   -- Elenco do técnico: sempre com linha própria, para condição e ritmo evoluírem dia a dia.
   insert into public.mgr_player_rows(career_id,player_id,club_id,condition,rhythm)
   select mp.career_id,mp.player_id,mp.club_id,mp.condition,mp.rhythm from public.mgr_players mp where mp.career_id=p_career and mp.club_id=p_club
   on conflict do nothing;
   update public.mgr_player_rows p set
    condition=least(100,150-(150-p.condition)*power(0.94,greatest(0,day-coalesce(c.day_no,start_day)))),
    rhythm=greatest(35,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))),
    injury=case when p.injured_until<=day then null else p.injury end,
    injured_until=case when p.injured_until<=day then null else p.injured_until end
   from(select r.player_id,pc.day_no from public.mgr_player_rows r left join public.cw_player_clock pc using(career_id,player_id)
    where r.career_id=p_career and r.club_id=p_club and not r.removed)c
   where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
  else
   -- Clube da IA: quem tem linha volta ao padrão (condição 100, ritmo padrão) e, sem outra diferença, a linha sai.
   update public.mgr_player_rows p set
    condition=least(100,150-(150-p.condition)*power(0.94,greatest(0,day-coalesce(c.day_no,start_day)))),
    rhythm=case when p.rhythm<c.base then least(c.base,p.rhythm+.4*greatest(0,day-coalesce(c.day_no,start_day)))
     else greatest(c.base,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))) end,
    injury=case when p.injured_until<=day then null else p.injury end,
    injured_until=case when p.injured_until<=day then null else p.injured_until end
   from(select r.player_id,pc.day_no,case when sp.is_youth then 50 else 70 end base from public.mgr_player_rows r
    join public.sim_players sp on sp.id=r.player_id left join public.cw_player_clock pc on pc.career_id=r.career_id and pc.player_id=r.player_id
    where r.career_id=p_career and r.club_id=p_club and not r.removed)c
   where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
   delete from public.mgr_player_rows r using public.sim_players sp
   where r.career_id=p_career and r.club_id=p_club and not r.removed and sp.id=r.player_id and sp.career_id is null and sp.active
    and sp.club_id=r.club_id and r.condition=100 and r.rhythm=(case when sp.is_youth then 50 else 70 end)
    and r.injured_until is null and r.injury is null and r.susp='{}'::jsonb and r.yellows='{}'::jsonb
    and exists(select 1 from public.cw_world_clubs wc where wc.career_id=p_career and wc.club_id=r.club_id)
    and not exists(select 1 from public.cw_contract_rows ct where ct.career_id=p_career and ct.player_id=r.player_id and ct.club_id is distinct from r.club_id and ct.status='active');
   delete from public.cw_player_clock k where k.career_id=p_career
    and not exists(select 1 from public.mgr_player_rows r where r.career_id=p_career and r.player_id=k.player_id);
  end if;
  insert into public.cw_player_clock(career_id,player_id,day_no)
  select p_career,player_id,day from public.mgr_player_rows where career_id=p_career and club_id=p_club and not removed
  on conflict(career_id,player_id) do update set day_no=excluded.day_no where cw_player_clock.day_no<>excluded.day_no;
  return;
 end if;
 update public.mgr_players p set
 condition=least(100,150-(150-p.condition)*power(0.94,greatest(0,day-coalesce(c.day_no,start_day)))),
 rhythm=greatest(35,p.rhythm-.4*greatest(0,day-coalesce(c.day_no,start_day))),
 injury=case when p.injured_until<=day then null else p.injury end,
 injured_until=case when p.injured_until<=day then null else p.injured_until end
 from (select mp.player_id,pc.day_no from public.mgr_players mp left join public.cw_player_clock pc using(career_id,player_id)
 where mp.career_id=p_career and mp.club_id=p_club)c
 where p.career_id=p_career and p.player_id=c.player_id and day>coalesce(c.day_no,start_day);
 insert into public.cw_player_clock(career_id,player_id,day_no)
 select p_career,player_id,day from public.mgr_players where career_id=p_career and club_id=p_club
 on conflict(career_id,player_id) do update set day_no=excluded.day_no where cw_player_clock.day_no<>excluded.day_no;
end $function$;
