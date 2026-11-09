-- Troca de clube pelo admin usa a temporada do ano atual da região (como o aceite de proposta),
-- em vez da temporada ativa mais antiga, que podia estar congelada com jogos vencidos.
CREATE OR REPLACE FUNCTION public.admin_career_set_club(p_career uuid, p_club text, p_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare w public.cw_world;c public.mgr_coach;sid uuid;spell uuid;salary bigint;old text;
begin
 perform public.admin_assert();
 if length(trim(coalesce(p_reason,'')))<3 then raise exception 'Informe o motivo.';end if;
 perform 1 from public.careers where id=p_career for update;
 select * into w from public.cw_world where career_id=p_career;
 if not found then raise exception 'Este jogador ainda não entrou no modo Temporadas.';end if;
 if not exists(select 1 from public.cw_clubs where career_id=p_career and club_id=p_club) then raise exception 'Clube inválido.';end if;
 if exists(select 1 from public.mgr_matches where career_id=p_career and status='live' and user_side is not null) then raise exception 'O jogador está com uma partida em andamento. Tente depois.';end if;
 if w.needs_sync then raise exception 'O calendário do jogador está atualizando resultados. Tente em instantes.';end if;
 -- Mesmo caminho do aceite de proposta: fecha anos antigos da região e usa a temporada do ano atual.
 -- Antes pegava a temporada ativa mais antiga, que podia estar congelada com jogos vencidos.
 perform set_config('cw.incoming_club',p_club,true);
 if public.cw_runtime_enabled(p_career) then
  sid:=public.cw_activate_region(p_career,public.cw_region(p_club));
  if (select status from public.career_seasons where id=sid)='finished' then
   sid:=public.cw_create_region(p_career,public.cw_region(p_club),
    greatest((select year from public.career_seasons where id=sid)+1,public.cw_year(public.cw_region(p_club),w.today)));
  end if;
 else
  select ws.season_id into sid from public.cw_seasons ws join public.career_seasons s on s.id=ws.season_id
   where ws.career_id=p_career and ws.region=public.cw_region(p_club) and s.status='active' order by ws.starts_on limit 1;
 end if;
 if sid is null or (select status from public.career_seasons where id=sid)<>'active' then raise exception 'A temporada desse país ainda não começou no mundo do jogador.';end if;
 perform public.cw_attach_club_leagues(p_career,sid,p_club);
 select * into c from public.mgr_coach where career_id=p_career;
 if c.club_id=p_club and c.status='employed' then raise exception 'O jogador já treina esse clube.';end if;
 old:=c.club_id;
 if c.status='employed' then perform public.mgr_end_spell(p_career,'left');end if;
 perform public.cw_promote_season(p_career,sid,p_club);spell:=public.mgr_start_spell(p_career,p_club);
 select coalesce(monthly_salary,150) into salary from public.cw_coach where career_id=p_career;
 update public.cw_coach set contract_until=(w.today+interval '2 years')::date where career_id=p_career;
 insert into public.cw_coach_contracts(career_id,spell_id,club_id,starts_on,expires_on,monthly_salary)
  values(p_career,spell,p_club,w.today,(w.today+interval '2 years')::date,coalesce(salary,150));
 update public.season_offers set status='expired',responded_at=now() where career_id=p_career and kind='coach' and status='pending';
 perform public.cw_news_add(p_career,'admin-club:'||spell,'job',public.mgr_club_name(p_club)||' anuncia novo treinador','Contrato por 2 anos. A temporada e os resultados existentes continuam.',98,p_club);
 perform public.admin_notify(p_career,'club','Você é o novo treinador do '||public.mgr_club_name(p_club),
  coalesce('Você deixou o '||public.mgr_club_name(old)||'. ','')||'Contrato de 2 anos; a temporada continua de onde está. Motivo: '||trim(p_reason));
 insert into public.admin_actions(admin_id,action,career_id,detail) values(auth.uid(),'set_club',p_career,jsonb_build_object('from',old,'to',p_club,'reason',left(trim(p_reason),200)));
 return public.admin_career(p_career);
end $function$;
