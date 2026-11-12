-- MODO TEMPORADAS — premiação na escala do dinheiro do modo online (1 moeda = $ 1 no online).
-- Referência do online: clube começa com $ 150 mil, título da liga paga $ 200 mil, jogador nota 80 vale $ 40 mil,
-- destaque parte de $ 520 mil e lenda de $ 650 mil. Um Brasileirão vencido (1 milhão) compra uma lenda e um reforço.
-- As proporções entre posições e entre competições seguem as do futebol real. Pode ser reaplicado.
insert into public.sim_prizes(competition_id,league,stages,win,draw,source)
select v.id,v.league,v.stages,v.win,v.draw,v.source from(values
 ('brasileirao',array[1000000,950000,900000,850000,800000,750000,700000,650000,600000,550000,450000,420000,390000,360000,350000,340000,0,0,0,0],'{}'::jsonb,2500,800,'Proporção CBF 2024; campeão = 1 milhão'),
 ('serie_b',array[150000,100000,80000,80000,40000,40000,30000,30000,25000,25000,20000,20000,15000,15000,10000,10000,0,0,0,0],'{}'::jsonb,800,250,'Campeão e acesso'),
 ('copa_brasil','{}'::int[],'{"group":0,"r16":60000,"qf":150000,"sf":350000,"runner_up":800000,"champion":1500000}'::jsonb,3000,0,'Proporção CBF 2024, acumulado'),
 ('libertadores','{}'::int[],'{"group":250000,"r16":400000,"qf":600000,"sf":900000,"runner_up":1500000,"champion":2500000}'::jsonb,4000,1000,'Proporção Conmebol 2024, acumulado'),
 ('ucl','{}'::int[],'{"group":400000,"r16":700000,"qf":1100000,"sf":1600000,"runner_up":2400000,"champion":3500000}'::jsonb,5000,1500,'Proporção UEFA, acumulado'),
 ('eng_premier',array(select 1800000-70000*(i-1) from generate_series(1,20) i),'{}'::jsonb,3500,1200,'Mérito por posição'),
 ('esp_laliga',array(select 1400000-60000*(i-1) from generate_series(1,20) i),'{}'::jsonb,3000,1000,'Mérito por posição'),
 ('ita_seriea',array(select 1400000-60000*(i-1) from generate_series(1,20) i),'{}'::jsonb,3000,1000,'Mérito por posição'),
 ('ger_bundesliga',array(select 1400000-68000*(i-1) from generate_series(1,18) i),'{}'::jsonb,3000,1000,'Mérito por posição'),
 ('fra_ligue1',array(select 1000000-48000*(i-1) from generate_series(1,18) i),'{}'::jsonb,2500,800,'Mérito por posição'),
 ('por_primeira',array(select 450000-22000*(i-1) from generate_series(1,18) i),'{}'::jsonb,1500,500,'Mérito por posição'),
 ('arg_primera',array(select greatest(0,250000-14000*(i-1)) from generate_series(1,20) i),'{}'::jsonb,1200,400,'Estimativa'),
 ('fa_cup','{}'::int[],'{"group":0,"r16":15000,"qf":50000,"sf":120000,"runner_up":220000,"champion":400000}'::jsonb,2500,0,'Acumulado')
) v(id,league,stages,win,draw,source)
where exists(select 1 from public.sim_competitions c where c.id=v.id)
on conflict(competition_id) do update set league=excluded.league,stages=excluded.stages,win=excluded.win,draw=excluded.draw,source=excluded.source;
-- demais ligas e copas do catálogo
update public.sim_prizes z set
 league=case when c.kind='league' then array(select greatest(0,150000-9000*(i-1)) from generate_series(1,20) i) else '{}'::int[] end,
 stages=case when c.kind='league' then '{}'::jsonb
  when c.region='ENG' then '{"group":0,"r16":10000,"qf":35000,"sf":80000,"runner_up":160000,"champion":300000}'::jsonb
  else '{"group":0,"r16":5000,"qf":15000,"sf":40000,"runner_up":80000,"champion":150000}'::jsonb end,
 win=case when c.kind='league' then 1000 else 1500 end,draw=case when c.kind='league' then 300 else 0 end,source='Estimativa'
from public.sim_competitions c
where c.id=z.competition_id and z.competition_id not in('brasileirao','serie_b','copa_brasil','libertadores','ucl','eng_premier','esp_laliga','ita_seriea','ger_bundesliga','fra_ligue1','por_primeira','arg_primera','fa_cup');
