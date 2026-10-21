-- =====================================================================
-- MODO TEMPORADAS — 2/3: DADOS (cadastro manual)
-- Fontes pesquisadas em out/2026: Série A 2026 (20 clubes), Copa do Brasil 2026
-- (16 clubes nas oitavas, sorteio de 26/05/2026) e Libertadores 2026 (32 clubes, 8 grupos).
-- "strength" é a força do clube de 30 a 99: é um palpite editável, não um dado oficial.
-- =====================================================================

insert into public.sim_clubs (id, name, short_name, country, tier, strength, color_primary, color_secondary) values
-- Série A 2026 --------------------------------------------------------
('flamengo',        'Flamengo',            'FLA', 'BRA', 'serie_a', 80, '#C8102E', '#111111'),
('palmeiras',       'Palmeiras',           'PAL', 'BRA', 'serie_a', 79, '#006437', '#FFFFFF'),
('botafogo',        'Botafogo',            'BOT', 'BRA', 'serie_a', 76, '#111111', '#FFFFFF'),
('fluminense',      'Fluminense',          'FLU', 'BRA', 'serie_a', 75, '#8B1E3F', '#0A7A3D'),
('cruzeiro',        'Cruzeiro',            'CRU', 'BRA', 'serie_a', 76, '#0033A0', '#FFFFFF'),
('atletico-mg',     'Atlético-MG',         'CAM', 'BRA', 'serie_a', 75, '#111111', '#FFFFFF'),
('corinthians',     'Corinthians',         'COR', 'BRA', 'serie_a', 75, '#111111', '#FFFFFF'),
('sao-paulo',       'São Paulo',           'SAO', 'BRA', 'serie_a', 74, '#E4002B', '#111111'),
('athletico-pr',    'Athletico-PR',        'CAP', 'BRA', 'serie_a', 74, '#C8102E', '#111111'),
('bahia',           'Bahia',               'BAH', 'BRA', 'serie_a', 74, '#0057B8', '#E31B23'),
('internacional',   'Internacional',       'INT', 'BRA', 'serie_a', 73, '#E4002B', '#FFFFFF'),
('gremio',          'Grêmio',              'GRE', 'BRA', 'serie_a', 73, '#0099D8', '#111111'),
('bragantino',      'Red Bull Bragantino', 'RBB', 'BRA', 'serie_a', 72, '#C8102E', '#FFFFFF'),
('santos',          'Santos',              'SAN', 'BRA', 'serie_a', 72, '#111111', '#FFFFFF'),
('vasco',           'Vasco da Gama',       'VAS', 'BRA', 'serie_a', 72, '#111111', '#FFFFFF'),
('coritiba',        'Coritiba',            'CFC', 'BRA', 'serie_a', 68, '#00693E', '#FFFFFF'),
('vitoria',         'Vitória',             'VIT', 'BRA', 'serie_a', 68, '#D00027', '#111111'),
('mirassol',        'Mirassol',            'MIR', 'BRA', 'serie_a', 68, '#FFD100', '#00A859'),
('remo',            'Remo',                'REM', 'BRA', 'serie_a', 62, '#001F5B', '#7FB6E8'),
('chapecoense',     'Chapecoense',         'CHA', 'BRA', 'serie_a', 60, '#00A859', '#FFFFFF'),
-- Brasileiros que só jogam a Copa do Brasil (Série B) -------------------
('fortaleza',       'Fortaleza',           'FOR', 'BRA', 'br_other', 69, '#003C8F', '#D81E05'),
('juventude',       'Juventude',           'JUV', 'BRA', 'br_other', 62, '#00A859', '#FFFFFF'),
-- Estrangeiros da Libertadores 2026 -------------------------------------
('estudiantes',     'Estudiantes',         'EST', 'ARG', 'foreign', 75, '#C8102E', '#FFFFFF'),
('cusco',           'Cusco FC',            'CUS', 'PER', 'foreign', 58, '#B71C1C', '#FFFFFF'),
('ind-medellin',    'Independiente Medellín','DIM','COL', 'foreign', 62, '#C8102E', '#1E3A8A'),
('nacional-uru',    'Nacional',            'NAC', 'URU', 'foreign', 73, '#1F3A93', '#FFFFFF'),
('universitario',   'Universitario',       'UNI', 'PER', 'foreign', 70, '#7B1E1E', '#F5E6C8'),
('coquimbo',        'Coquimbo Unido',      'COQ', 'CHI', 'foreign', 60, '#FFD100', '#111111'),
('tolima',          'Deportes Tolima',     'TOL', 'COL', 'foreign', 62, '#7A1F2B', '#F2C300'),
('bolivar',         'Bolívar',             'BOL', 'BOL', 'foreign', 66, '#3AA7E0', '#FFFFFF'),
('la-guaira',       'Deportivo La Guaira', 'LAG', 'VEN', 'foreign', 54, '#1F57B5', '#FFFFFF'),
('ind-rivadavia',   'Independiente Rivadavia','RIV','ARG','foreign', 66, '#0057B8', '#FFFFFF'),
('boca-juniors',    'Boca Juniors',        'BOC', 'ARG', 'foreign', 78, '#0A3D91', '#F5C400'),
('u-catolica',      'Universidad Católica','UCA', 'CHI', 'foreign', 66, '#1D4E9E', '#FFFFFF'),
('barcelona-sc',    'Barcelona SC',        'BSC', 'ECU', 'foreign', 70, '#F6C900', '#111111'),
('penarol',         'Peñarol',             'PEN', 'URU', 'foreign', 74, '#F6C900', '#111111'),
('santa-fe',        'Santa Fe',            'SFE', 'COL', 'foreign', 64, '#C8102E', '#FFFFFF'),
('platense',        'Platense',            'PLA', 'ARG', 'foreign', 62, '#6B3E26', '#FFFFFF'),
('cerro-porteno',   'Cerro Porteño',       'CER', 'PAR', 'foreign', 68, '#0A2A6B', '#C8102E'),
('junior',          'Junior Barranquilla', 'JUN', 'COL', 'foreign', 66, '#D1121F', '#FFFFFF'),
('sporting-cristal','Sporting Cristal',    'SCR', 'PER', 'foreign', 64, '#4FB3E8', '#FFFFFF'),
('ldu',             'LDU Quito',           'LDU', 'ECU', 'foreign', 72, '#1B2A6B', '#FFFFFF'),
('lanus',           'Lanús',               'LAN', 'ARG', 'foreign', 71, '#7A1126', '#FFFFFF'),
('always-ready',    'Always Ready',        'ARE', 'BOL', 'foreign', 58, '#C8102E', '#FFFFFF'),
('ind-del-valle',   'Independiente del Valle','IDV','ECU','foreign', 72, '#111111', '#1E6FD9'),
('libertad',        'Libertad',            'LIB', 'PAR', 'foreign', 66, '#111111', '#FFFFFF'),
('rosario-central', 'Rosario Central',     'ROS', 'ARG', 'foreign', 70, '#1E4FA3', '#F5C400'),
('u-central',       'Universidad Central', 'UCE', 'VEN', 'foreign', 52, '#2E7D32', '#FFFFFF')
on conflict (id) do update set
  name = excluded.name, short_name = excluded.short_name, country = excluded.country, tier = excluded.tier,
  strength = excluded.strength, color_primary = excluded.color_primary, color_secondary = excluded.color_secondary;

insert into public.sim_competitions (id, name, short_name, sort_order, xp_mult) values
  ('brasileirao',  'Brasileirão Série A', 'Brasileirão',  1, 1.00),
  ('copa_brasil',  'Copa do Brasil',      'Copa do Brasil', 2, 1.20),
  ('libertadores', 'Copa Libertadores',   'Libertadores', 3, 1.30)
on conflict (id) do update set
  name = excluded.name, short_name = excluded.short_name, sort_order = excluded.sort_order, xp_mult = excluded.xp_mult;

-- Recadastra os participantes do zero (seguro: as temporadas já criadas guardam seus próprios jogos)
delete from public.sim_competition_clubs;

-- Brasileirão Série A 2026: os 20 clubes
insert into public.sim_competition_clubs (competition_id, club_id)
select 'brasileirao', id from public.sim_clubs where tier = 'serie_a';

-- Copa do Brasil 2026 — oitavas (ida: seed 1 em casa | volta: seed 2 em casa)
insert into public.sim_competition_clubs (competition_id, club_id, group_label, seed) values
  ('copa_brasil', 'vasco',         'T1', 1), ('copa_brasil', 'fluminense',  'T1', 2),
  ('copa_brasil', 'internacional', 'T2', 1), ('copa_brasil', 'corinthians', 'T2', 2),
  ('copa_brasil', 'mirassol',      'T3', 1), ('copa_brasil', 'gremio',      'T3', 2),
  ('copa_brasil', 'athletico-pr',  'T4', 1), ('copa_brasil', 'vitoria',     'T4', 2),
  ('copa_brasil', 'atletico-mg',   'T5', 1), ('copa_brasil', 'juventude',   'T5', 2),
  ('copa_brasil', 'santos',        'T6', 1), ('copa_brasil', 'remo',        'T6', 2),
  ('copa_brasil', 'chapecoense',   'T7', 1), ('copa_brasil', 'cruzeiro',    'T7', 2),
  ('copa_brasil', 'palmeiras',     'T8', 1), ('copa_brasil', 'fortaleza',   'T8', 2);

-- Libertadores 2026 — fase de grupos (32 clubes, 8 grupos)
insert into public.sim_competition_clubs (competition_id, club_id, group_label) values
  ('libertadores','flamengo','A'),('libertadores','estudiantes','A'),('libertadores','cusco','A'),('libertadores','ind-medellin','A'),
  ('libertadores','nacional-uru','B'),('libertadores','universitario','B'),('libertadores','coquimbo','B'),('libertadores','tolima','B'),
  ('libertadores','fluminense','C'),('libertadores','bolivar','C'),('libertadores','la-guaira','C'),('libertadores','ind-rivadavia','C'),
  ('libertadores','boca-juniors','D'),('libertadores','cruzeiro','D'),('libertadores','u-catolica','D'),('libertadores','barcelona-sc','D'),
  ('libertadores','penarol','E'),('libertadores','corinthians','E'),('libertadores','santa-fe','E'),('libertadores','platense','E'),
  ('libertadores','palmeiras','F'),('libertadores','cerro-porteno','F'),('libertadores','junior','F'),('libertadores','sporting-cristal','F'),
  ('libertadores','ldu','G'),('libertadores','lanus','G'),('libertadores','always-ready','G'),('libertadores','mirassol','G'),
  ('libertadores','ind-del-valle','H'),('libertadores','libertad','H'),('libertadores','rosario-central','H'),('libertadores','u-central','H');

-- Conferência (deve mostrar: 20, 16 e 32)
select competition_id, count(*) as clubes from public.sim_competition_clubs group by 1 order by 1;
