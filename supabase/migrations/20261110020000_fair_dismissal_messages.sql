-- Demissão justa e mensagens profissionais (2026-11-10).
-- 1. Eliminação com o elenco insatisfeito só demite quando o treinador também não vai bem no resto da temporada.
--    Liga dentro da meta (ou perto dela), líder/vice de um grupo ou vivo no mata-mata de outra competição
--    seguram o cargo: a diretoria mantém o treinador e manda um recado.
-- 2. Acentos corrompidos em textos de funções ("BalanÃ§o", "nÃ£o"...) voltam ao normal.
-- 3. Mensagens da diretoria, da torcida, do elenco e do mercado de treinadores reescritas em tom profissional,
--    sem citar regras internas do jogo (números de reputação, pontos de ranking, veto do clube).
-- Nada do progresso é apagado: só funções.

-- ---------------------------------------------------------------- 2. acentos corrompidos
do $$ declare fn record; src text; fixed text; m text; good text; begin
 for fn in select p.oid from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind = 'f'
            and pg_get_functiondef(p.oid) ~ '(Ã|Â|â)' loop
  src := pg_get_functiondef(fn.oid); fixed := src;
  for m in select distinct x[1] from regexp_matches(src, '(â..|Ã.|Â.)', 'g') x loop
   begin
    good := convert_from(convert_to(m, 'WIN1252'), 'UTF8');
   exception when others then
    begin good := convert_from(convert_to(m, 'LATIN1'), 'UTF8'); exception when others then good := null; end;
   end;
   if good is not null and length(good) = 1 then fixed := replace(fixed, m, good); end if;
  end loop;
  if fixed <> src then execute fixed; end if;
 end loop;
end $$;

-- ---------------------------------------------------------------- 1. demissão justa
-- O treinador vai bem em outra frente? (liga dentro/perto da meta, 1º ou 2º de um grupo, ou vivo no mata-mata)
create or replace function public.mgr_coach_standing_ok(p_career uuid, p_club text, p_skip_comp text)
 returns boolean language plpgsql stable security definer set search_path to 'public' as $$
declare r record; g text; ps int; pl int; lg text;
begin
 lg := public.cw_league_status(p_career)->>'risk';
 if lg in ('ok', 'attention') then return true; end if;
 for r in select sc.season_id, sc.competition_id, sc.stage, k.kind
            from public.season_competitions sc
            join public.career_seasons s on s.id = sc.season_id
            join public.sim_competitions k on k.id = sc.competition_id
           where s.career_id = p_career and s.status = 'active' and sc.status is distinct from 'finished'
             and sc.competition_id is distinct from p_skip_comp and (k.kind <> 'league' or lg is null) loop
  if r.kind = 'league' then
   -- sem meta de liga definida: vale a metade de cima da tabela (ou começo de campeonato)
   select t.pos, t.played into ps, pl from public.sim_standings(r.season_id, r.competition_id, null) t where t.club_id = p_club;
   if found and (pl < 3 or ps <= ceil((select count(*) from public.season_participants sp
       where sp.season_id = r.season_id and sp.competition_id = r.competition_id) / 2.0)) then return true; end if;
  elsif r.stage = 'group' then
   select x.group_label into g from public.season_fixtures x
    where x.season_id = r.season_id and x.competition_id = r.competition_id and x.stage = 'group'
      and p_club in (x.home_club, x.away_club) limit 1;
   if not found then continue; end if;
   select t.pos, t.played into ps, pl from public.sim_standings(r.season_id, r.competition_id, g) t where t.club_id = p_club;
   if pl >= 1 and ps <= 2 then return true; end if;
  elsif exists (select 1 from public.season_fixtures x
                 where x.season_id = r.season_id and x.competition_id = r.competition_id and x.stage = r.stage
                   and x.status = 'pending' and p_club in (x.home_club, x.away_club)) then
   return true;
  end if;
 end loop;
 return false;
end $$;
revoke all on function public.mgr_coach_standing_ok(uuid, text, text) from public, anon, authenticated;

create or replace function public.mgr_squad_check(p_fixture bigint, p_club text, p_car jsonb)
 returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare c public.mgr_coach; rr public.mgr_failure_rules; s public.career_seasons; f public.season_fixtures;
 h jsonb; e numeric; prev smallint; drag numeric := 0; b0 numeric; div int; out jsonb;
begin
 select * into f from public.season_fixtures where id = p_fixture;
 select * into c from public.mgr_coach where career_id = (select career_id from public.mgr_matches where fixture_id = p_fixture) for update;
 if c.career_id is null or c.status <> 'employed' or c.club_id is distinct from p_club then return p_car; end if;
 select * into rr from public.mgr_failure_rules;
 select * into s from public.career_seasons where id = f.season_id;
 h := public.cw_squad_unrest(c.career_id, p_club);
 e := (h->>'harmony')::numeric;
 prev := c.squad_warned;
 b0 := coalesce((p_car #>> '{board,before}')::numeric, c.board_confidence);

 -- diretoria perde a confiança com o vestiário em crise
 if e < rr.squad_warn1 then
  drag := round((rr.squad_warn1 - e) / rr.squad_board_drag, 2);
  update public.mgr_coach set board_confidence = round(greatest(0, board_confidence - drag), 2)
   where career_id = c.career_id returning * into c;
 end if;

 if e < rr.squad_warn2 and c.squad_warned < 2 then
  perform public.mgr_msg(c.career_id, s.id, s.day_no, 'board', 'Diretoria cobra solução para o vestiário',
   'O desgaste na relação entre a comissão técnica e o elenco tornou-se motivo de preocupação para a diretoria. Vários atletas manifestaram insatisfação com a falta de oportunidades, e a continuidade do trabalho passa a depender de uma melhora no ambiente e nos resultados.', p_club);
  update public.mgr_coach set squad_warned = 2 where career_id = c.career_id;
 elsif e < rr.squad_warn1 and c.squad_warned < 1 then
  perform public.mgr_msg(c.career_id, s.id, s.day_no, 'board', 'Diretoria atenta ao ambiente do elenco',
   'A diretoria acompanha com atenção o ambiente no vestiário. Parte do grupo demonstra insatisfação com a falta de oportunidades, e a expectativa é de que a gestão do elenco seja revista nas próximas partidas.', p_club);
  update public.mgr_coach set squad_warned = 1 where career_id = c.career_id;
 elsif e >= rr.squad_warn1 + 8 and c.squad_warned > 0 then
  update public.mgr_coach set squad_warned = 0 where career_id = c.career_id;
 end if;

 out := p_car || jsonb_build_object('squad', jsonb_build_object('harmony', e, 'unhappy', h->'unhappy', 'angry', h->'angry'),
   'board', jsonb_build_object('before', p_car #> '{board,before}', 'after', round(c.board_confidence),
            'delta', round(c.board_confidence - b0, 1)));

 -- eliminação + elenco insatisfeito (já avisado antes deste jogo)
 if coalesce((p_car->>'eliminated')::boolean, false) and e < rr.squad_fire and prev >= 1 and p_car->>'fire_reason' is null then
  if public.mgr_coach_standing_ok(c.career_id, p_club, f.competition_id) then
   -- vai bem em outra frente: a diretoria mantém o treinador
   perform public.mgr_msg(c.career_id, s.id, s.day_no, 'board', 'Diretoria mantém a confiança no trabalho',
    'A eliminação e a insatisfação de parte do elenco foram discutidas pela diretoria. O desempenho da equipe nas demais competições sustenta a continuidade do trabalho, mas o ambiente do vestiário precisa de atenção.', p_club);
   return out;
  end if;
  update public.mgr_coach
     set rank_penalty = rank_penalty + rr.squad_fire_rank_points,
         reputation = round(greatest(0, reputation - rr.squad_fire_reputation), 2)
   where career_id = c.career_id;
  div := public.mgr_club_division(c.career_id, p_club);
  insert into public.mgr_club_bans(career_id, club_id, reason, season_no, min_reputation, division)
  values (c.career_id, p_club, 'elenco', s.season_no, 100, div)
  on conflict (career_id, club_id) do update set reason = 'elenco', season_no = excluded.season_no,
    min_reputation = greatest(public.mgr_club_bans.min_reputation, excluded.min_reputation), division = excluded.division, created_at = now();
  out := out || jsonb_build_object('fire_reason', 'eliminação e desgaste no relacionamento com o elenco',
    'squad_fire', true,
    'ranking', jsonb_build_object('delta', coalesce((p_car #>> '{ranking,delta}')::int, 0) - rr.squad_fire_rank_points),
    'reputation', jsonb_build_object('before', p_car #> '{reputation,before}', 'after', round(c.reputation - rr.squad_fire_reputation, 1),
                  'delta', round(coalesce((p_car #>> '{reputation,delta}')::numeric, 0) - rr.squad_fire_reputation, 2)));
 end if;
 return out;
end $$;
revoke all on function public.mgr_squad_check(bigint, text, jsonb) from public, anon, authenticated;

-- ---------------------------------------------------------------- 3. mensagens
-- Troca textos dentro de uma função já instalada; falha se algum texto esperado não existir.
create or replace function public._msg_swap(p_fn text, p_pairs text[])
 returns void language plpgsql as $$
declare src text; i int;
begin
 src := pg_get_functiondef(p_fn::regprocedure);
 for i in 1 .. array_length(p_pairs, 1) / 2 loop
  if position(p_pairs[2*i] in src) > 0 then continue; end if;       -- já trocado
  if position(p_pairs[2*i-1] in src) = 0 then raise exception '%: texto não encontrado: %', p_fn, left(p_pairs[2*i-1], 60); end if;
  src := replace(src, p_pairs[2*i-1], p_pairs[2*i]);
 end loop;
 execute src;
end $$;

select public._msg_swap('public.mgr_after_user_match(bigint)', array[
 '''Ultimato da diretoria''', '''Diretoria exige reação imediata''',
 '''A paciência acabou. Sem resultados imediatos, o seu cargo estará em risco.''',
 '''A sequência de resultados esgotou a margem de tolerância da diretoria. A continuidade do trabalho depende de uma resposta imediata em campo.''',
 '''Diretoria preocupada''', '''Diretoria cobra melhores resultados''',
 '''Os resultados estão abaixo do esperado. A diretoria quer ver reação nos próximos jogos.''',
 '''O desempenho recente está abaixo do planejado para a temporada. A diretoria espera uma reação nas próximas partidas.''',
 '''Protesto da torcida''', '''Torcida manifesta insatisfação''',
 '''Faixas e vaias no estádio: a torcida pede a saída do treinador.''',
 '''Houve protestos nas arquibancadas após a partida. Parte da torcida questiona o trabalho da comissão técnica e cobra mudanças.''',
 '''resultados muito abaixo do esperado''', '''desempenho abaixo das metas da temporada''',
 'v_fire := ''pressão da torcida''', 'v_fire := ''desgaste com a torcida e resultados insuficientes''']);

select public._msg_swap('public.mgr_group_exit(bigint,text,jsonb)', array[
 '''Vexame na fase de grupos''', '''Diretoria lamenta a eliminação na fase de grupos''',
 '''Cair na fase de grupos %s é inadmissível. A diretoria exige reação imediata.''',
 '''A eliminação na fase de grupos %s ficou muito abaixo do planejamento do clube. A diretoria espera uma resposta à altura nas próximas competições.''',
 '''Torcida revoltada''', '''Torcida cobra explicações''',
 '''Vaias, faixas de protesto e cobrança no aeroporto: a eliminação ainda nos grupos revoltou a torcida.''',
 '''A eliminação precoce gerou forte reação da torcida, com protestos e cobranças à comissão técnica.''']);

select public._msg_swap('public.mgr_fire(uuid,text)', array[
 '||'': ''||p_reason||''. A credibilidade e o acesso a novas propostas foram afetados.''',
 '||'' comunicou oficialmente a saída do treinador. Motivo informado: ''||p_reason||''. A decisão repercute no mercado e pode influenciar as próximas propostas.''']);

select public._msg_swap('public.mgr_fire_before_world(uuid,text)', array[
 '''Você foi demitido''', '''Comunicado oficial: contrato encerrado''',
 '''A diretoria %s decidiu encerrar o seu trabalho (%s). Agora é aguardar propostas: elas chegam com o passar dos dias.''',
 '''A diretoria %s comunica o encerramento do seu contrato. Motivo: %s. O clube agradece pelos serviços prestados. Novas propostas de trabalho chegarão ao longo dos próximos dias.''']);

select public._msg_swap('public.mgr_relegation_fallout(uuid,uuid,text)', array[
 '''Diretoria revoltada''', '''Diretoria se pronuncia sobre o rebaixamento''',
 '''O rebaixamento %s é inaceitável. A diretoria não quer mais o seu nome no clube.''',
 '''O rebaixamento %s representa o descumprimento do principal objetivo da temporada. A diretoria considera o resultado incompatível com a continuidade do trabalho.''',
 '''Torcida em fúria''', '''Torcida protesta após o rebaixamento''',
 '''Protestos na porta do CT, pichações no muro e gritos de "fora!": a torcida responsabiliza você pela queda.''',
 '''Torcedores protestaram em frente ao centro de treinamento e responsabilizam a comissão técnica pela queda de divisão.''',
 ''' é rebaixado e demite o treinador''', ''' é rebaixado e encerra o contrato do treinador''',
 '''Diretoria e torcida estão revoltadas. Sua reputação despencou e só clubes menores devem procurar você. %s não volta a fazer proposta até sua reputação chegar a %s.''',
 '''O rebaixamento teve forte repercussão e abalou a sua imagem no mercado. A tendência é que as próximas propostas venham de clubes de menor porte, e um retorno a %s não está nos planos da diretoria.''']);

select public._msg_swap('public.mgr_resign()', array[
 '''Você pediu demissão''', '''Pedido de demissão aceito''',
 '''Você deixou %s. Avance os dias para receber propostas.''',
 '''O seu vínculo com %s foi encerrado a seu pedido. Novas propostas de trabalho chegarão ao longo dos próximos dias.''']);

select public._msg_swap('public.cw_vacancies_tick(uuid)', array[
 '''A diretoria aprovou seu nome: sua reputação (%s) atende ao porte do clube (pede %s). A proposta está em Carreira > Propostas.''',
 '''A diretoria aprovou o seu nome para o cargo. A proposta formal está disponível em Carreira > Propostas.''',
 '''A diretoria preferiu um nome mais experiente. Para o porte do clube, ela pede reputação %s; a sua é %s (credibilidade %s também pesa).''',
 '''A diretoria agradece o interesse, mas optou por um profissional com currículo mais consolidado para o momento do clube. Bons resultados e títulos fortalecem futuras candidaturas.''',
 ''' contratou outro treinador antes de responder à sua candidatura.''',
 ''' anunciou outro treinador e encerrou o processo de seleção.''',
 '''Com o time em %sº lugar, a diretoria abriu a vaga. Candidaturas em Carreira > Propostas.''',
 '''Com a equipe na %sª posição, a diretoria optou pela troca no comando técnico. O clube recebe candidaturas em Carreira > Propostas.''']);

select public._msg_swap('public.cw_v32_tick(uuid)', array[
 '''Último aviso: clube à beira da falência''', '''Alerta da diretoria: situação financeira crítica''',
 '''%. Sem vender atletas, cortar a folha ou investir recursos, você será demitido por irresponsabilidade financeira.''',
 '''%. A diretoria exige medidas imediatas, como a venda de atletas, a redução da folha salarial ou novos aportes. A permanência no cargo depende da recuperação das contas.''',
 '''irresponsabilidade financeira: o clube está à beira da falência''', '''gestão financeira: as contas do clube chegaram a uma situação crítica''']);

select public._msg_swap('public.mgr_ensure(public.careers)', array[
 '''Bem-vindo, professor!''', '''Boas-vindas da diretoria''',
 '''A diretoria %s confia no seu trabalho. Monte o time, defina a tática e confira os objetivos da temporada.''',
 '''A diretoria %s deposita confiança no seu trabalho. Defina a escalação e a tática e acompanhe os objetivos traçados para a temporada.''',
 '''Resultados ruins derrubam a confiança da diretoria e o humor da torcida — e o técnico pode ser demitido.''',
 '''O desempenho da equipe influencia a confiança da diretoria e o apoio da torcida.''']);

select public._msg_swap('public.career_begin_coach(uuid,text)', array[
 '''Bem-vindo, professor!''', '''Boas-vindas da diretoria''',
 '''A diretoria %s confia no seu trabalho. Monte o time, defina a tática e confira os objetivos da temporada.''',
 '''A diretoria %s deposita confiança no seu trabalho. Defina a escalação e a tática e acompanhe os objetivos traçados para a temporada.''']);

select public._msg_swap('public.mgr_season_end(uuid)', array[
 '''Você assumiu o clube na reta final: as metas desta temporada não foram cobradas. A avaliação começa na próxima.''',
 '''Você assumiu o clube na reta final da temporada, por isso as metas não foram avaliadas. A avaliação passa a valer a partir da próxima.''',
 '''Objetivos cumpridos. A diretoria está satisfeita e conta com você na próxima temporada.''',
 '''Todos os objetivos foram cumpridos. A diretoria está satisfeita e conta com você para a próxima temporada.''',
 '''%s objetivo(s) cumprido(s) e %s não. A diretoria espera evolução.''',
 '''%s objetivo(s) cumprido(s) e %s não cumprido(s). A diretoria espera evolução na próxima temporada.''',
 '''Temporada abaixo do esperado. A cobrança vai aumentar.''',
 '''A temporada ficou abaixo do planejado. A diretoria espera uma resposta já no início da próxima.''',
 '''objetivo da temporada não cumprido''', '''objetivos da temporada não cumpridos''']);

select public._msg_swap('public.cw_unrest_tick(uuid)', array[
 ''' voltou a ter espaço e deixou de lado o pedido para sair. O clima no vestiário melhorou.''',
 ''' voltou a ter espaço na equipe e retirou o pedido para sair. O ambiente no vestiário melhorou.''',
 ''' está muito insatisfeito com a falta de oportunidades e pediu para ser negociado. Dê minutos a ele ou coloque-o na lista de transferências.''',
 ''' manifestou insatisfação com a falta de oportunidades e solicitou ser negociado. Você pode dar mais minutos ao atleta ou colocá-lo na lista de transferências.''',
 ''' não vê espaço no elenco e pediu para ser liberado. Dê uma chance a ele, coloque-o na lista de transferências ou rescinda o contrato.''',
 ''' entende que não tem espaço no elenco e solicitou a liberação. Você pode dar oportunidades ao atleta, colocá-lo na lista de transferências ou rescindir o contrato.''',
 ''' segue sem resposta e voltou a reclamar. A insatisfação dele já pesa no vestiário e no rendimento do time.''',
 ''' segue sem resposta e voltou a cobrar uma definição. A insatisfação do atleta já afeta o ambiente do vestiário e o rendimento da equipe.''',
 ''' reclamou publicamente e está cada vez mais irritado. Enquanto nada mudar, ele vai continuar cobrando — e o time sente.''',
 ''' tornou pública a sua insatisfação. Enquanto a situação não for resolvida, o ambiente do elenco continuará prejudicado.''',
 ''' perdeu a paciência''', ''' torna pública a insatisfação''']);

drop function public._msg_swap(text, text[]);
notify pgrst, 'reload schema';
