-- MODO TEMPORADAS — início pela Série B, sem aporte de moedas no clube, preços na escala nova e modo liberado.
-- Pode ser reaplicado.

-- Série B: 1.000 moedas por vitória
update public.sim_prizes set win=1000 where competition_id='serie_b';

-- Exercícios pré-jogo na escala nova (uma vitória no Brasileirão paga 2.500)
update public.cw_drill_rules set price=4000 where price<4000;

-- Moedas não entram mais no caixa do clube do modo Temporadas (elas servem para investir no modo Online).
select public.sim_patch('public.career_club_invest(integer,uuid)',
 ' if p_request is null then raise exception ''Identificador do aporte obrigatório'';end if;',
 ' raise exception ''No modo Temporadas não é possível investir moedas no clube. Use suas moedas no modo Online.'';'||chr(10)||
 ' if p_request is null then raise exception ''Identificador do aporte obrigatório'';end if;');

-- Recomeço: três propostas sorteadas entre os clubes da Série B (técnico com reputação inicial).
select public.sim_patch('public.career_reset_offers(uuid)',
 '   where pa.season_id=w.primary_season and pa.competition_id=''brasileirao'')x',
 '   where pa.season_id=w.primary_season and pa.competition_id=''serie_b'')x');
select public.sim_patch('public.career_reset_offers(uuid)',
 '  where x.rk between b.rank_from and b.rank_to',
 '  where x.rk>=1 -- qualquer clube da Série B');
select public.sim_patch('public.career_begin_unemployed(uuid)',
 '||''Três clubes da Série A querem conversar:','||''Três clubes da Série B querem conversar:');
select public.sim_patch('public.career_begin_unemployed(uuid)',
 '''O futebol recomeçou com Brasil e Libertadores. Sua reputação, credibilidade e ranks continuam com você. ''',
 '''O futebol recomeçou em 2026. Você começa de baixo: suba com o seu clube e as propostas maiores aparecem. ''');

-- Modo liberado para todos: a checagem de acesso deixa de barrar (as funções continuam chamando-a).
create or replace function public.seasons_require_access() returns void
language plpgsql stable security definer set search_path='' as $$
begin
 return;
end $$;
