-- MODO ONLINE — Fase 35: Séries A, B, C e D, Copa Online com todas as séries e calendário de dois jogos por dia.
--
--  • Quatro divisões ao mesmo tempo, com acesso e rebaixamento entre elas (o tamanho de cada uma não muda):
--      A — 20 clubes, pontos corridos em turno e returno (38 rodadas). Os 4 últimos caem.
--      B — 20 clubes, 38 rodadas. 1º e 2º sobem; 3º×6º e 4º×5º em ida e volta valem as outras duas vagas
--          (empate no agregado: avança quem fez melhor campanha). Os 4 últimos caem. (Regulamento da Série B 2026.)
--      C — 24 clubes, turno único (23 rodadas). Os 8 primeiros vão para dois quadrangulares (1º,4º,5º,8º e 2º,3º,6º,7º)
--          em ida e volta; os 2 primeiros de cada grupo sobem; os líderes decidem o título em ida e volta.
--          Os 4 últimos da primeira fase caem. (Série C 2027; a real rebaixa 2, aqui são 4 para casar com a D.)
--      D — 30 clubes em 2 grupos de 15, turno e returno (30 rodadas, uma folga por turno). Os 4 primeiros de cada
--          grupo vão para as quartas (1ºA×4ºB, 2ºA×3ºB, 1ºB×4ºA, 2ºB×3ºA), em ida e volta: quem vence as quartas
--          sobe. Depois semifinal e final, também em ida e volta.
--  • Bots são clubes reais: A com os elencos reais em cartas de destaque que evoluem a cada jogo até o potencial;
--    B com os elencos reais em cartas base; C e D com cartas base geradas (só os nomes dos clubes são reais).
--    Todo técnico começa na Série D (com o elenco e o caixa que já tem).
--  • Copa Online (todas as séries): 1ª fase com as Séries D e C e os 6 piores da B (jogo único, 60 clubes);
--    2ª fase com A e o resto da B (64); 3ª fase (32); oitavas, quartas, semifinal e final em ida e volta.
--    Jogo único e volta empatados (no agregado) vão direto para os pênaltis. O mando do jogo único é do clube de
--    série mais baixa.
--  • Calendário: dois jogos por dia por clube, um de manhã (08:00 a 10:30) e outro à tarde (13:00 a 15:30), em
--    horários que mudam a cada dia; cada série começa com alguns minutos de diferença (A +0, B +5, C +10, D +15).
--    51 turnos (25 dias e meio): 40 de liga e 11 de copa.
--  • Suspensão por competição: vermelho tira do próximo jogo; cada 2 amarelos acumulados também.

-- ─────────────────────────────────────────────────────────────────────────────
-- Esquema
-- ─────────────────────────────────────────────────────────────────────────────

-- Clubes reais que viram bots. div0 é a série em que começam; sim_club liga ao elenco real do catálogo.
create table if not exists public.on_real_clubs(
 key text primary key,
 name text not null,
 short text not null,
 div0 char(1) not null check (div0 in('A','B','C','D')),
 sim_club text,
 city text,
 colors jsonb not null default '{}'::jsonb,
 crest text
);
alter table public.on_real_clubs enable row level security;
revoke all on public.on_real_clubs from anon,authenticated;

alter table public.on_clubs add column if not exists div char(1);
alter table public.on_clubs add column if not exists grp smallint not null default 0;
alter table public.on_clubs add column if not exists real_key text;
alter table public.on_clubs add column if not exists sq text; -- elenco de bot: star (destaque real), base (base real), gen (gerado)

alter table public.on_fixtures add column if not exists div char(1);        -- série (jogos de liga)
alter table public.on_fixtures add column if not exists tphase smallint;    -- fase da tabela que o jogo soma (nulo: mata-mata)
alter table public.on_fixtures add column if not exists grp smallint;       -- grupo
alter table public.on_fixtures add column if not exists tie int;            -- confronto (mata-mata)
alter table public.on_fixtures add column if not exists leg smallint;       -- 1 ida, 2 volta (nulo: jogo único)
alter table public.on_fixtures add column if not exists adv int;            -- vantagem do empate no agregado (liga)
alter table public.on_fixtures add column if not exists slot smallint;      -- turno do calendário (0 = 1º dia, manhã)
create index if not exists on_fixtures_div on public.on_fixtures(season_id,div,round);
create index if not exists on_fixtures_tie on public.on_fixtures(season_id,comp,tie);

alter table public.on_table add column if not exists phase smallint not null default 1;
alter table public.on_table add column if not exists div char(1);
alter table public.on_table add column if not exists grp smallint not null default 0;
do $$ begin
 if exists(select 1 from pg_constraint where conname='on_table_pkey'
  and pg_get_constraintdef(oid)='PRIMARY KEY (season_id, club_id)') then
  alter table public.on_table drop constraint on_table_pkey;
  alter table public.on_table add constraint on_table_pkey primary key(season_id,club_id,phase);
 end if;
end $$;

alter table public.on_players add column if not exists tier text;                       -- 'destaque': carta de destaque
alter table public.on_players add column if not exists susp jsonb not null default '{}'; -- jogos de suspensão por competição {"L":1}
alter table public.on_players add column if not exists ylw jsonb not null default '{}';  -- amarelos acumulados por competição

alter table public.on_history add column if not exists div char(1);
alter table public.on_history add column if not exists result text; -- champion, promoted, relegated, playoff...

alter table public.on_honors alter column comp type text;
alter table public.on_honors drop constraint if exists on_honors_comp_check;
alter table public.on_honors add constraint on_honors_comp_check check (comp in('L','C','LA','LB','LC','LD'));

alter table public.on_seasons add column if not exists series boolean not null default false;

alter table public.on_config add column if not exists kick_am time[] not null
 default array['08:00','09:30','10:30','08:30','10:00','09:00','10:15']::time[];
alter table public.on_config add column if not exists kick_pm time[] not null
 default array['14:00','15:30','13:00','15:00','14:30','13:30','15:15']::time[];
-- prêmio de cada série sobre a tabela de prêmios da liga (prize_league) e pontos de ranking
alter table public.on_config add column if not exists series_mult jsonb not null default '{"A":1,"B":0.6,"C":0.4,"D":0.25}';
-- nível dos elencos gerados por série (bots sem elenco real)
alter table public.on_config add column if not exists series_level jsonb not null default '{"A":74,"B":64,"C":60,"D":56}';
update public.on_config set prize_cup=prize_cup
 ||jsonb_build_object('r2',jsonb_build_object('xp',200,'cash',250000,'energy',5,'diamonds',10))
 ||jsonb_build_object('r3',jsonb_build_object('xp',300,'cash',300000,'energy',5,'diamonds',10))
 ||jsonb_build_object('r16',jsonb_build_object('xp',300,'cash',350000,'energy',5,'diamonds',10))
 where not prize_cup ? 'r16';
update public.on_config set rank_rules=jsonb_set(rank_rules,'{cup}',rank_rules->'cup'||'{"qf":40,"r16":20}')
 where not rank_rules->'cup' ? 'r16';

-- ─────────────────────────────────────────────────────────────────────────────
-- Clubes reais (A e B com elenco do catálogo; C da Série C 2027; D: nomes reais, elenco gerado)
-- ─────────────────────────────────────────────────────────────────────────────
insert into public.on_real_clubs(key,name,short,div0,sim_club,city,colors)
select x.key,x.name,x.short,x.div0,x.sim,x.city,jsonb_build_object('a',x.ca,'b',x.cb,'pattern',x.pat,'shape','shield','stadium','Estádio '||x.name)
from(values
 ('athletico-pr','Athletico-PR','CAP','A','athletico-pr','Curitiba-PR','#C8102E','#111111','stripes'),
 ('atletico-mg','Atlético-MG','CAM','A','atletico-mg','Belo Horizonte-MG','#111111','#FFFFFF','stripes'),
 ('bahia','Bahia','BAH','A','bahia','Salvador-BA','#0057B8','#E31B23','halves'),
 ('botafogo','Botafogo','BOT','A','botafogo','Rio de Janeiro-RJ','#111111','#FFFFFF','stripes'),
 ('chapecoense','Chapecoense','CHA','A','chapecoense','Chapecó-SC','#00A859','#FFFFFF','plain'),
 ('corinthians','Corinthians','COR','A','corinthians','São Paulo-SP','#FFFFFF','#111111','plain'),
 ('coritiba','Coritiba','CFC','A','coritiba','Curitiba-PR','#00693E','#FFFFFF','hoops'),
 ('cruzeiro','Cruzeiro','CRU','A','cruzeiro','Belo Horizonte-MG','#0033A0','#FFFFFF','plain'),
 ('flamengo','Flamengo','FLA','A','flamengo','Rio de Janeiro-RJ','#C8102E','#111111','hoops'),
 ('fluminense','Fluminense','FLU','A','fluminense','Rio de Janeiro-RJ','#8B1E3F','#0A7A3D','stripes'),
 ('gremio','Grêmio','GRE','A','gremio','Porto Alegre-RS','#0099D8','#111111','stripes'),
 ('internacional','Internacional','INT','A','internacional','Porto Alegre-RS','#E4002B','#FFFFFF','plain'),
 ('mirassol','Mirassol','MIR','A','mirassol','Mirassol-SP','#FFD100','#00A859','plain'),
 ('palmeiras','Palmeiras','PAL','A','palmeiras','São Paulo-SP','#006437','#FFFFFF','plain'),
 ('bragantino','Red Bull Bragantino','RBB','A','bragantino','Bragança Paulista-SP','#FFFFFF','#C8102E','plain'),
 ('remo','Remo','REM','A','remo','Belém-PA','#001F5B','#7FB6E8','plain'),
 ('santos','Santos','SAN','A','santos','Santos-SP','#FFFFFF','#111111','plain'),
 ('sao-paulo','São Paulo','SAO','A','sao-paulo','São Paulo-SP','#FFFFFF','#E4002B','sash'),
 ('vasco','Vasco da Gama','VAS','A','vasco','Rio de Janeiro-RJ','#111111','#FFFFFF','sash'),
 ('vitoria','Vitória','VIT','A','vitoria','Salvador-BA','#D00027','#111111','stripes'),
 ('america-mg','América-MG','AME','B','america-mg','Belo Horizonte-MG','#00843D','#111111','stripes'),
 ('athletic-mg','Athletic','ATH','B','athletic-mg','São João del-Rei-MG','#111111','#FFFFFF','plain'),
 ('atletico-go','Atlético-GO','ACG','B','atletico-go','Goiânia-GO','#C8102E','#111111','stripes'),
 ('avai','Avaí','AVA','B','avai','Florianópolis-SC','#0047AB','#FFFFFF','stripes'),
 ('botafogo-sp','Botafogo-SP','BSP','B','botafogo-sp','Ribeirão Preto-SP','#E30613','#111111','stripes'),
 ('ceara','Ceará','CEA','B','ceara','Fortaleza-CE','#111111','#FFFFFF','stripes'),
 ('crb','CRB','CRB','B','crb','Maceió-AL','#E30613','#FFFFFF','stripes'),
 ('criciuma','Criciúma','CRI','B','criciuma','Criciúma-SC','#FFD700','#111111','stripes'),
 ('cuiaba','Cuiabá','CUI','B','cuiaba','Cuiabá-MT','#006B3F','#FFD700','plain'),
 ('fortaleza','Fortaleza','FOR','B','fortaleza','Fortaleza-CE','#003C8F','#D81E05','hoops'),
 ('goias','Goiás','GOI','B','goias','Goiânia-GO','#00843D','#FFFFFF','plain'),
 ('juventude','Juventude','JUV','B','juventude','Caxias do Sul-RS','#00A859','#FFFFFF','stripes'),
 ('londrina','Londrina','LON','B','londrina','Londrina-PR','#00A3E0','#FFFFFF','plain'),
 ('nautico','Náutico','NAU','B','nautico','Recife-PE','#C8102E','#FFFFFF','stripes'),
 ('novorizontino','Novorizontino','NOV','B','novorizontino','Novo Horizonte-SP','#FFD700','#111111','plain'),
 ('operario-pr','Operário-PR','OPE','B','operario-pr','Ponta Grossa-PR','#111111','#FFFFFF','stripes'),
 ('ponte-preta','Ponte Preta','PON','B','ponte-preta','Campinas-SP','#111111','#FFFFFF','sash'),
 ('sao-bernardo','São Bernardo','SBE','B','sao-bernardo','São Bernardo do Campo-SP','#FFD700','#111111','plain'),
 ('sport','Sport','SPT','B','sport','Recife-PE','#E30613','#111111','hoops'),
 ('vila-nova','Vila Nova','VNO','B','vila-nova','Goiânia-GO','#C8102E','#FFFFFF','plain'),
 ('maringa','Maringá','MGA','C',null,'Maringá-PR','#1E3A8A','#FFFFFF','plain'),
 ('ferroviaria','Ferroviária','AFE','C',null,'Araraquara-SP','#7A1F2B','#FFFFFF','plain'),
 ('inter-limeira','Inter de Limeira','INL','C',null,'Limeira-SP','#111111','#FFFFFF','stripes'),
 ('santa-cruz','Santa Cruz','STC','C',null,'Recife-PE','#E30613','#111111','hoops'),
 ('amazonas','Amazonas','AMZ','C',null,'Manaus-AM','#FFD100','#111111','stripes'),
 ('anapolis','Anápolis','ANP','C',null,'Anápolis-GO','#E30613','#FFFFFF','plain'),
 ('barra','Barra','BAR','C',null,'Balneário Camboriú-SC','#1E40AF','#FFFFFF','plain'),
 ('botafogo-pb','Botafogo-PB','BPB','C',null,'João Pessoa-PB','#111111','#FFFFFF','stripes'),
 ('brusque','Brusque','BRU','C',null,'Brusque-SC','#E2B007','#E30613','stripes'),
 ('caxias','Caxias','CAX','C',null,'Caxias do Sul-RS','#8B0000','#FFFFFF','plain'),
 ('figueirense','Figueirense','FIG','C',null,'Florianópolis-SC','#111111','#FFFFFF','stripes'),
 ('floresta','Floresta','FLO','C',null,'Fortaleza-CE','#0F7A3A','#FFFFFF','plain'),
 ('guarani','Guarani','GUA','C',null,'Campinas-SP','#0F7A3A','#FFFFFF','plain'),
 ('ituano','Ituano','ITU','C',null,'Itu-SP','#E30613','#111111','stripes'),
 ('maranhao','Maranhão','MAC','C',null,'São Luís-MA','#1E40AF','#E30613','stripes'),
 ('paysandu','Paysandu','PAY','C',null,'Belém-PA','#5BA4E6','#FFFFFF','stripes'),
 ('volta-redonda','Volta Redonda','VOL','C',null,'Volta Redonda-RJ','#FFD100','#111111','plain'),
 ('ypiranga-rs','Ypiranga','YPI','C',null,'Erechim-RS','#F2C200','#0F7A3A','stripes'),
 ('uberlandia','Uberlândia','UEC','C',null,'Uberlândia-MG','#00843D','#FFFFFF','plain'),
 ('asa','ASA','ASA','C',null,'Arapiraca-AL','#E30613','#FFFFFF','plain'),
 ('abc','ABC','ABC','C',null,'Natal-RN','#111111','#FFFFFF','plain'),
 ('gama','Gama','GAM','C',null,'Gama-DF','#0F7A3A','#FFFFFF','plain'),
 ('goiatuba','Goiatuba','GTB','C',null,'Goiatuba-GO','#1E40AF','#FFFFFF','plain'),
 ('nacional-am','Nacional-AM','NAC','C',null,'Manaus-AM','#1E40AF','#FFFFFF','stripes'),
 ('itabaiana','Itabaiana','ITB','D',null,'Itabaiana-SE','#1E40AF','#FFFFFF','plain'),
 ('confianca','Confiança','CON','D',null,'Aracaju-SE','#1E40AF','#FFFFFF','stripes'),
 ('sergipe','Sergipe','SER','D',null,'Aracaju-SE','#E30613','#FFFFFF','plain'),
 ('treze','Treze','TRE','D',null,'Campina Grande-PB','#111111','#FFFFFF','stripes'),
 ('campinense','Campinense','CPN','D',null,'Campina Grande-PB','#E30613','#111111','stripes'),
 ('america-rn','América-RN','ARN','D',null,'Natal-RN','#E30613','#FFFFFF','plain'),
 ('ferroviario','Ferroviário','FRR','D',null,'Fortaleza-CE','#111111','#E30613','hoops'),
 ('central','Central','CEN','D',null,'Caruaru-PE','#111111','#FFFFFF','stripes'),
 ('retro','Retrô','RET','D',null,'Camaragibe-PE','#F97316','#111111','plain'),
 ('sampaio-correa','Sampaio Corrêa','SAM','D',null,'São Luís-MA','#FFD100','#0F7A3A','hoops'),
 ('moto-club','Moto Club','MOT','D',null,'São Luís-MA','#E30613','#111111','stripes'),
 ('fluminense-pi','Fluminense-PI','FPI','D',null,'Teresina-PI','#8B1E3F','#0A7A3D','stripes'),
 ('altos','Altos','ALT','D',null,'Altos-PI','#FFD100','#0F7A3A','plain'),
 ('juazeirense','Juazeirense','JUA','D',null,'Juazeiro-BA','#E30613','#FFFFFF','plain'),
 ('jacuipense','Jacuipense','JAC','D',null,'Riachão do Jacuípe-BA','#E30613','#FFD100','plain'),
 ('csa','CSA','CSA','D',null,'Maceió-AL','#1E40AF','#FFFFFF','stripes'),
 ('ceilandia','Ceilândia','CEI','D',null,'Ceilândia-DF','#111111','#E30613','plain'),
 ('brasiliense','Brasiliense','BSE','D',null,'Taguatinga-DF','#FFD100','#0F7A3A','plain'),
 ('aparecidense','Aparecidense','APA','D',null,'Aparecida de Goiânia-GO','#1E40AF','#FFFFFF','plain'),
 ('portuguesa','Portuguesa','POR','D',null,'São Paulo-SP','#E30613','#0F7A3A','halves'),
 ('xv-piracicaba','XV de Piracicaba','XVP','D',null,'Piracicaba-SP','#111111','#FFFFFF','stripes'),
 ('santo-andre','Santo André','SAD','D',null,'Santo André-SP','#1E40AF','#FFFFFF','plain'),
 ('joinville','Joinville','JEC','D',null,'Joinville-SC','#E30613','#111111','stripes'),
 ('cascavel','Cascavel','FCC','D',null,'Cascavel-PR','#FFD100','#111111','plain'),
 ('sao-jose-rs','São José-RS','SJO','D',null,'Porto Alegre-RS','#1E40AF','#FFFFFF','plain'),
 ('tombense','Tombense','TOM','D',null,'Tombos-MG','#E30613','#FFFFFF','plain'),
 ('manaus','Manaus','MAN','D',null,'Manaus-AM','#FFD100','#111111','stripes'),
 ('aguia-maraba','Águia de Marabá','AGU','D',null,'Marabá-PA','#1E40AF','#E30613','plain'),
 ('rio-branco-ac','Rio Branco-AC','RBR','D',null,'Rio Branco-AC','#E30613','#FFFFFF','stripes'),
 ('tuna-luso','Tuna Luso','TUN','D',null,'Belém-PA','#0F7A3A','#E30613','plain')
) x(key,name,short,div0,sim,city,ca,cb,pat)
on conflict(key) do update set name=excluded.name,short=excluded.short,div0=excluded.div0,sim_club=excluded.sim_club,city=excluded.city,
 colors=excluded.colors||coalesce(public.on_real_clubs.colors-'a'-'b'-'pattern'-'shape'-'stadium','{}'::jsonb);

-- ─────────────────────────────────────────────────────────────────────────────
-- Constantes das séries
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_div_name(p_div text) returns text
language sql immutable as $$
 select case p_div when 'A' then 'Liga Online A' when 'B' then 'Liga Online B' when 'C' then 'Liga Online C' when 'D' then 'Liga Online D' else 'Liga Online' end
$$;
create or replace function public.on_div_size(p_div text) returns int
language sql immutable as $$ select case p_div when 'A' then 20 when 'B' then 20 when 'C' then 24 when 'D' then 30 end $$;
-- rodadas de cada série (com mata-mata) e da copa
create or replace function public.on_div_rounds(p_div text) returns int
language sql immutable as $$ select case p_div when 'A' then 38 when 'B' then 40 when 'C' then 31 when 'D' then 36 when 'K' then 11 end $$;
create or replace function public.on_div_offset(p_div text) returns interval
language sql immutable as $$ select make_interval(mins=>case p_div when 'B' then 5 when 'C' then 10 when 'D' then 15 else 0 end) $$;

-- Turno do calendário (0 a 50) de cada rodada. Turnos de copa: 3, 8, 13, 18, 22, 27, 31, 36, 40, 45 e 49.
-- Os outros 40 são de liga: A e B usam um por rodada; C e D se espalham por eles (há descanso entre rodadas).
create or replace function public.on_round_slot(p_div text,p_round int) returns int
language sql immutable as $$
 with cup as(select array[3,8,13,18,22,27,31,36,40,45,49] s),
 lg as(select array(select g from generate_series(0,50) g,cup where g<>all(cup.s) order by g) s)
 select case when p_div='K' then (select s[p_round] from cup)
  else (select s[1+case p_div when 'C' then round((p_round-1)*39.0/30) when 'D' then round((p_round-1)*39.0/35) else p_round-1 end] from lg) end
$$;

-- Horário real de um turno: dia = início + turno/2; manhã nos pares, tarde nos ímpares; horários mudam a cada dia.
create or replace function public.on_slot_kick(p_season smallint,p_slot int,p_div text) returns timestamptz
language sql stable security definer set search_path=public as $$
 select ((s.starts_on+(p_slot/2))
  +(case when p_slot%2=0 then c.kick_am[1+(p_slot/2)%cardinality(c.kick_am)] else c.kick_pm[1+(p_slot/2)%cardinality(c.kick_pm)] end)
  +public.on_div_offset(p_div))::timestamp at time zone s.tz
 from public.on_seasons s,public.on_config c where s.id=p_season
$$;

-- Rodízio (método do círculo): rodadas de 1 a n-1 (n par; com n ímpar entra uma folga). p_double: returno.
create or replace function public.on_rr(p_ids int[],p_double boolean) returns table(rnd int,home int,away int)
language plpgsql immutable as $$
declare a int[]:=p_ids;m int;r int;i int;x int;y int;h int;w int;
begin
 if cardinality(a)%2=1 then a:=a||0;end if;
 m:=cardinality(a);
 for r in 0..m-2 loop
  for i in 0..m/2-1 loop
   x:=case when i=0 then m-1 else (r+i)%(m-1) end;
   y:=case when i=0 then r else (r-i+m-1)%(m-1) end;
   if (r+i)%2=0 then h:=a[x+1];w:=a[y+1];else h:=a[y+1];w:=a[x+1];end if;
   continue when h=0 or w=0;
   rnd:=r+1;home:=h;away:=w;return next;
   if p_double then rnd:=r+m;home:=w;away:=h;return next;end if;
  end loop;
 end loop;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Elencos dos bots
-- ─────────────────────────────────────────────────────────────────────────────

-- Cartas base geradas (sem consultar o catálogo): 22 jogadores perto do nível da série.
create or replace function public.on_gen_fake(p_club int,p_seed text,p_base int,p_contract_end int) returns void
language sql security definer set search_path=public as $$
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,number,wage,contract_end,agg,disc)
 select p_club,public.cw_regen_name('BRA',x.s),x.pos,a.age,a.lvl,
  least(92,a.lvl+floor(public.sim_hash01(x.s||':pot')*case when a.age<23 then 6 else 2 end)::int),
  a.lvl,x.n,public.on_wage(a.lvl),p_contract_end,
  35+floor(public.sim_hash01(x.s||':agg')*40)::int,40+floor(public.sim_hash01(x.s||':disc')*45)::int
 from(select u.n::int n,u.pos,p_seed||':f'||u.n s
  from unnest(array['GOL','LD','ZAG','ZAG','LE','VOL','MC','MEI','PD','PE','ATA','GOL','LD','ZAG','LE','VOL','MC','MEI','PD','ATA','ZAG','GOL'])
   with ordinality u(pos,n)) x
 cross join lateral(select 18+floor(public.sim_hash01(x.s||':age')*16)::int age,
  (p_base-4+floor(public.sim_hash01(x.s||':lvl')*9))::int lvl) a
$$;

-- Monta (ou refaz) o elenco de um clube bot conforme a série: star = elenco real em cartas de destaque (evoluem até o
-- potencial), base = elenco real em cartas base, gen = cartas base geradas. Sem jogadores reais livres, completa com geradas.
create or replace function public.on_bot_squad(p_club int,p_seed text) returns void
language plpgsql security definer set search_path=public as $$
declare k public.on_clubs;rc public.on_real_clubs;v_lv int;v_end int;n int:=0;r record;v_id text;
begin
 select * into k from public.on_clubs where id=p_club for update;
 if k.user_id is not null then return;end if;
 select * into rc from public.on_real_clubs where key=k.real_key;
 v_lv:=coalesce((select (series_level->>k.div)::int from public.on_config),60);
 v_end:=k.season_id+5;
 delete from public.on_lots where player_id in(select id from public.on_players where club_id=p_club) and status<>'open';
 update public.on_lots set status='cancelled',settled_at=now() where player_id in(select id from public.on_players where club_id=p_club) and status='open';
 delete from public.on_players where club_id=p_club and id not in(select player_id from public.on_lots);
 update public.on_players set club_id=null where club_id=p_club;
 delete from public.on_lineups where club_id=p_club;
 k.sq:=case when rc.sim_club is not null and k.div in('A','B') then case when k.div='A' then 'star' else 'base' end else 'gen' end;
 update public.on_clubs set sq=k.sq where id=p_club;
 if k.sq in('star','base') then
  for r in select q.id from(
    select p.id,p.position pos,b.rating,row_number() over(partition by p.position='GOL' order by b.rating desc,p.id) rn
    from public.sim_players p join public.sim_player_base b on b.player_id=p.id
    where p.club_id=rc.sim_club and p.career_id is null and p.active
     and not exists(select 1 from public.on_players o where o.src=p.id)) q
   where (q.pos='GOL' and q.rn<=3) or (q.pos<>'GOL' and q.rn<=20)
   order by q.rating desc loop
   n:=n+1;
   v_id:=public.on_real_insert(r.id,p_club,n,v_end);
  end loop;
  if k.sq='star' then
   -- destaque: o potencial fica pelo menos 5 acima da nota (a carta evolui jogando)
   update public.on_players set tier='destaque',pot=least(95,greatest(pot,level+5)) where club_id=p_club;
  end if;
 end if;
 if n<18 then
  perform public.on_gen_fake(p_club,p_seed||':'||p_club,v_lv,v_end);
  if n>0 then -- completa: tira as geradas que sobram nas posições já cheias
   delete from public.on_players p where p.club_id=p_club and p.src is null
    and p.id in(select x.id from public.on_players x where x.club_id=p_club and x.src is null order by x.number desc limit greatest(0,n+22-23));
  end if;
 end if;
 update public.on_players p set number=x.rn from(select id,row_number() over(order by (pos='GOL') desc,ovr desc,id) rn from public.on_players where club_id=p_club) x
  where p.id=x.id;
 perform public.on_auto_lineup(p_club);
end $$;

-- Carta de destaque de bot da Série A evolui jogando: +0,5 na nota por jogo com 45 minutos ou mais, até o potencial.
create or replace function public.on_star_grow(p_fixture bigint) returns void
language sql security definer set search_path=public as $$
 update public.on_players p set
  g=case when sp.line in('GK','DEF') then array[p.g[1]+1,p.g[2],p.g[3],p.g[4]]
   when sp.line='MID' then array[p.g[1],p.g[2]+1,p.g[3],p.g[4]] else array[p.g[1],p.g[2],p.g[3]+1,p.g[4]] end::smallint[],
  ovr=public.on_ovr(p.level,p.pot,case when sp.line in('GK','DEF') then array[p.g[1]+1,p.g[2],p.g[3],p.g[4]]
   when sp.line='MID' then array[p.g[1],p.g[2]+1,p.g[3],p.g[4]] else array[p.g[1],p.g[2],p.g[3]+1,p.g[4]] end::smallint[])
 from public.on_match_players mp,public.sim_positions sp,public.on_clubs k
 where mp.fixture_id=p_fixture and mp.player_id=p.id and mp.minutes>=45 and sp.code=p.pos
  and k.id=p.club_id and k.user_id is null and p.tier='destaque' and p.ovr<p.pot
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Classificação
-- ─────────────────────────────────────────────────────────────────────────────

-- Posição dentro de uma tabela (série, fase, grupo). Desempate: pontos, vitórias, saldo, gols marcados, nome.
create or replace function public.on_table_rank(p_season smallint,p_div text,p_phase int,p_grp int)
returns table(club_id int,pos int,pts int,w int,gd int)
language sql stable security definer set search_path=public as $$
 select t.club_id,row_number() over(order by t.pts desc,t.w desc,t.gf-t.ga desc,t.gf desc,k.name)::int,t.pts::int,t.w::int,(t.gf-t.ga)::int
 from public.on_table t join public.on_clubs k on k.id=t.club_id
 where t.season_id=p_season and t.div is not distinct from p_div and t.phase=p_phase and t.grp=p_grp
$$;

-- Posição de cada clube na primeira fase da sua série (e grupo). Temporada antiga (liga única): a tabela toda.
create or replace function public.on_rank(p_season smallint) returns table(club_id int,pos int)
language sql stable security definer set search_path=public as $$
 select t.club_id,row_number() over(partition by t.div,t.grp order by t.pts desc,t.w desc,t.gf-t.ga desc,t.gf desc,k.name)::int
 from public.on_table t join public.on_clubs k on k.id=t.club_id where t.season_id=p_season and t.phase=1
$$;

-- Vencedor de um confronto (jogo único ou ida e volta), nulo enquanto não terminou.
-- Empate no agregado: copa decide nos pênaltis da volta; liga dá a vaga a quem tem a vantagem (adv).
create or replace function public.on_tie_winner(p_season smallint,p_comp text,p_tie int) returns int
language plpgsql stable security definer set search_path=public as $$
declare a int;b int;ga int:=0;gb int:=0;f record;last record;n int:=0;
begin
 for f in select * from public.on_fixtures where season_id=p_season and comp=p_comp and tie=p_tie order by coalesce(leg,1) loop
  if f.status<>'done' then return null;end if;
  n:=n+1;
  if a is null then a:=f.home;b:=f.away;end if;
  ga:=ga+case when f.home=a then f.hg else f.ag end;
  gb:=gb+case when f.home=b then f.hg else f.ag end;
  last:=f;
 end loop;
 if n=0 then return null;end if;
 if ga>gb then return a;end if;
 if gb>ga then return b;end if;
 if p_comp='C' and last.pens is not null then
  return case when (last.pens->>0)::int>(last.pens->>1)::int then last.home else last.away end;
 end if;
 return coalesce(last.adv,last.home);
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Calendário
-- ─────────────────────────────────────────────────────────────────────────────

-- Jogo (ou confronto de ida e volta) nas rodadas p_round (e p_round+1 na volta).
create or replace function public.on_fx_add(p_season smallint,p_comp text,p_div text,p_round int,p_home int,p_away int,
 p_tphase int,p_grp int,p_tie int,p_legs int,p_stage text,p_adv int) returns void
language plpgsql security definer set search_path=public as $$
declare v_slot int;v_kdiv text;i int;
begin
 for i in 1..p_legs loop
  v_slot:=public.on_round_slot(case when p_comp='C' then 'K' else p_div end,p_round+i-1);
  v_kdiv:=case when p_comp='C' then (select div from public.on_clubs where id=case when i=1 then p_home else p_away end) else p_div end;
  insert into public.on_fixtures(season_id,comp,div,round,stage,home,away,kickoff,tphase,grp,tie,leg,adv,slot)
  values(p_season,p_comp,case when p_comp='L' then p_div end,p_round+i-1,p_stage,
   case when i=1 then p_home else p_away end,case when i=1 then p_away else p_home end,
   public.on_slot_kick(p_season,v_slot,v_kdiv),p_tphase,nullif(p_grp,0),p_tie,case when p_legs=2 then i end,p_adv,v_slot);
 end loop;
end $$;

-- Primeira fase de cada série: A e B turno e returno; C turno único; D dois grupos de 15 em turno e returno.
create or replace function public.on_series_fixtures(p_season smallint) returns void
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;d text;g int;ids int[];r record;
begin
 select * into s from public.on_seasons where id=p_season;
 foreach d in array array['A','B','C','D'] loop
  for g in select distinct k.grp from public.on_clubs k where k.season_id=p_season and k.div=d order by 1 loop
   ids:=array(select k.id from public.on_clubs k where k.season_id=p_season and k.div=d and k.grp=g order by public.sim_hash01(s.seed||':rr:'||k.id));
   for r in select * from public.on_rr(ids,d<>'C') loop
    perform public.on_fx_add(p_season,'L',d,r.rnd,r.home,r.away,1,g,null,1,null,null);
   end loop;
  end loop;
 end loop;
 insert into public.on_table(season_id,club_id,phase,div,grp)
 select p_season,k.id,1,k.div,k.grp from public.on_clubs k where k.season_id=p_season and k.div is not null
 on conflict do nothing;
end $$;

-- Grupos da D: 30 clubes em 2 grupos de 15, alternando pela força (técnicos e bots misturados).
create or replace function public.on_series_groups(p_season smallint) returns void
language sql security definer set search_path=public as $$
 update public.on_clubs k set grp=case when x.rn%4 in(1,0) then 1 else 2 end
 from(select id,row_number() over(order by public.on_strength(id) desc,id) rn from public.on_clubs where season_id=p_season and div='D') x
 where k.id=x.id;
 update public.on_clubs set grp=0 where season_id=p_season and div<>'D';
$$;

-- Copa: sorteio de uma fase. Jogo único com mando do clube de série mais baixa; oitavas em diante, ida e volta.
create or replace function public.on_cup_draw(p_season smallint,p_round int,p_teams int[]) returns int
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;t int[];i int;h int;a int;n int;
 v_stage text:=(array['f1','f2','f3','r16','r16','qf','qf','sf','sf','final','final'])[p_round];
begin
 select * into s from public.on_seasons where id=p_season;
 if exists(select 1 from public.on_fixtures where season_id=p_season and comp='C' and round=p_round) then return 0;end if;
 t:=array(select x from unnest(p_teams) x order by public.sim_hash01(s.seed||':cup:'||p_round||':'||x));
 n:=cardinality(t)/2;
 for i in 1..n loop
  h:=t[2*i-1];a:=t[2*i];
  if p_round<=3 and (select div from public.on_clubs where id=a)>(select div from public.on_clubs where id=h) then h:=t[2*i];a:=t[2*i-1];end if;
  perform public.on_fx_add(p_season,'C',null,p_round,h,a,null,0,p_round*100+i,case when p_round<=3 then 1 else 2 end,v_stage,null);
 end loop;
 return n;
end $$;

-- Clubes da 1ª fase da copa: Séries D e C e os 6 piores da B (p_b_weak, em ordem do mais fraco).
create or replace function public.on_cup_start(p_season smallint,p_b_order int[]) returns int
language sql security definer set search_path=public as $$
 select public.on_cup_draw(p_season,1,
  array(select id from public.on_clubs where season_id=p_season and div in('C','D'))||p_b_order[1:6])
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Fases seguintes (gancho de fim de partida)
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function public.on_series_hook(p_fixture bigint) returns void
language plpgsql security definer set search_path=public as $$
declare f public.on_fixtures;s public.on_seasons;r1 int[];r2 int[];w int[];i int;x int;y int;k int;nx int;
begin
 select * into f from public.on_fixtures where id=p_fixture;
 select * into s from public.on_seasons where id=f.season_id for update;
 if not coalesce(s.series,false) or s.status<>'live' then return;end if;

 if f.comp='L' then
  -- B: fim dos pontos corridos → playoffs 3º×6º e 4º×5º (volta na casa do melhor, que tem a vantagem do empate)
  if f.div='B' and f.tphase=1 and not exists(select 1 from public.on_fixtures where season_id=s.id and div='B' and tphase=1 and status<>'done')
   and not exists(select 1 from public.on_fixtures where season_id=s.id and div='B' and tie is not null) then
   r1:=array(select club_id from public.on_table_rank(s.id,'B',1,0) order by pos);
   perform public.on_fx_add(s.id,'L','B',39,r1[6],r1[3],null,0,201,2,'po',r1[3]);
   perform public.on_fx_add(s.id,'L','B',39,r1[5],r1[4],null,0,202,2,'po',r1[4]);
  end if;
  -- C: fim do turno único → quadrangulares (1º,4º,5º,8º e 2º,3º,6º,7º) em ida e volta
  if f.div='C' and f.tphase=1 and not exists(select 1 from public.on_fixtures where season_id=s.id and div='C' and tphase=1 and status<>'done')
   and not exists(select 1 from public.on_fixtures where season_id=s.id and div='C' and tphase=2) then
   r1:=array(select club_id from public.on_table_rank(s.id,'C',1,0) order by pos);
   for k in 1..2 loop
    w:=case k when 1 then array[r1[1],r1[4],r1[5],r1[8]] else array[r1[2],r1[3],r1[6],r1[7]] end;
    insert into public.on_table(season_id,club_id,phase,div,grp) select s.id,u,2,'C',k from unnest(w) u on conflict do nothing;
    for x,y,i in select q.home,q.away,q.rnd from public.on_rr(w,true) q loop
     perform public.on_fx_add(s.id,'L','C',23+i,x,y,2,k,null,1,'quad',null);
    end loop;
   end loop;
  end if;
  -- C: fim dos quadrangulares → final entre os líderes (vantagem: melhor campanha na primeira fase)
  if f.div='C' and f.tphase=2 and not exists(select 1 from public.on_fixtures where season_id=s.id and div='C' and tphase=2 and status<>'done')
   and not exists(select 1 from public.on_fixtures where season_id=s.id and div='C' and stage='final') then
   x:=(select club_id from public.on_table_rank(s.id,'C',2,1) where pos=1);
   y:=(select club_id from public.on_table_rank(s.id,'C',2,2) where pos=1);
   if (select pos from public.on_table_rank(s.id,'C',1,0) where club_id=x)>(select pos from public.on_table_rank(s.id,'C',1,0) where club_id=y) then
    i:=x;x:=y;y:=i;
   end if;
   perform public.on_fx_add(s.id,'L','C',30,y,x,null,0,301,2,'final',x);
  end if;
  -- D: fim dos grupos → quartas (1ºA×4ºB, 2ºA×3ºB, 1ºB×4ºA, 2ºB×3ºA); quem vence sobe
  if f.div='D' and f.tphase=1 and not exists(select 1 from public.on_fixtures where season_id=s.id and div='D' and tphase=1 and status<>'done')
   and not exists(select 1 from public.on_fixtures where season_id=s.id and div='D' and tie is not null) then
   r1:=array(select club_id from public.on_table_rank(s.id,'D',1,1) order by pos);
   r2:=array(select club_id from public.on_table_rank(s.id,'D',1,2) order by pos);
   perform public.on_fx_add(s.id,'L','D',31,r2[4],r1[1],null,0,401,2,'qf',r1[1]);
   perform public.on_fx_add(s.id,'L','D',31,r2[3],r1[2],null,0,402,2,'qf',r1[2]);
   perform public.on_fx_add(s.id,'L','D',31,r1[4],r2[1],null,0,403,2,'qf',r2[1]);
   perform public.on_fx_add(s.id,'L','D',31,r1[3],r2[2],null,0,404,2,'qf',r2[2]);
  end if;
  -- D: semifinal (vencedor 1×4 contra 2×3... cruzado) e final
  if f.div='D' and f.tie is not null then
   if f.stage='qf' and not exists(select 1 from public.on_fixtures where season_id=s.id and div='D' and stage='sf') then
    w:=array(select public.on_tie_winner(s.id,'L',t) from generate_series(401,404) t);
    if array_position(w,null) is null then
     perform public.on_series_ko(s.id,'D',33,w[1],w[4],405,'sf');
     perform public.on_series_ko(s.id,'D',33,w[2],w[3],406,'sf');
    end if;
   elsif f.stage='sf' and not exists(select 1 from public.on_fixtures where season_id=s.id and div='D' and stage='final') then
    w:=array(select public.on_tie_winner(s.id,'L',t) from generate_series(405,406) t);
    if array_position(w,null) is null then perform public.on_series_ko(s.id,'D',35,w[1],w[2],407,'final');end if;
   end if;
  end if;
 elsif f.comp='C' then
  -- copa: fase terminada → sorteio da próxima
  nx:=f.round+1;
  if f.round<=3 or f.leg=2 then
   if nx<=11 and not exists(select 1 from public.on_fixtures where season_id=s.id and comp='C' and round=nx)
    and not exists(select 1 from public.on_fixtures where season_id=s.id and comp='C' and round in(f.round,f.round-1) and stage=f.stage and status<>'done') then
    w:=array(select public.on_tie_winner(s.id,'C',t) from(select distinct tie from public.on_fixtures where season_id=s.id and comp='C' and stage=f.stage) q(t));
    if f.round=1 then
     w:=w||array(select id from public.on_clubs where season_id=s.id and div in('A','B')
      and id not in(select home from public.on_fixtures where season_id=s.id and comp='C' and round=1
       union select away from public.on_fixtures where season_id=s.id and comp='C' and round=1));
    end if;
    perform public.on_cup_draw(s.id,nx,w);
   end if;
  end if;
  if f.stage='final' and f.leg=2 then perform public.on_award_cup(s.id);end if;
 end if;

 if not exists(select 1 from public.on_fixtures x where x.season_id=s.id and x.status<>'done') then
  perform public.on_series_end(s.id,greatest(now(),f.kickoff+interval '13 minutes'));
 end if;
end $$;

-- Mata-mata de liga entre a e b (confrontos: B 201-202, C 301, D 401-407): vantagem e volta em casa para quem fez a melhor campanha nos grupos.
create or replace function public.on_series_ko(p_season smallint,p_div text,p_round int,a int,b int,p_tie int,p_stage text) returns void
language plpgsql security definer set search_path=public as $$
declare ra record;rb record;
begin
 select pos,pts,w,gd into ra from(select * from public.on_table_rank(p_season,p_div,1,1) union all select * from public.on_table_rank(p_season,p_div,1,2)) q where q.club_id=a;
 select pos,pts,w,gd into rb from(select * from public.on_table_rank(p_season,p_div,1,1) union all select * from public.on_table_rank(p_season,p_div,1,2)) q where q.club_id=b;
 if (ra.pos,-ra.pts,-ra.w,-ra.gd)>(rb.pos,-rb.pts,-rb.w,-rb.gd) then
  perform public.on_fx_add(p_season,'L',p_div,p_round,a,b,null,0,p_tie,2,p_stage,b);
 else
  perform public.on_fx_add(p_season,'L',p_div,p_round,b,a,null,0,p_tie,2,p_stage,a);
 end if;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Fim da temporada das séries: história, prêmios, acesso e rebaixamento, nova temporada
-- ─────────────────────────────────────────────────────────────────────────────

-- Resultado de cada clube na série: posição final na série (1 = campeão) e o que aconteceu.
create or replace function public.on_series_result(p_season smallint)
returns table(club_id int,div text,pos int,result text)
language plpgsql stable security definer set search_path=public as $$
declare r record;w int;
begin
 -- A: pontos corridos
 for r in select * from public.on_table_rank(p_season,'A',1,0) loop
  club_id:=r.club_id;div:='A';pos:=r.pos;result:=case when r.pos=1 then 'champion' when r.pos>=17 then 'relegated' end;return next;
 end loop;
 -- B: 1º e 2º sobem, vencedores dos playoffs também; 4 últimos caem
 for r in select q.*,public.on_tie_winner(p_season,'L',t.tie) po from public.on_table_rank(p_season,'B',1,0) q
  left join lateral(select f.tie from public.on_fixtures f where f.season_id=p_season and f.div='B' and f.tie is not null and q.club_id in(f.home,f.away) limit 1) t on true loop
  club_id:=r.club_id;div:='B';pos:=r.pos;
  result:=case when r.pos=1 then 'champion' when r.pos=2 then 'promoted' when r.po=r.club_id then 'promoted' when r.pos between 3 and 6 then 'playoff'
   when r.pos>=17 then 'relegated' end;
  return next;
 end loop;
 -- C: campeão e vice da final, demais dos quadrangulares conforme o grupo, 4 últimos da primeira fase caem
 w:=public.on_tie_winner(p_season,'L',(select f.tie from public.on_fixtures f where f.season_id=p_season and f.div='C' and f.stage='final' limit 1));
 for r in select q.*,(select x.pos from public.on_table t2 join lateral public.on_table_rank(p_season,'C',2,t2.grp) x on x.club_id=t2.club_id
   where t2.season_id=p_season and t2.club_id=q.club_id and t2.phase=2) qpos
  from public.on_table_rank(p_season,'C',1,0) q loop
  club_id:=r.club_id;div:='C';
  pos:=case when r.club_id=w then 1 when r.qpos=1 then 2 when r.qpos is not null then 2+r.qpos*2-2+(r.pos>4)::int else r.pos end;
  result:=case when r.club_id=w then 'champion' when r.qpos<=2 then 'promoted' when r.qpos is not null then 'quad' when r.pos>=21 then 'relegated' end;
  return next;
 end loop;
 -- D: quem vence as quartas sobe; campeão da final
 w:=public.on_tie_winner(p_season,'L',407);
 for r in select q.*,
   (select max(case f.stage when 'final' then 4 when 'sf' then 3 when 'qf' then 2 end) from public.on_fixtures f where f.season_id=p_season and f.div='D' and f.tie is not null and q.club_id in(f.home,f.away)) ko,
   (select bool_or(public.on_tie_winner(p_season,'L',f.tie)=q.club_id) from public.on_fixtures f where f.season_id=p_season and f.div='D' and f.stage='qf' and q.club_id in(f.home,f.away)) up
  from(select * ,1 g from public.on_table_rank(p_season,'D',1,1) union all select *,2 from public.on_table_rank(p_season,'D',1,2)) q loop
  club_id:=r.club_id;div:='D';
  pos:=case when r.club_id=w then 1 when r.ko=4 then 2 when r.ko=3 then 3 when r.ko=2 then 5 else 8+(r.pos-5)*2+r.g end;
  result:=case when r.club_id=w then 'champion' when coalesce(r.up,false) then 'promoted' when r.ko is not null then 'qf' end;
  return next;
 end loop;
end $$;

create or replace function public.on_series_end(p_season smallint,p_now timestamptz default now()) returns smallint
language plpgsql security definer set search_path=public as $$
declare s public.on_seasons;cfg public.on_config;v_new smallint;r record;v_start date;q record;v_free int[];v_seed text:=md5(gen_random_uuid()::text);
 i int:=0;v_seat int;v_mult numeric;v_idx int;v_prize jsonb;v_b int[];v_old text;
begin
 select * into s from public.on_seasons where id=p_season for update;
 if s.status<>'live' or exists(select 1 from public.on_fixtures where season_id=p_season and status<>'done') then return null;end if;
 select * into cfg from public.on_config;

 -- histórico (posição na série e o que aconteceu) e copa
 insert into public.on_history(season_id,club_id,user_id,name,pos,p,w,d,l,gf,ga,pts,cup,div,result)
 select p_season,k.id,k.user_id,k.name,x.pos,t.p,t.w,t.d,t.l,t.gf,t.ga,t.pts,public.on_cup_reach(p_season,k.id),x.div,x.result
 from public.on_series_result(p_season) x join public.on_clubs k on k.id=x.club_id
 join public.on_table t on t.season_id=p_season and t.club_id=k.id and t.phase=1
 on conflict do nothing;

 -- prêmios da liga por série (a tabela de prêmios da liga, proporcional ao tamanho e ao peso da série)
 perform public.on_award_cup(p_season);
 if s.league_paid_at is null then
  for r in select h.* from public.on_history h where h.season_id=p_season and h.div is not null order by h.div,h.pos loop
   v_mult:=coalesce((cfg.series_mult->>r.div)::numeric,1);
   v_idx:=least(12,ceil(r.pos*12.0/public.on_div_size(r.div)))::int;
   v_prize:=(select jsonb_object_agg(e.key,round(e.value::numeric*v_mult)) from jsonb_each_text(cfg.prize_league->(v_idx-1)) e);
   perform public.on_award(p_season,r.club_id,'L'||r.div,r.pos::text,v_prize,0);
   if r.user_id is not null and r.result in('promoted','champion') and r.div<>'A' then
    insert into public.on_news(club_id,kind,text) values(r.club_id,'season',format('ACESSO! Na próxima temporada o %s joga a %s.',r.name,
     public.on_div_name(chr(ascii(r.div)-1))));
   elsif r.user_id is not null and r.result='relegated' then
    insert into public.on_news(club_id,kind,text) values(r.club_id,'season',format('Rebaixado: na próxima temporada o %s joga a %s.',r.name,
     public.on_div_name(chr(ascii(r.div)+1))));
   end if;
  end loop;
  update public.on_seasons set league_paid_at=now() where id=p_season;
 end if;
 perform public.on_rank_season(p_season);
 update public.on_seasons set status='closed',
  champion=(select club_id from public.on_history where season_id=p_season and div='A' and pos=1),
  cup_champion=(select club_id from public.on_history where season_id=p_season and cup='champion') where id=p_season;

 -- limpeza
 delete from public.on_match_events e using public.on_fixtures f where f.id=e.fixture_id and f.season_id=p_season;
 delete from public.on_match_players mp using public.on_fixtures f where f.id=mp.fixture_id and f.season_id=p_season;
 delete from public.on_bids b using public.on_lots l where l.id=b.lot_id and l.season_id=p_season;
 update public.on_lots set status='cancelled',settled_at=p_now where season_id=p_season and status='open';
 update public.on_clubs k set reserved=0 where k.season_id=p_season;
 delete from public.on_players where club_id is null and id not in(select player_id from public.on_lots where status='open');

 -- nova temporada (um dia de descanso)
 v_start:=(p_now at time zone s.tz)::date+2;
 insert into public.on_seasons(kind,starts_on,seed,tz,slots,series) values(s.kind,v_start,v_seed,s.tz,s.slots,true) returning id into v_new;
 update public.on_clubs set season_id=v_new,coins_conv=0,train_used=0,train_day=null where season_id=p_season;
 -- acesso e rebaixamento
 update public.on_clubs k set div=case when h.result in('promoted','champion') and h.div<>'A' then chr(ascii(h.div)-1)
   when h.result='relegated' and h.div<>'D' then chr(ascii(h.div)+1) else h.div end
 from public.on_history h where h.season_id=p_season and h.club_id=k.id;
 -- bots que mudaram de série trocam de elenco (A: destaque; B: base real; C e D: base gerada)
 for r in select k.id from public.on_clubs k join public.on_history h on h.season_id=p_season and h.club_id=k.id
  where k.season_id=v_new and k.user_id is null and k.div is distinct from h.div loop
  perform public.on_bot_squad(r.id,v_seed);
 end loop;
 update public.on_players p set susp='{}',ylw='{}',yellows=0,susp_round=null from public.on_clubs k where k.id=p.club_id and k.season_id=v_new;

 -- contratos vencidos (só nos clubes de técnicos) viram leilões do sistema na abertura da nova temporada
 v_free:=array(select k.id from public.on_clubs k where k.season_id=v_new and k.user_id is not null);
 for r in select p.id,p.club_id,p.name,p.ovr,p.age,p.pot from public.on_players p where p.club_id=any(v_free) and coalesce(p.contract_end,0)<=p_season
  and (select count(*) from public.on_players x where x.club_id=p.club_id)>16 order by p.club_id,p.ovr loop
  update public.on_players set club_id=null,contract_end=v_new+1 where id=r.id;
  insert into public.on_lots(season_id,player_id,start_price,opens_at,ends_at,hard_end)
  values(v_new,r.id,greatest(500,round(public.on_value(r.ovr,r.age,r.pot)*.4))::bigint,
   (v_start+time '09:00') at time zone s.tz+i*interval '20 minutes',(v_start+time '09:10') at time zone s.tz+i*interval '20 minutes',
   (v_start+time '09:20') at time zone s.tz+i*interval '20 minutes');
  insert into public.on_news(club_id,kind,text) values(r.club_id,'contract',format('O contrato de %s acabou. Ele foi para o mercado.',r.name));
  i:=i+1;
 end loop;
 perform public.on_lineup_repair(x) from unnest(v_free) x;

 -- fila: quem esperava assume os bots pior colocados da Série D
 for q in select a.user_id from public.on_access a where a.state='queued' order by a.queued_at loop
  select h.club_id into v_seat from public.on_history h join public.on_clubs k on k.id=h.club_id and k.user_id is null and k.div='D'
   where h.season_id=p_season order by h.pos desc limit 1;
  exit when v_seat is null;
  perform public.on_take_seat(v_seat,q.user_id,v_seed);
  update public.on_access set state='allowed' where user_id=q.user_id;
  v_seat:=null;
 end loop;

 perform public.on_series_groups(v_new);
 perform public.on_series_fixtures(v_new);
 -- copa: os 6 piores da nova B = os que vieram da C e os piores que ficaram
 v_b:=array(select k.id from public.on_clubs k join public.on_history h on h.season_id=p_season and h.club_id=k.id
  where k.season_id=v_new and k.div='B' order by (h.div='C') desc,h.pos desc);
 perform public.on_cup_start(v_new,v_b);
 return v_new;
end $$;

-- Técnico assume um clube de bot: nome e elenco novos (cartas base + escolha dos 3 craques).
create or replace function public.on_take_seat(p_club int,p_user uuid,p_seed text) returns void
language plpgsql security definer set search_path=public as $$
declare v_nick text;v_name text;k public.on_clubs;
begin
 select * into k from public.on_clubs where id=p_club for update;
 select c.nickname into v_nick from public.careers c where c.user_id=p_user order by (c.status='active') desc,c.created_at desc limit 1;
 v_name:=left('FC '||coalesce(v_nick,'Novo'),24);
 if exists(select 1 from public.on_clubs x where x.season_id=k.season_id and lower(x.name)=lower(v_name) and x.id<>p_club) then v_name:=left(v_name,21)||' '||p_club;end if;
 delete from public.on_lots where player_id in(select id from public.on_players where club_id=p_club) and status<>'open';
 delete from public.on_players where club_id=p_club and id not in(select player_id from public.on_lots);
 update public.on_players set club_id=null where club_id=p_club;
 delete from public.on_lineups where club_id=p_club;
 update public.on_clubs set user_id=p_user,name=v_name,real_key=null,sq=null,
  short=upper(left(coalesce(nullif(regexp_replace(coalesce(v_nick,''),'[^A-Za-z0-9]','','g'),''),'CLB'),3)),
  colors=colors||jsonb_build_object('stadium','Arena '||left(coalesce(v_nick,'do Clube'),20)),
  cash=150000,debt=0,reserved=0,draft_step=0,prep='{}',prep_streak=0,train_used=0,train_day=null,coins_conv=0
 where id=p_club;
 perform public.on_gen_squad(p_club,p_seed||':join:'||p_club,62,k.season_id+1);
 perform public.on_draft_prepare(p_club);
 insert into public.on_news(club_id,kind,text) values(p_club,'season','Bem-vindo à Liga Online D! Escolha seus três craques e prepare o time para o próximo jogo.');
end $$;

-- Cria a estrutura de séries. Fecha a temporada ao vivo sem premiar (títulos e histórico ficam), leva os clubes dos
-- técnicos para a Série D (com elenco e caixa) e cria os bots dos clubes reais. p_users: técnicos novos (testes).
create or replace function public.on_series_bootstrap(p_start date,p_users uuid[] default '{}',p_kind text default 'main') returns smallint
language plpgsql security definer set search_path=public as $$
declare old public.on_seasons;v_s smallint;v_seed text:=md5(gen_random_uuid()::text);v_users int;r record;n int:=0;v_b int[];u uuid;
begin
 select * into old from public.on_seasons where status='live' for update;
 if old.id is not null then update public.on_seasons set status='closed' where id=old.id;end if;
 insert into public.on_seasons(kind,starts_on,seed,series) values(p_kind,p_start,v_seed,true) returning id into v_s;
 if old.id is not null then
  update public.on_lots set season_id=v_s where season_id=old.id and status='open';
  -- bots antigos ficam na temporada encerrada, sem jogadores (os reais voltam ao catálogo)
  delete from public.on_lots l using public.on_players p,public.on_clubs k
   where l.player_id=p.id and p.club_id=k.id and k.season_id=old.id and k.user_id is null and l.status<>'open';
  delete from public.on_players p using public.on_clubs k where p.club_id=k.id and k.season_id=old.id and k.user_id is null
   and p.id not in(select player_id from public.on_lots);
  delete from public.on_lineups l using public.on_clubs k where l.club_id=k.id and k.season_id=old.id and k.user_id is null;
  update public.on_clubs set season_id=v_s,div='D',seat=1000+id,coins_conv=0,train_used=0,train_day=null,real_key=null,sq=null
   where season_id=old.id and user_id is not null;
  update public.on_players p set susp='{}',ylw='{}',yellows=0,susp_round=null,cond=100 from public.on_clubs k where k.id=p.club_id and k.season_id=v_s;
 end if;
 foreach u in array coalesce(p_users,'{}') loop
  insert into public.on_clubs(season_id,user_id,seat,name,short,colors,cash,div)
  values(v_s,u,2000+n,'Novo '||n,'NOV','{}',150000,'D') returning id into r;
  n:=n+1;
 end loop;
 v_users:=(select count(*) from public.on_clubs where season_id=v_s);
 if v_users>30 then raise exception 'Mais de 30 técnicos: a Série D não comporta';end if;
 -- bots: A, B e C inteiras; D completa os 30 com os técnicos
 insert into public.on_clubs(season_id,seat,name,short,colors,cash,draft_step,div,real_key)
 select v_s,(row_number() over(order by x.div0,x.key))::smallint,x.name,x.short,x.colors,
  case x.div0 when 'A' then 3000000 when 'B' then 1500000 when 'C' then 800000 else 500000 end,3,x.div0,x.key
 from(select rc.*,row_number() over(partition by rc.div0 order by public.sim_hash01(v_seed||':real:'||rc.key)) rn from public.on_real_clubs rc) x
 where x.div0<>'D' or x.rn<=30-v_users;
 for r in select k.id from public.on_clubs k where k.season_id=v_s and k.user_id is null order by k.id loop
  perform public.on_bot_squad(r.id,v_seed);
 end loop;
 for r in select k.id,k.user_id from public.on_clubs k where k.season_id=v_s and k.user_id is not null and k.name like 'Novo %' loop
  perform public.on_take_seat(r.id,r.user_id,v_seed);
  insert into public.on_access(user_id,state) values(r.user_id,'allowed') on conflict(user_id) do update set state='allowed';
 end loop;
 perform public.on_series_groups(v_s);
 perform public.on_series_fixtures(v_s);
 v_b:=array(select id from public.on_clubs where season_id=v_s and div='B' order by public.on_strength(id),id);
 perform public.on_cup_start(v_s,v_b);
 return v_s;
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Prêmios e insígnias por série (LA, LB, LC, LD); a liga única antiga continua como L
-- ─────────────────────────────────────────────────────────────────────────────
drop function if exists public.on_award(smallint,integer,character,text,jsonb,integer);
create or replace function public.on_award(p_season smallint, p_club integer, p_comp text, p_place text, p_prize jsonb, p_rank integer)
 returns void language plpgsql security definer set search_path=public as $function$
declare k public.on_clubs;s public.on_seasons;cfg public.on_config;v_first boolean:=false;v_cash bigint;rw jsonb:='{}'::jsonb;
 v_title text;v_body text;v_comp text:=case p_comp when 'L' then 'Liga Online' when 'C' then 'Copa Online' else public.on_div_name(right(p_comp,1)) end;v_car uuid;v_honor text;
begin
 select * into k from public.on_clubs where id=p_club for update;
 select * into s from public.on_seasons where id=p_season;
 select * into cfg from public.on_config;
 v_cash:=coalesce((p_prize->>'cash')::bigint,0);
 -- campeão de técnico: insígnia (a primeira de cada competição é a rara, só na liga principal)
 if k.user_id is not null and p_place in('champion','1') then
  if s.kind='main' and not exists(select 1 from public.on_honors where comp=p_comp and first) then
   insert into public.on_honors(user_id,comp,first,season_id,club_id,club_name) values(k.user_id,p_comp,true,p_season,k.id,k.name)
   on conflict do nothing;
   v_first:=found;
  end if;
  if not v_first then
   insert into public.on_honors(user_id,comp,season_id,club_id,club_name) values(k.user_id,p_comp,p_season,k.id,k.name) on conflict do nothing;
  end if;
  v_honor:=case when v_first then 'honor_first_' else 'honor_' end||case p_comp when 'L' then 'league' when 'C' then 'cup' else 'league_'||lower(right(p_comp,1)) end;
  if v_first then v_cash:=v_cash+coalesce((cfg.prize_first->>'cash')::bigint,0);end if;
 end if;
 if v_cash>0 then perform public.on_money(k.id,v_cash,'prize',format('%s: %s',v_comp,case p_place when 'champion' then 'campeão' when 'final' then 'vice'
  when 'sf' then 'semifinal' when 'qf' then 'quartas de final' when 'r16' then 'oitavas de final' when 'r3' then 'terceira fase' when 'r2' then 'segunda fase' when 'r1' then 'primeira fase' else p_place||'º lugar' end));end if;
 if k.user_id is null then return;end if;

 -- pontos de ranking da copa (a liga segue em on_rank_season)
 if coalesce(p_rank,0)>0 then
  insert into public.on_ranking as r(user_id,points,pts_season,cups) values(k.user_id,p_rank,p_rank,(p_place='champion')::int)
  on conflict(user_id) do update set points=r.points+excluded.points,pts_season=r.pts_season+excluded.pts_season,
   cups=r.cups+excluded.cups,updated_at=now();
 end if;

 rw:=jsonb_strip_nulls(jsonb_build_object(
  'diamonds',nullif(coalesce((p_prize->>'diamonds')::int,0)+case when v_first then coalesce((cfg.prize_first->>'diamonds')::int,0) else 0 end,0),
  'bonus_energy',nullif(coalesce((p_prize->>'energy')::int,0),0),
  'xp',nullif(coalesce((p_prize->>'xp')::int,0),0),
  'golden_whistle',case when v_first then nullif(coalesce((cfg.prize_first->>'golden_whistle')::int,0),0) end));
 if v_honor is not null then rw:=rw||jsonb_build_object(v_honor,1);end if;

 v_title:=case
  when v_first then format('Você é o PRIMEIRO CAMPEÃO DA %s!',upper(v_comp))
  when p_place in('champion','1') then format('Campeão da %s!',v_comp)
  when p_place='final' then format('Vice-campeão da %s',v_comp)
  when p_place='sf' then format('Semifinal da %s',v_comp)
  when p_place='qf' then format('Quartas de final da %s',v_comp)
  when p_place='r1' then format('Participação na %s',v_comp)
  when p_place in('r2','r3','r16') then format('%s da %s',case p_place when 'r2' then 'Segunda fase' when 'r3' then 'Terceira fase' else 'Oitavas de final' end,v_comp)
  else format('%sº lugar na %s',p_place,v_comp) end;
 v_body:=concat_ws(E'\n',
  case when v_first then format('Parabéns, %s! O %s entra para a história como o primeiro campeão da %s. Essa conquista é única: ninguém mais vai ter a insígnia de Primeiro Campeão.',
    coalesce(public.on_coach_name(k.user_id),'técnico'),k.name,v_comp)
   when p_place in('champion','1') then format('Parabéns, %s! O %s é campeão da %s (temporada %s).',coalesce(public.on_coach_name(k.user_id),'técnico'),k.name,v_comp,p_season)
   else format('%s, o %s terminou a %s com %s.',coalesce(public.on_coach_name(k.user_id),'Técnico'),k.name,v_comp,
    case p_place when 'final' then 'o vice-campeonato' when 'sf' then 'a semifinal' when 'qf' then 'as quartas de final'
     when 'r1' then 'a participação na primeira fase' when 'r2' then 'a segunda fase' when 'r3' then 'a terceira fase' when 'r16' then 'as oitavas de final' else p_place||'º lugar' end) end,
  '',
  'PRÊMIOS',
  format('• %s já estão no caixa do clube para investir no mercado.',public.on_fmt_money(v_cash)),
  case when (rw->>'diamonds') is not null then format('• %s diamantes',rw->>'diamonds') end,
  case when (rw->>'bonus_energy') is not null then format('• %s de energia',rw->>'bonus_energy') end,
  case when (rw->>'xp') is not null then format('• %s de XP',replace(to_char((rw->>'xp')::int,'FM999,999'),',','.')) end,
  case when (rw->>'golden_whistle') is not null then format('• %s Apito de Ouro',rw->>'golden_whistle') end,
  case when coalesce(p_rank,0)>0 then format('• %s pontos no ranking (já somados)',p_rank) end,
  case when p_comp like 'L%' then '• Pontos no ranking pela colocação (já somados)' end,
  case when v_honor is not null then format('• Insígnia %s para o seu perfil',
    case when v_first then 'rara "Primeiro Campeão da '||v_comp||'"' else '"Campeão da '||v_comp||'"' end) end,
  '',
  'Toque em Resgatar para receber diamantes, energia, XP'||case when v_honor is not null then ' e a insígnia' else '' end||'.');
 v_car:=public.on_career_of(k.user_id);
 if v_car is not null then
  insert into public.player_notices(career_id,kind,title,body,reward) values(v_car,'reward',left(v_title,120),left(v_body,2000),rw);
 end if;
 insert into public.on_news(club_id,kind,text) values(k.id,'season',format('%s: prêmio de %s no caixa. Resgate o resto na caixa de entrada.',v_title,public.on_fmt_money(v_cash)));
end $function$;

create or replace function public.on_honors_json(p_user uuid) returns jsonb
language sql stable security definer set search_path=public as $$
 select coalesce(jsonb_agg(x order by x.rank,x.comp,x.last desc),'[]'::jsonb) from(
  select case when h.first then 'first_' else '' end||case h.comp when 'L' then 'league' when 'C' then 'cup' else 'league_'||lower(right(h.comp,1)) end id,
   case when h.first then 'Primeiro Campeão da ' else 'Campeão da ' end
    ||case h.comp when 'L' then 'Liga Online' when 'C' then 'Copa Online' else public.on_div_name(right(h.comp,1)) end label,
   h.first,h.comp,count(*) n,max(h.awarded_at) last,
   jsonb_agg(jsonb_build_object('season',h.season_id,'club',h.club_name) order by h.season_id) seasons,
   case when h.first then 0 else 1 end rank
  from public.on_honors h where h.user_id=p_user and h.claimed_at is not null
  group by h.first,h.comp) x
$$;
revoke all on function public.on_honors_json(uuid) from public,anon,authenticated;

-- Fase que cada clube alcançou na copa (nulo: não jogou).
create or replace function public.on_cup_reach(p_season smallint,p_club int) returns text
language sql stable security definer set search_path=public as $$
 select case when bool_or(f.stage='final' and f.status='done' and coalesce(f.leg,2)=2
   and case when f.tie is null then public.on_cup_winner(f) else public.on_tie_winner(p_season,'C',f.tie) end=p_club) then 'champion'
  else (array['r1','r2','r3','r16','qf','sf','final'])[max(case f.stage when 'f1' then 1 when 'r1' then 1 when 'f2' then 2 when 'f3' then 3
   when 'r16' then 4 when 'qf' then 5 when 'sf' then 6 when 'final' then 7 end)] end
 from public.on_fixtures f where f.season_id=p_season and f.comp='C' and p_club in(f.home,f.away)
$$;
CREATE OR REPLACE FUNCTION public.on_match_finish(p_fixture bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare m public.on_matches;f public.on_fixtures;v_hg int;v_ag int;v_pens int[];motm jsonb;v_sum jsonb;v_w int;v_hook text;v_c text;v_first boolean;
begin
 select * into m from public.on_matches where fixture_id=p_fixture for update;
 if m.summary is not null then return m.summary;end if;
 select * into f from public.on_fixtures where id=p_fixture for update;
 v_hg:=(m.state->'score'->>0)::int;v_ag:=(m.state->'score'->>1)::int;
 -- pênaltis: jogo decisivo empatado (na volta, empate no agregado)
 if coalesce((m.state->>'decisive')::boolean,false)
  and v_hg+coalesce((m.state->'agg'->>0)::int,0)=v_ag+coalesce((m.state->'agg'->>1)::int,0) then
  v_pens:=public.on_shootout(p_fixture,greatest(m.minute,90));
  update public.on_matches set state=state||jsonb_build_object('pens',to_jsonb(v_pens)) where fixture_id=p_fixture;
 end if;
 perform public.on_rate(p_fixture,true);
 select jsonb_build_object('id',mp.player_id,'name',mp.name,'side',mp.side,'rating',mp.rating,'goals',mp.goals,'assists',mp.assists) into motm
  from public.on_match_players mp where mp.fixture_id=p_fixture and mp.minutes>0 order by mp.rating desc,mp.goals desc,mp.player_id limit 1;
 v_w:=case when v_hg>v_ag or (v_pens is not null and v_pens[1]>v_pens[2]) then f.home when v_ag>v_hg or v_pens is not null then f.away end;
 v_sum:=jsonb_build_object('fixture_id',p_fixture,'home',f.home,'away',f.away,'home_goals',v_hg,'away_goals',v_ag,'pens',to_jsonb(v_pens),
  'winner',v_w,'motm',motm);
 update public.on_matches set status='finished',summary=v_sum,updated_at=now() where fixture_id=p_fixture;

 -- classificação: só na primeira vez que o jogo vira 'done' (terminar duas vezes não soma em dobro)
 update public.on_fixtures set status='done',hg=v_hg,ag=v_ag,pens=to_jsonb(v_pens) where id=p_fixture and status<>'done';
 v_first:=found;
 if v_first and f.comp='L' and (f.tphase is not null or f.div is null) then
  update public.on_table t set p=t.p+1,
   w=t.w+(x.gf>x.ga)::int,d=t.d+(x.gf=x.ga)::int,l=t.l+(x.gf<x.ga)::int,gf=t.gf+x.gf,ga=t.ga+x.ga,
   pts=t.pts+case when x.gf>x.ga then 3 when x.gf=x.ga then 1 else 0 end
  from(values(f.home,v_hg,v_ag),(f.away,v_ag,v_hg)) x(club,gf,ga)
  where t.season_id=f.season_id and t.club_id=x.club and t.phase=coalesce(f.tphase,1);
 end if;

 -- quem cumpriu suspensão nesta competição (não podia jogar) desconta um jogo
 v_c:=f.comp;
 update public.on_players p set susp=p.susp||jsonb_build_object(v_c,(p.susp->>v_c)::int-1)
  where v_first and p.club_id in(f.home,f.away) and coalesce((p.susp->>v_c)::int,0)>0
   and not exists(select 1 from public.on_match_players mp where mp.fixture_id=p_fixture and mp.player_id=p.id);
 -- condição, ritmo, cartões e lesões voltam para o elenco em uma instrução.
 -- Suspensão por competição: vermelho tira do próximo jogo; cada 2 amarelos acumulados também.
 update public.on_players p set
  cond=round(mp.cond)::smallint,
  rhythm=least(100,p.rhythm+case when mp.minutes>=45 then 10 when mp.minutes>0 then 5 else 0 end),
  ylw=case when not v_first then p.ylw else p.ylw||jsonb_build_object(v_c,case when mp.red>0 then coalesce((p.ylw->>v_c)::int,0) else (coalesce((p.ylw->>v_c)::int,0)+mp.yellow)%2 end) end,
  susp=case when not v_first then p.susp else p.susp||jsonb_build_object(v_c,coalesce((p.susp->>v_c)::int,0)
   +case when mp.red>0 then 1 else (coalesce((p.ylw->>v_c)::int,0)+mp.yellow)/2 end) end,
  yellows=case when not v_first or mp.red>0 then p.yellows else (coalesce((p.ylw->>v_c)::int,0)+mp.yellow)%2 end,
  inj_until=case when mp.injured then (now() at time zone 'America/Sao_Paulo')::date+1+case when coalesce((select (k.lv->>'medical')::int from public.on_clubs k where k.id=mp.club_id),0)>=3 then 0 else floor(random()*2)::int end else p.inj_until end
 from public.on_match_players mp
 where mp.fixture_id=p_fixture and p.id=mp.player_id and p.club_id=mp.club_id and mp.status<>'bench';
 -- condição para o próximo jogo (fase 33)
 update public.on_players p set arrow=public.on_arrow_next(p.form,p.arrow,
   (select mp.rating from public.on_match_players mp where mp.fixture_id=p_fixture and mp.player_id=p.id and mp.minutes>0),
   p.club_id=v_w)
 where p.club_id in(f.home,f.away);
 -- fases seguintes (bilheteria, copa...)
 for v_hook in select unnest(finish_hooks) from public.on_config loop
  execute format('select public.%I($1)',v_hook) using p_fixture;
 end loop;
 return v_sum;
end $function$;

-- Partida: jogo decisivo (copa em jogo único ou na volta) vai direto aos pênaltis nas séries (sem prorrogação);
-- na volta, o placar da ida entra no agregado.
do $$ begin
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  'v_dec boolean:=p_fx.comp=''C'';',
  'v_dec boolean:=p_fx.comp=''C'' and coalesce(p_fx.leg,2)=2;');
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  'v_neut boolean:=p_fx.stage=''final'';',
  'v_neut boolean:=p_fx.stage=''final'' and p_fx.slot is null;');
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  '''agg'',jsonb_build_array(0,0)',
  '''agg'',coalesce((select jsonb_build_array(f1.ag,f1.hg) from public.on_fixtures f1 where f1.season_id=p_fx.season_id and f1.comp=p_fx.comp and f1.tie=p_fx.tie and f1.leg=1 and p_fx.leg=2),jsonb_build_array(0,0))');
 perform public.on_patch('public.on_match_open(public.on_fixtures)',
  '''extra_time_rule'',v_dec,',
  '''extra_time_rule'',v_dec and p_fx.slot is null,''leg'',p_fx.leg,''div'',p_fx.div,');
 perform public.on_patch('public.on_match_payload(bigint,integer,character)',
  '''comp'',f.comp,''round'',f.round,''stage'',f.stage,',
  '''comp'',f.comp,''div'',f.div,''leg'',f.leg,''agg'',m.state->''agg'',''round'',f.round,''stage'',f.stage,');
 perform public.on_patch('public.on_award_cup(smallint)',
  'comp=''C'' and stage=''final'' and status=''done'')',
  'comp=''C'' and stage=''final'' and status=''done'' and coalesce(leg,2)=2)');
 perform public.on_patch('public.on_squad()',
  '''suspended'',v_next.comp=''L'' and p.susp_round is not null and p.susp_round>=v_next.round,',
  '''suspended'',coalesce((p.susp->>v_next.comp)::int,0)>0,''susp'',p.susp,''ylw'',p.ylw,''tier'',p.tier,');
 perform public.on_patch('public.on_tick(timestamp with time zone)',
  'and x.kickoff<=p_now order by x.kickoff limit 8 loop','and x.kickoff<=p_now order by x.kickoff limit 120 loop');
end $$;

-- Suspensão por competição.
create or replace function public.on_can_play(p public.on_players,p_club int,p_fx public.on_fixtures) returns boolean
language sql stable set search_path=public as $$
 select p.club_id=p_club and (p.inj_until is null or p.inj_until<=(p_fx.kickoff at time zone 'America/Sao_Paulo')::date)
  and coalesce((p.susp->>p_fx.comp)::int,0)=0
$$;

-- Bilheteria: copa paga 50% a mais; as finais agora são em ida e volta (cada um no seu estádio).
create or replace function public.on_gate_income(p_fixture bigint) returns void
language plpgsql security definer set search_path=public as $$
declare f public.on_fixtures;v bigint;
begin
 select * into f from public.on_fixtures where id=p_fixture;
 if f.stage='final' and f.slot is null then return;end if; -- final antiga em campo neutro
 select public.on_gate_value((lv->>'stadium')::int)*case when f.comp='C' then 1.5 else 1 end into v from public.on_clubs where id=f.home for update;
 perform public.on_money(f.home,v,'gate','Bilheteria');
end $$;

-- Ranking pela temporada: pontos da colocação na série (8 primeiros), proporcionais ao peso da série.
create or replace function public.on_rank_season(p_season smallint) returns void
language plpgsql security definer set search_path=public as $$
declare cfg public.on_config;h record;v int;
begin
 select * into cfg from public.on_config;
 for h in select * from public.on_history where season_id=p_season and user_id is not null loop
  v:=round(coalesce((cfg.rank_rules->'league'->>(h.pos-1))::int,0)*coalesce((cfg.series_mult->>h.div)::numeric,1));
  insert into public.on_ranking as r(user_id,points,pts_season,league_titles,cups,seasons)
  values(h.user_id,v,v,(h.pos=1 and coalesce(h.div,'A')='A')::int,0,1)
  on conflict(user_id) do update set points=r.points+excluded.points,pts_season=r.pts_season+excluded.pts_season,
   league_titles=r.league_titles+excluded.league_titles,cups=r.cups+excluded.cups,seasons=r.seasons+1,updated_at=now();
 end loop;
end $$;

-- Entrada na hora: o técnico assume o bot pior colocado da Série D (fora de jogo e de leilão); sem vaga, fila.
create or replace function public.on_join_queue() returns jsonb
language plpgsql security definer set search_path=public as $$
declare v_uid uuid:=auth.uid();s public.on_seasons;v_club int;
begin
 if v_uid is null then raise exception 'Entre na sua conta para jogar';end if;
 if not public.on_gate() then raise exception 'O modo online ainda não está aberto para a sua conta';end if;
 select * into s from public.on_seasons where status='live';
 if s.id is not null and exists(select 1 from public.on_clubs where season_id=s.id and user_id=v_uid) then return public.on_status();end if;
 if s.id is not null and (select join_instant from public.on_config) then
  select k.id into v_club from public.on_clubs k
  where k.season_id=s.id and k.user_id is null and k.reserved=0 and (k.div='D' or not coalesce(s.series,false))
   and not exists(select 1 from public.on_matches m join public.on_fixtures f on f.id=m.fixture_id where m.status='live' and k.id in(f.home,f.away))
   and not exists(select 1 from public.on_lots l where l.status='open' and l.best_club=k.id)
  order by (select r.pos from public.on_rank(s.id) r where r.club_id=k.id) desc nulls last,k.id
  limit 1 for update of k skip locked;
 end if;
 if v_club is null then
  insert into public.on_access(user_id,state) values(v_uid,'queued') on conflict(user_id) do nothing;
  return public.on_status();
 end if;
 perform public.on_take_seat(v_club,v_uid,s.seed);
 insert into public.on_access(user_id,state) values(v_uid,'allowed') on conflict(user_id) do update set state='allowed';
 return public.on_status();
end $$;

-- Status do técnico com a série, o grupo e a rodada da série.
CREATE OR REPLACE FUNCTION public.on_status()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_uid uuid:=auth.uid();s public.on_seasons;c public.on_clubs;a text;cfg public.on_config;v_today date;j jsonb;
begin
 if v_uid is null then raise exception 'Entre na sua conta para jogar';end if;
 if not public.on_gate() then
  return jsonb_build_object('server_now',now(),'access','unavailable','season',null,'club',null,'next',null);
 end if;
 select x.* into s from public.on_seasons x where x.status='live';
 select x.state into a from public.on_access x where x.user_id=v_uid;
 if s.id is not null then select k.* into c from public.on_clubs k where k.season_id=s.id and k.user_id=v_uid;end if;
 j:=jsonb_build_object('server_now',now(),
  'access',case when c.id is not null then 'playing' when a is not null then 'queued' else 'none' end,
  'season',case when s.id is null then null else jsonb_build_object('id',s.id,'kind',s.kind,'starts_on',s.starts_on) end,
  'club',null,'next',null);
 if c.id is null then return j;end if;
 select * into cfg from public.on_config;
 v_today:=(now() at time zone s.tz)::date;
 return j||jsonb_build_object(
  'club',jsonb_build_object('id',c.id,'name',c.name,'short',c.short,'colors',c.colors,
   'cash',c.cash,'reserved',c.reserved,'debt',c.debt,'draft_step',c.draft_step,'levels',c.lv,
   'roster',(select count(*) from public.on_players p where p.club_id=c.id),
   'strength',public.on_strength(c.id)),
  'coins',coalesce(public.on_wallet(),0),
  'day',jsonb_build_object('n',coalesce((select min(f.round) from public.on_fixtures f where f.season_id=s.id and f.comp='L' and c.id in(f.home,f.away) and f.status<>'done'),
    (select max(f.round) from public.on_fixtures f where f.season_id=s.id and f.comp='L' and c.id in(f.home,f.away)),0),
   'of',case when s.series then public.on_div_rounds(c.div) else 22 end,'round',true),
  'league',case when c.div is not null then jsonb_build_object('div',c.div,'name',public.on_div_name(c.div),'grp',nullif(c.grp,0),'size',public.on_div_size(c.div),
   'season',s.id,'start',s.starts_on) end,
  'position',(select x.pos from public.on_rank(s.id) x where x.club_id=c.id),
  'standing',(select jsonb_build_object('p',t.p,'w',t.w,'d',t.d,'l',t.l,'gf',t.gf,'ga',t.ga,'pts',t.pts) from public.on_table t where t.season_id=s.id and t.club_id=c.id and t.phase=1),
  'form',coalesce((select jsonb_agg(x.r order by x.kickoff) from(
    select f.kickoff,case when f.hg=f.ag then 'D' when (f.hg>f.ag)=(f.home=c.id) then 'W' else 'L' end r
    from public.on_fixtures f where f.season_id=s.id and f.status='done' and c.id in(f.home,f.away) order by f.kickoff desc limit 5) x),'[]'::jsonb),
  'next',(select jsonb_build_object('id',f.id,'comp',f.comp,'div',f.div,'leg',f.leg,'round',f.round,'stage',f.stage,'kickoff',f.kickoff,
    'status',f.status,'live',f.kickoff<=now(),'at_home',f.home=c.id,
    'opp',jsonb_build_object('id',o.id,'name',o.name,'short',o.short,'colors',o.colors,'bot',o.user_id is null,
     'position',(select x.pos from public.on_rank(s.id) x where x.club_id=o.id)))
   from public.on_fixtures f join public.on_clubs o on o.id=case when f.home=c.id then f.away else f.home end
   where f.season_id=s.id and f.status<>'done' and (f.home=c.id or f.away=c.id) order by f.kickoff limit 1),
  'rest_today',not exists(select 1 from public.on_fixtures f where f.season_id=s.id and c.id in(f.home,f.away) and (f.kickoff at time zone s.tz)::date=v_today)
   and exists(select 1 from public.on_fixtures f where f.season_id=s.id and (f.kickoff at time zone s.tz)::date=v_today),
  'last',(select jsonb_build_object('id',f.id,'hg',f.hg,'ag',f.ag,'at_home',f.home=c.id,'comp',f.comp,'div',f.div,'stage',f.stage,'pens',f.pens,'round',f.round,
    'opp',jsonb_build_object('id',o.id,'name',o.name,'short',o.short,'colors',o.colors))
   from public.on_fixtures f join public.on_clubs o on o.id=case when f.home=c.id then f.away else f.home end
   where f.season_id=s.id and f.status='done' and (f.home=c.id or f.away=c.id) order by f.kickoff desc limit 1),
  'prep',case when c.draft_step>=3 then public.on_prep_json(c,public.on_next_fixture(c.id)) end,'train',jsonb_build_object('used',case when c.train_day=v_today then c.train_used else 0 end,'max',public.on_train_max(c,v_today),'energy',c.train_energy),
  'featured',(select jsonb_build_object('count',count(*),'ends_at',min(l.ends_at)) from public.on_lots l
   where l.season_id=s.id and l.status='open' and l.featured>0 and l.opens_at<=now()),
  'bids',coalesce((select jsonb_agg(public.on_lot_json(l,c.id) order by l.ends_at) from(
    select * from public.on_lots x where x.season_id=s.id and x.status='open'
     and (x.seller=c.id or exists(select 1 from public.on_bids b where b.lot_id=x.id and b.club_id=c.id)) order by x.ends_at limit 6) l),'[]'::jsonb),
  'results',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'text',n.text,'data',n.data,'at',n.at) order by n.id desc) from(
    select * from public.on_news x where x.club_id=c.id and x.kind='auction' and x.seen_at is null order by x.id desc limit 5) n),'[]'::jsonb),
  'news',coalesce((select jsonb_agg(jsonb_build_object('id',n.id,'kind',n.kind,'text',n.text,'at',n.at) order by n.id desc) from(
    select * from public.on_news x where x.club_id=c.id and x.kind<>'auction' order by x.id desc limit 5) n),'[]'::jsonb));
end $function$;
do $$ begin
 perform public.on_patch('public.on_scout(boolean)',
  'from public.on_table t where t.season_id=c.season_id and t.club_id=o.id)',
  'from public.on_table t where t.season_id=c.season_id and t.club_id=o.id and t.phase=1)');
end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- Leituras para o app
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function public.on_club_json(k public.on_clubs) returns jsonb
language sql stable set search_path=public as $$
 select jsonb_build_object('id',k.id,'name',k.name,'short',k.short,'colors',k.colors,'bot',k.user_id is null,'div',k.div,
  'crest',(select rc.crest from public.on_real_clubs rc where rc.key=k.real_key))
$$;

drop function if exists public.on_standings();
-- Tabelas de uma série (padrão: a do técnico): fases, grupos, zonas e mata-matas.
create or replace function public.on_standings(p_div text default null) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();s public.on_seasons;d text;
begin
 select * into s from public.on_seasons where id=c.season_id;
 if not coalesce(s.series,false) then
  return jsonb_build_object('my_club',c.id,'rows',(select jsonb_agg(public.on_club_json(k)||jsonb_build_object('club_id',k.id,'p',t.p,'w',t.w,'d',t.d,'l',t.l,'gf',t.gf,'ga',t.ga,'pts',t.pts)
    order by t.pts desc,t.gf-t.ga desc,t.gf desc,k.name) from public.on_table t join public.on_clubs k on k.id=t.club_id where t.season_id=c.season_id));
 end if;
 d:=coalesce(upper(p_div),c.div,'D');
 return jsonb_build_object('my_club',c.id,'my_div',c.div,'div',d,'name',public.on_div_name(d),'size',public.on_div_size(d),
  'rounds',public.on_div_rounds(d),
  'current_round',coalesce((select min(f.round) from public.on_fixtures f where f.season_id=s.id and f.div=d and f.status<>'done'),public.on_div_rounds(d)),
  'divisions',(select jsonb_agg(jsonb_build_object('div',x,'name',public.on_div_name(x),'size',public.on_div_size(x))) from unnest(array['A','B','C','D']) x),
  'tables',coalesce((select jsonb_agg(jsonb_build_object('phase',g.phase,'grp',g.grp,'rows',(
     select jsonb_agg(public.on_club_json(k)||jsonb_build_object('pos',r.pos,'p',t.p,'w',t.w,'d',t.d,'l',t.l,'gf',t.gf,'ga',t.ga,'pts',t.pts,
       'form',(select jsonb_agg(z.r order by z.kickoff) from(select f.kickoff,case when f.hg=f.ag then 'D' when (f.hg>f.ag)=(f.home=k.id) then 'W' else 'L' end r
        from public.on_fixtures f where f.season_id=s.id and f.comp='L' and f.status='done' and k.id in(f.home,f.away) order by f.kickoff desc limit 5) z))
      order by r.pos)
     from public.on_table_rank(s.id,d,g.phase,g.grp) r join public.on_table t on t.season_id=s.id and t.club_id=r.club_id and t.phase=g.phase
     join public.on_clubs k on k.id=r.club_id)) order by g.phase,g.grp)
   from(select distinct t.phase,t.grp from public.on_table t where t.season_id=s.id and t.div=d) g),'[]'::jsonb),
  'ties',coalesce((select jsonb_agg(x order by x->>'stage_order',(x->>'tie')::int) from(
    select jsonb_build_object('tie',f.tie,'stage',min(f.stage),'stage_order',min(case f.stage when 'po' then 1 when 'qf' then 1 when 'sf' then 2 when 'final' then 3 end)::text,
     'winner',public.on_tie_winner(s.id,'L',f.tie),'adv',min(f.adv),
     'legs',jsonb_agg(jsonb_build_object('id',f.id,'leg',f.leg,'home',f.home,'away',f.away,'hg',f.hg,'ag',f.ag,'status',f.status,'kickoff',f.kickoff) order by f.leg),
     'clubs',(select jsonb_agg(public.on_club_json(k)) from public.on_clubs k where k.id in(min(f.home),min(f.away)))) x
    from public.on_fixtures f where f.season_id=s.id and f.div=d and f.tie is not null group by f.tie) q),'[]'::jsonb));
end $$;

-- Jogos de uma rodada de uma série (padrão: a rodada atual da série do técnico).
create or replace function public.on_round(p_div text default null,p_round int default null) returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();d text:=coalesce(upper(p_div),c.div,'D');r int;
begin
 r:=coalesce(p_round,(select min(f.round) from public.on_fixtures f where f.season_id=c.season_id and f.div=d and f.status<>'done'),
  (select max(f.round) from public.on_fixtures f where f.season_id=c.season_id and f.div=d),1);
 return jsonb_build_object('server_now',now(),'div',d,'name',public.on_div_name(d),'round',r,'rounds',public.on_div_rounds(d),
  'last_round',(select max(f.round) from public.on_fixtures f where f.season_id=c.season_id and f.div=d),
  'my_club',c.id,
  'fixtures',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'kickoff',f.kickoff,'status',f.status,'hg',f.hg,'ag',f.ag,'stage',f.stage,'leg',f.leg,'grp',f.grp,
    'home',public.on_club_json(h),'away',public.on_club_json(a),
    'live',case when f.status='live' then (select jsonb_build_object('minute',m.minute,'score',m.state->'score') from public.on_matches m where m.fixture_id=f.id) end)
    order by f.grp nulls first,f.kickoff,f.id)
   from public.on_fixtures f join public.on_clubs h on h.id=f.home join public.on_clubs a on a.id=f.away
   where f.season_id=c.season_id and f.div=d and f.round=r),'[]'::jsonb));
end $$;

-- Calendário do técnico: só os jogos do clube (liga e copa), com adversário, horário e resultado.
create or replace function public.on_calendar() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();s public.on_seasons;
begin
 select * into s from public.on_seasons where id=c.season_id;
 if not coalesce(s.series,false) then -- liga única antiga: todos os jogos
  return jsonb_build_object('server_now',now(),'my_club',c.id,
   'clubs',(select jsonb_agg(jsonb_build_object('id',k.id,'name',k.name,'short',k.short,'colors',k.colors,'bot',k.user_id is null) order by k.id)
    from public.on_clubs k where k.season_id=c.season_id),
   'fixtures',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'comp',f.comp,'round',f.round,'stage',f.stage,'home',f.home,'away',f.away,
     'kickoff',f.kickoff,'status',f.status,'hg',f.hg,'ag',f.ag,'pens',f.pens) order by f.kickoff,f.id)
    from public.on_fixtures f where f.season_id=c.season_id),'[]'::jsonb));
 end if;
 return jsonb_build_object('server_now',now(),'my_club',c.id,'tz',s.tz,'start',s.starts_on,'series',s.series,
  'club',public.on_club_json(c),
  'clubs',coalesce((select jsonb_agg(public.on_club_json(k)) from public.on_clubs k where k.id in(
    select case when f.home=c.id then f.away else f.home end from public.on_fixtures f where f.season_id=c.season_id and c.id in(f.home,f.away))),'[]'::jsonb),
  'fixtures',coalesce((select jsonb_agg(jsonb_build_object('id',f.id,'comp',f.comp,'div',f.div,'round',f.round,'stage',f.stage,'leg',f.leg,'home',f.home,'away',f.away,
    'kickoff',f.kickoff,'status',f.status,'hg',f.hg,'ag',f.ag,'pens',f.pens) order by f.kickoff,f.id)
   from public.on_fixtures f where f.season_id=c.season_id and c.id in(f.home,f.away)),'[]'::jsonb));
end $$;

-- Copa: fases com os confrontos (agregado e vencedor) e o caminho do técnico; histórico das temporadas.
create or replace function public.on_cup() returns jsonb
language plpgsql stable security definer set search_path=public as $$
declare c public.on_clubs:=public.on_me();
begin
 return jsonb_build_object('my_club',c.id,'series',(select series from public.on_seasons where id=c.season_id),
  'stages',coalesce((select jsonb_agg(jsonb_build_object('stage',q.stage,'ties',q.ties) order by q.o) from(
    select f.stage,min(f.round) o,jsonb_agg(jsonb_build_object('tie',f.tie,'winner',public.on_tie_winner(c.season_id,'C',f.tie),
      'home',(select public.on_club_json(k) from public.on_clubs k where k.id=f.home),'away',(select public.on_club_json(k) from public.on_clubs k where k.id=f.away),
      'legs',(select jsonb_agg(jsonb_build_object('id',x.id,'leg',x.leg,'home',x.home,'hg',x.hg,'ag',x.ag,'pens',x.pens,'status',x.status,'kickoff',x.kickoff) order by x.leg)
        from public.on_fixtures x where x.season_id=c.season_id and x.comp='C' and x.tie=f.tie),
      'mine',c.id in(f.home,f.away)) order by (c.id in(f.home,f.away)) desc,f.tie) ties
    from public.on_fixtures f where f.season_id=c.season_id and f.comp='C' and coalesce(f.leg,1)=1 group by f.stage) q),'[]'::jsonb),
  -- formato antigo (temporadas de liga única)
  'rounds',coalesce((select jsonb_agg(jsonb_build_object('round',f.round,'stage',f.stage,'id',f.id,'kickoff',f.kickoff,'status',f.status,'hg',f.hg,'ag',f.ag,'pens',f.pens,
    'home',jsonb_build_object('id',h.id,'name',h.name,'short',h.short,'colors',h.colors),
    'away',jsonb_build_object('id',a.id,'name',a.name,'short',a.short,'colors',a.colors),
    'winner',case when f.status='done' then public.on_cup_winner(f) end) order by f.round,f.kickoff)
   from public.on_fixtures f join public.on_clubs h on h.id=f.home join public.on_clubs a on a.id=f.away
   where f.season_id=c.season_id and f.comp='C' and f.slot is null),'[]'::jsonb),
  'history',coalesce((select jsonb_agg(jsonb_build_object('season',x.season_id,'champion',x.champ,'cup',x.cupw,'me',x.me,'series',x.ser) order by x.season_id desc) from(
    select h.season_id,coalesce(max(h.name) filter(where h.pos=1 and h.div='A'),max(h.name) filter(where h.pos=1 and h.div is null)) champ,
     max(h.name) filter(where h.cup='champion') cupw,
     jsonb_object_agg(h.div,h.name) filter(where h.pos=1 and h.div is not null) ser,
     max(jsonb_build_object('pos',h.pos,'pts',h.pts,'cup',h.cup,'div',h.div,'result',h.result)::text) filter(where h.user_id=auth.uid())::jsonb me
    from public.on_history h group by h.season_id) x),'[]'::jsonb));
end $$;

-- Premiação pela caixa de entrada aceita as insígnias das séries (honor_league_a ... honor_first_league_d).
do $$ begin
 if to_regprocedure('public.inbox_claim(text,text)') is not null then
  perform public.on_patch('public.inbox_reward_clean(jsonb)',
   '''honor_first_league'',''honor_first_cup'',''honor_league'',''honor_cup'']) k',
   '''honor_first_league'',''honor_first_cup'',''honor_league'',''honor_cup'',''honor_league_a'',''honor_league_b'',''honor_league_c'',''honor_league_d'',''honor_first_league_a'',''honor_first_league_b'',''honor_first_league_c'',''honor_first_league_d'']) k');
  perform public.on_patch('public.inbox_reward_text(jsonb)',
   'case when p ?| array[''honor_first_league'',''honor_first_cup'',''honor_league'',''honor_cup'']',
   'case when exists(select 1 from jsonb_object_keys(p) k where k like ''honor\_%'')');
  perform public.on_patch('public.inbox_claim(text,text)',
   'and h.comp=case when k like ''%league'' then ''L'' else ''C'' end',
   'and h.comp=case when k ~ ''league_[abcd]$'' then ''L''||upper(right(k,1)) when k like ''%league'' then ''L'' else ''C'' end');
 end if;
end $$;

-- ganchos: o das séries roda depois do da copa antiga (que só age nas temporadas de liga única); destaques da A evoluem
do $$ begin
 perform public.on_patch('public.on_cup_hook(bigint)',
  ' select * into f from public.on_fixtures where id=p_fixture;',
  ' select * into f from public.on_fixtures where id=p_fixture;
 if coalesce((select series from public.on_seasons where id=f.season_id),false) then return;end if; -- séries: on_series_hook');
end $$;
update public.on_config set finish_hooks=array(select x from unnest(array['on_cup_hook','on_gate_income','on_rank_hook','on_star_grow','on_series_hook']) x
 where to_regprocedure('public.'||x||'(bigint)') is not null);

revoke all on function public.on_div_name(text),public.on_div_size(text),public.on_div_rounds(text),public.on_div_offset(text),
 public.on_round_slot(text,int),public.on_slot_kick(smallint,int,text),public.on_rr(int[],boolean),public.on_gen_fake(int,text,int,int),
 public.on_bot_squad(int,text),public.on_star_grow(bigint),public.on_table_rank(smallint,text,int,int),public.on_tie_winner(smallint,text,int),
 public.on_fx_add(smallint,text,text,int,int,int,int,int,int,int,text,int),public.on_series_fixtures(smallint),public.on_series_groups(smallint),
 public.on_cup_draw(smallint,int,int[]),public.on_cup_start(smallint,int[]),public.on_series_hook(bigint),public.on_series_ko(smallint,text,int,int,int,int,text),
 public.on_series_result(smallint),public.on_series_end(smallint,timestamptz),public.on_take_seat(int,uuid,text),public.on_series_bootstrap(date,uuid[],text),
 public.on_award(smallint,integer,text,text,jsonb,integer),public.on_cup_reach(smallint,int),public.on_can_play(public.on_players,int,public.on_fixtures),
 public.on_gate_income(bigint),public.on_rank_season(smallint),public.on_club_json(public.on_clubs)
 from public,anon,authenticated;
revoke all on function public.on_standings(text),public.on_round(text,int),public.on_calendar(),public.on_cup(),public.on_join_queue(),public.on_status() from public,anon;
grant execute on function public.on_standings(text),public.on_round(text,int),public.on_calendar(),public.on_cup(),public.on_join_queue(),public.on_status() to authenticated;
