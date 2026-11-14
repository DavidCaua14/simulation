-- Evolução 72: piso de elenco para os clubes da IA.
--
-- Problema (produção, carreira com 4 temporadas): o Fortaleza da IA chegou a 7 jogadores. Saídas por venda, fim de
-- contrato e moral baixa não eram repostas: a IA só renova quem tem moral >= 35 ou nota 80+, e o resgate de livres só
-- pega nota 80+. O clube tinha caixa de sobra e havia 137 jogadores livres no mundo.
--
-- Agora, a cada dia de mercado (cw_ai_contracts_tick), clube da IA do país ativo com menos de 18 jogadores contrata
-- livres por necessidade de posição (2 goleiros, 6 defensores, 6 meio-campistas, 4 atacantes), do nível mais próximo
-- do elenco, com salário mínimo do atleta e contrato de 1 ano.
create or replace function public.cw_ai_squad_floor(p_career uuid) returns integer
language plpgsql security definer set search_path to 'public' as $function$
#variable_conflict use_column
declare d date;own text;cl record;grp text;pid text;n int:=0;cnt int;lvl numeric;
begin
 select today into d from public.cw_world where career_id=p_career;
 if d is null then return 0;end if;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 for cl in select mp.club_id,count(*) c from public.mgr_players mp
   where mp.career_id=p_career and mp.club_id is not null and mp.club_id is distinct from own
     and mp.club_id in(select public.cw_domestic_clubs(p_career))
   group by mp.club_id having count(*)<18 order by mp.club_id loop
  cnt:=cl.c;
  select avg(r.rating) into lvl from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
   join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position where mp.career_id=p_career and mp.club_id=cl.club_id;
  while cnt<18 loop
   -- posição que mais falta
   select g into grp from(
    select g,need-coalesce((select count(*) from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id
     where mp.career_id=p_career and mp.club_id=cl.club_id and case when sp.position='GOL' then 'G' when sp.position in('ZAG','LD','LE') then 'D'
      when sp.position in('VOL','MC','MEI') then 'M' else 'A' end=g),0) gap
    from(values('G',2),('D',6),('M',6),('A',4))v(g,need))x order by gap desc,g limit 1;
   select mp.player_id into pid from public.mgr_players mp join public.sim_players sp on sp.id=mp.player_id and sp.active
    join public.sim_player_pos_ratings r on r.player_id=sp.id and r.pos=sp.position
    join public.cw_players cp on cp.career_id=mp.career_id and cp.player_id=mp.player_id and cp.retired_on is null
   where mp.career_id=p_career and mp.club_id is null and(sp.career_id is null or sp.career_id=p_career)
    and not exists(select 1 from public.cw_contracts ct where ct.career_id=p_career and ct.player_id=mp.player_id and ct.status='active')
    and not exists(select 1 from public.cw_negotiations ng where ng.career_id=p_career and ng.player_id=mp.player_id
     and ng.status not in('completed','rejected','expired','cancelled','failed_funds'))
   order by(case when sp.position='GOL' then 'G' when sp.position in('ZAG','LD','LE') then 'D' when sp.position in('VOL','MC','MEI') then 'M' else 'A' end)<>grp,
    abs(r.rating-coalesce(lvl,65)),mp.player_id
   limit 1;
   exit when pid is null;
   perform public.cw_ensure_club_finance(p_career,cl.club_id);
   update public.mgr_players set club_id=cl.club_id where career_id=p_career and player_id=pid and club_id is null;
   insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,role)
    values(p_career,pid,cl.club_id,d,d+365,public.cw_salary_floor(pid),'rotation');
   cnt:=cnt+1;n:=n+1;pid:=null;
  end loop;
 end loop;
 return n;
end $function$;
revoke all on function public.cw_ai_squad_floor(uuid) from public,anon,authenticated;

CREATE OR REPLACE FUNCTION public.cw_ai_contracts_tick(p_career uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
#variable_conflict use_column
declare ct public.cw_contracts;d date;own text;wage bigint;payroll bigint;revenue bigint;cash bigint;inactive boolean;
begin
 select today into d from public.cw_world where career_id=p_career;
 select club_id into own from public.mgr_coach where career_id=p_career and status='employed';
 perform public.cw_recover_ai_free_players(p_career);
 -- Evolução 72: nenhum clube da IA fica sem elenco para jogar.
 perform public.cw_ai_squad_floor(p_career);
 for ct in select x.* from public.cw_contracts x join public.mgr_players mp on mp.career_id=x.career_id and mp.player_id=x.player_id and mp.club_id=x.club_id
  where x.career_id=p_career and x.status='active' and not x.computed and x.club_id is distinct from own and x.expires_on<=d+45
  and not exists(select 1 from public.cw_negotiations n where n.career_id=p_career and n.player_id=x.player_id and
   (n.status in('agreed','precontract') or(n.status in('seller_review','club_pending','club_counter','player_pending','player_counter') and n.expires_on>=d)))
  order by x.club_id,x.player_id loop
  inactive:=public.cw_runtime_enabled(p_career) and ct.club_id not in(select public.cw_domestic_clubs(p_career));
  if inactive then
   -- Dormant leagues retain their clubs; no salary, cash, results or market simulation is advanced there.
   if ct.expires_on<d then update public.cw_contracts set expires_on=ct.expires_on+make_interval(years=>greatest(2,ceil((d-ct.expires_on)/365.0)::int+2)) where id=ct.id and career_id=ct.career_id;end if;
   continue;
  end if;
  wage:=greatest(ct.monthly_salary,public.cw_salary_floor(ct.player_id));
  select c.monthly_revenue,c.cash-c.debt-public.cw_reserved(p_career,ct.club_id) into revenue,cash from public.cw_clubs c where c.career_id=p_career and c.club_id=ct.club_id and c.financial_risk<75;
  payroll:=public.cw_payroll(p_career,ct.club_id);
  if revenue is not null and cash>=2*payroll+6*greatest(0,wage-ct.monthly_salary)
   and payroll-ct.monthly_salary+wage<=revenue
   and((select r.rating>=80 from public.sim_players p join public.sim_player_pos_ratings r on r.player_id=p.id and r.pos=p.position where p.id=ct.player_id)
    or coalesce((select morale from public.cw_players where career_id=p_career and player_id=ct.player_id),65)>=35) then
   update public.cw_contracts set status='ended',ended_on=d-1 where id=ct.id and career_id=ct.career_id;
   insert into public.cw_contracts(career_id,player_id,club_id,starts_on,expires_on,monthly_salary,appearance_bonus,goal_bonus,role)
    values(p_career,ct.player_id,ct.club_id,d,d+730,wage,ct.appearance_bonus,ct.goal_bonus,ct.role);
  end if;
 end loop;
end $function$;
