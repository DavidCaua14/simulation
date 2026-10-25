-- =====================================================================
-- CARTAS AUTOMÁTICAS — gerado por scripts/build-auto-cards.mjs (não edite à mão)
-- Épica 50 · Destaque 200 · Básica 300 (atletas atuais) · Lenda 100 (aposentados)
-- Rode no Supabase (SQL Editor) depois de supabase/manager (precisa de sim_players).
-- =====================================================================
begin;

-- 1) remove as cartas manuais antigas (e as cópias nas coleções)
delete from public.user_cards where card_id in ('arrascaeta-78', 'arrascaeta-86', 'arrascaeta-92', 'arrascaeta-98', 'gabriel-86', 'juninho-96', 'ribamar-58', 'igor-bahia-51', 'flavio-caca-rato-51');
delete from public.cards where id in ('arrascaeta-78', 'arrascaeta-86', 'arrascaeta-92', 'arrascaeta-98', 'gabriel-86', 'juninho-96', 'ribamar-58', 'igor-bahia-51', 'flavio-caca-rato-51');

-- 2) atletas atuais: épica = maiores overalls, destaque = os seguintes, básica = espalhadas entre os clubes
create temp table _pick on commit drop as
with base as (
  select p.id, p.short_name, p.full_name, p.position, p.club_id, p.nationality, p.shirt_number,
         round(r.eff)::int as ovr, c.name as club_name
    from public.sim_players p
    join public.sim_player_pos_ratings r on r.player_id = p.id and r.pos = p.position
    join public.sim_clubs c on c.id = p.club_id
   where p.active
), ranked as (
  select b.*, row_number() over (order by b.ovr desc, b.id) as rk from base b
), top as (
  select r.*, case when r.rk <= 50 then 'epica' else 'destaque' end as tier
    from ranked r where r.rk <= 250
), rest as (
  select r.*, row_number() over (partition by r.club_id order by r.ovr desc, r.id) as club_rk
    from ranked r where r.rk > 250
), basic as (
  select x.*, 'basica' as tier from (select * from rest order by club_rk, ovr desc, id limit 300) x
)
select id, short_name, full_name, position, club_id, nationality, shirt_number, ovr, club_name, tier from top
union all
select id, short_name, full_name, position, club_id, nationality, shirt_number, ovr, club_name, tier from basic;

insert into public.cards (id, name, tier, overall, position, club_id, player_key, image, weight, active, meta)
select tier || '-' || id, short_name, tier, ovr, position, club_id, id, 'auto', 100, true,
       jsonb_build_object('kind', 'atual', 'full_name', full_name, 'nationality', nationality, 'number', shirt_number,
                          'club_name', club_name, 'estimated', true, 'season', 2026)
  from _pick
on conflict (id) do update set name = excluded.name, tier = excluded.tier, overall = excluded.overall, position = excluded.position,
  club_id = excluded.club_id, player_key = excluded.player_key, image = excluded.image, active = true, meta = excluded.meta;

-- cartas automáticas de atletas que saíram da seleção param de cair (quem já tem, continua tendo)
update public.cards set active = false
 where image = 'auto' and meta ->> 'kind' = 'atual' and id not in (select tier || '-' || id from _pick);

-- 3) lendas (aposentados)
insert into public.cards (id, name, tier, overall, position, club_id, player_key, image, weight, active, meta)
select v.id, v.name, 'lenda', v.ovr, v.pos, v.club, v.pkey, 'auto', 100, true, v.meta
  from (values
  ('lenda-pele', 'Pelé', 99, 'ATA', 'santos', 'pele', '{"kind":"lenda","nationality":"BRA","club_name":"Santos","estimated":true}'::jsonb),
  ('lenda-diego-maradona', 'Diego Maradona', 98, 'MEI', 'boca-juniors', 'diego-maradona', '{"kind":"lenda","nationality":"ARG","club_name":"Boca Juniors","estimated":true}'::jsonb),
  ('lenda-garrincha', 'Garrincha', 97, 'PD', 'botafogo', 'garrincha', '{"kind":"lenda","nationality":"BRA","club_name":"Botafogo","estimated":true}'::jsonb),
  ('lenda-ronaldo', 'Ronaldo', 97, 'ATA', 'cruzeiro', 'ronaldo', '{"kind":"lenda","nationality":"BRA","club_name":"Cruzeiro","estimated":true}'::jsonb),
  ('lenda-alfredo-di-stefano', 'Alfredo Di Stéfano', 96, 'ATA', null, 'alfredo-di-stefano', '{"kind":"lenda","nationality":"ARG","club_name":"River Plate","estimated":true}'::jsonb),
  ('lenda-zico', 'Zico', 96, 'MEI', 'flamengo', 'zico', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-romario', 'Romário', 96, 'ATA', 'vasco', 'romario', '{"kind":"lenda","nationality":"BRA","club_name":"Vasco da Gama","estimated":true}'::jsonb),
  ('lenda-ronaldinho', 'Ronaldinho', 95, 'MEI', 'atletico-mg', 'ronaldinho', '{"kind":"lenda","nationality":"BRA","club_name":"Atlético-MG","estimated":true}'::jsonb),
  ('lenda-rivaldo', 'Rivaldo', 93, 'MEI', 'palmeiras', 'rivaldo', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-kaka', 'Kaká', 93, 'MEI', 'sao-paulo', 'kaka', '{"kind":"lenda","nationality":"BRA","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-cafu', 'Cafu', 93, 'LD', 'sao-paulo', 'cafu', '{"kind":"lenda","nationality":"BRA","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-socrates', 'Sócrates', 93, 'MEI', 'corinthians', 'socrates', '{"kind":"lenda","nationality":"BRA","club_name":"Corinthians","estimated":true}'::jsonb),
  ('lenda-didi', 'Didi', 92, 'MEI', 'botafogo', 'didi', '{"kind":"lenda","nationality":"BRA","club_name":"Botafogo","estimated":true}'::jsonb),
  ('lenda-rivellino', 'Rivellino', 92, 'MEI', 'corinthians', 'rivellino', '{"kind":"lenda","nationality":"BRA","club_name":"Corinthians","estimated":true}'::jsonb),
  ('lenda-falcao', 'Falcão', 92, 'VOL', 'internacional', 'falcao', '{"kind":"lenda","nationality":"BRA","club_name":"Internacional","estimated":true}'::jsonb),
  ('lenda-roberto-carlos', 'Roberto Carlos', 92, 'LE', 'palmeiras', 'roberto-carlos', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-carlos-alberto-torres', 'Carlos Alberto Torres', 92, 'LD', 'santos', 'carlos-alberto-torres', '{"kind":"lenda","nationality":"BRA","club_name":"Santos","estimated":true}'::jsonb),
  ('lenda-jairzinho', 'Jairzinho', 92, 'PD', 'botafogo', 'jairzinho', '{"kind":"lenda","nationality":"BRA","club_name":"Botafogo","estimated":true}'::jsonb),
  ('lenda-juan-roman-riquelme', 'Juan Román Riquelme', 92, 'MEI', 'boca-juniors', 'juan-roman-riquelme', '{"kind":"lenda","nationality":"ARG","club_name":"Boca Juniors","estimated":true}'::jsonb),
  ('lenda-gabriel-batistuta', 'Gabriel Batistuta', 92, 'ATA', 'boca-juniors', 'gabriel-batistuta', '{"kind":"lenda","nationality":"ARG","club_name":"Boca Juniors","estimated":true}'::jsonb),
  ('lenda-nilton-santos', 'Nílton Santos', 91, 'LE', 'botafogo', 'nilton-santos', '{"kind":"lenda","nationality":"BRA","club_name":"Botafogo","estimated":true}'::jsonb),
  ('lenda-tostao', 'Tostão', 91, 'ATA', 'cruzeiro', 'tostao', '{"kind":"lenda","nationality":"BRA","club_name":"Cruzeiro","estimated":true}'::jsonb),
  ('lenda-gerson', 'Gérson', 91, 'MC', 'botafogo', 'gerson', '{"kind":"lenda","nationality":"BRA","club_name":"Botafogo","estimated":true}'::jsonb),
  ('lenda-roberto-dinamite', 'Roberto Dinamite', 91, 'ATA', 'vasco', 'roberto-dinamite', '{"kind":"lenda","nationality":"BRA","club_name":"Vasco da Gama","estimated":true}'::jsonb),
  ('lenda-elias-figueroa', 'Elías Figueroa', 91, 'ZAG', 'internacional', 'elias-figueroa', '{"kind":"lenda","nationality":"CHI","club_name":"Internacional","estimated":true}'::jsonb),
  ('lenda-mario-kempes', 'Mario Kempes', 91, 'ATA', 'rosario-central', 'mario-kempes', '{"kind":"lenda","nationality":"ARG","club_name":"Rosario Central","estimated":true}'::jsonb),
  ('lenda-junior', 'Júnior', 90, 'LE', 'flamengo', 'junior', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-rogerio-ceni', 'Rogério Ceni', 90, 'GOL', 'sao-paulo', 'rogerio-ceni', '{"kind":"lenda","nationality":"BRA","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-ademir-da-guia', 'Ademir da Guia', 90, 'MEI', 'palmeiras', 'ademir-da-guia', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-juninho-pernambucano', 'Juninho Pernambucano', 90, 'MEI', 'vasco', 'juninho-pernambucano', '{"kind":"lenda","nationality":"BRA","club_name":"Vasco da Gama","estimated":true}'::jsonb),
  ('lenda-bebeto', 'Bebeto', 90, 'ATA', 'flamengo', 'bebeto', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-careca', 'Careca', 90, 'ATA', 'sao-paulo', 'careca', '{"kind":"lenda","nationality":"BRA","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-leonidas-da-silva', 'Leônidas da Silva', 90, 'ATA', 'flamengo', 'leonidas-da-silva', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-ademir-de-menezes', 'Ademir de Menezes', 90, 'ATA', 'vasco', 'ademir-de-menezes', '{"kind":"lenda","nationality":"BRA","club_name":"Vasco da Gama","estimated":true}'::jsonb),
  ('lenda-daniel-passarella', 'Daniel Passarella', 90, 'ZAG', null, 'daniel-passarella', '{"kind":"lenda","nationality":"ARG","club_name":"River Plate","estimated":true}'::jsonb),
  ('lenda-alberto-spencer', 'Alberto Spencer', 90, 'ATA', 'penarol', 'alberto-spencer', '{"kind":"lenda","nationality":"ECU","club_name":"Peñarol","estimated":true}'::jsonb),
  ('lenda-enzo-francescoli', 'Enzo Francescoli', 90, 'MEI', null, 'enzo-francescoli', '{"kind":"lenda","nationality":"URU","club_name":"River Plate","estimated":true}'::jsonb),
  ('lenda-djalma-santos', 'Djalma Santos', 89, 'LD', 'palmeiras', 'djalma-santos', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-marcos', 'Marcos', 89, 'GOL', 'palmeiras', 'marcos', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-rai', 'Raí', 89, 'MEI', 'sao-paulo', 'rai', '{"kind":"lenda","nationality":"BRA","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-alex', 'Alex', 89, 'MEI', 'palmeiras', 'alex', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-reinaldo', 'Reinaldo', 89, 'ATA', 'atletico-mg', 'reinaldo', '{"kind":"lenda","nationality":"BRA","club_name":"Atlético-MG","estimated":true}'::jsonb),
  ('lenda-adriano', 'Adriano', 89, 'ATA', 'flamengo', 'adriano', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-renato-gaucho', 'Renato Gaúcho', 89, 'PD', 'gremio', 'renato-gaucho', '{"kind":"lenda","nationality":"BRA","club_name":"Grêmio","estimated":true}'::jsonb),
  ('lenda-marcelo', 'Marcelo', 89, 'LE', 'fluminense', 'marcelo', '{"kind":"lenda","nationality":"BRA","club_name":"Fluminense","estimated":true}'::jsonb),
  ('lenda-obdulio-varela', 'Obdulio Varela', 89, 'VOL', 'penarol', 'obdulio-varela', '{"kind":"lenda","nationality":"URU","club_name":"Peñarol","estimated":true}'::jsonb),
  ('lenda-javier-zanetti', 'Javier Zanetti', 89, 'LD', null, 'javier-zanetti', '{"kind":"lenda","nationality":"ARG","club_name":"Banfield","estimated":true}'::jsonb),
  ('lenda-carlos-valderrama', 'Carlos Valderrama', 89, 'MEI', null, 'carlos-valderrama', '{"kind":"lenda","nationality":"COL","club_name":"Junior Barranquilla","estimated":true}'::jsonb),
  ('lenda-teofilo-cubillas', 'Teófilo Cubillas', 89, 'MEI', null, 'teofilo-cubillas', '{"kind":"lenda","nationality":"PER","club_name":"Alianza Lima","estimated":true}'::jsonb),
  ('lenda-hernan-crespo', 'Hernán Crespo', 89, 'ATA', null, 'hernan-crespo', '{"kind":"lenda","nationality":"ARG","club_name":"River Plate","estimated":true}'::jsonb),
  ('lenda-carlos-tevez', 'Carlos Tevez', 89, 'ATA', 'boca-juniors', 'carlos-tevez', '{"kind":"lenda","nationality":"ARG","club_name":"Boca Juniors","estimated":true}'::jsonb),
  ('lenda-ricardo-bochini', 'Ricardo Bochini', 89, 'MEI', null, 'ricardo-bochini', '{"kind":"lenda","nationality":"ARG","club_name":"Independiente","estimated":true}'::jsonb),
  ('lenda-taffarel', 'Taffarel', 88, 'GOL', 'internacional', 'taffarel', '{"kind":"lenda","nationality":"BRA","club_name":"Internacional","estimated":true}'::jsonb),
  ('lenda-gilmar-dos-santos-neves', 'Gilmar dos Santos Neves', 88, 'GOL', 'santos', 'gilmar-dos-santos-neves', '{"kind":"lenda","nationality":"BRA","club_name":"Santos","estimated":true}'::jsonb),
  ('lenda-julio-cesar', 'Júlio César', 88, 'GOL', 'flamengo', 'julio-cesar', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-leandro', 'Leandro', 88, 'LD', 'flamengo', 'leandro', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-aldair', 'Aldair', 88, 'ZAG', 'flamengo', 'aldair', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-dunga', 'Dunga', 88, 'VOL', 'internacional', 'dunga', '{"kind":"lenda","nationality":"BRA","club_name":"Internacional","estimated":true}'::jsonb),
  ('lenda-toninho-cerezo', 'Toninho Cerezo', 88, 'VOL', 'atletico-mg', 'toninho-cerezo', '{"kind":"lenda","nationality":"BRA","club_name":"Atlético-MG","estimated":true}'::jsonb),
  ('lenda-zito', 'Zito', 88, 'VOL', 'santos', 'zito', '{"kind":"lenda","nationality":"BRA","club_name":"Santos","estimated":true}'::jsonb),
  ('lenda-dirceu-lopes', 'Dirceu Lopes', 88, 'MEI', 'cruzeiro', 'dirceu-lopes', '{"kind":"lenda","nationality":"BRA","club_name":"Cruzeiro","estimated":true}'::jsonb),
  ('lenda-edmundo', 'Edmundo', 88, 'ATA', 'vasco', 'edmundo', '{"kind":"lenda","nationality":"BRA","club_name":"Vasco da Gama","estimated":true}'::jsonb),
  ('lenda-vava', 'Vavá', 88, 'ATA', 'vasco', 'vava', '{"kind":"lenda","nationality":"BRA","club_name":"Vasco da Gama","estimated":true}'::jsonb),
  ('lenda-coutinho', 'Coutinho', 88, 'ATA', 'santos', 'coutinho', '{"kind":"lenda","nationality":"BRA","club_name":"Santos","estimated":true}'::jsonb),
  ('lenda-arthur-friedenreich', 'Arthur Friedenreich', 88, 'ATA', null, 'arthur-friedenreich', '{"kind":"lenda","nationality":"BRA","club_name":"Paulistano","estimated":true}'::jsonb),
  ('lenda-juan-sebastian-veron', 'Juan Sebastián Verón', 88, 'MC', 'estudiantes', 'juan-sebastian-veron', '{"kind":"lenda","nationality":"ARG","club_name":"Estudiantes","estimated":true}'::jsonb),
  ('lenda-fernando-redondo', 'Fernando Redondo', 88, 'VOL', null, 'fernando-redondo', '{"kind":"lenda","nationality":"ARG","club_name":"Argentinos Juniors","estimated":true}'::jsonb),
  ('lenda-martin-palermo', 'Martín Palermo', 88, 'ATA', 'boca-juniors', 'martin-palermo', '{"kind":"lenda","nationality":"ARG","club_name":"Boca Juniors","estimated":true}'::jsonb),
  ('lenda-fernando-morena', 'Fernando Morena', 88, 'ATA', 'penarol', 'fernando-morena', '{"kind":"lenda","nationality":"URU","club_name":"Peñarol","estimated":true}'::jsonb),
  ('lenda-diego-forlan', 'Diego Forlán', 88, 'ATA', 'penarol', 'diego-forlan', '{"kind":"lenda","nationality":"URU","club_name":"Peñarol","estimated":true}'::jsonb),
  ('lenda-ivan-zamorano', 'Iván Zamorano', 88, 'ATA', null, 'ivan-zamorano', '{"kind":"lenda","nationality":"CHI","club_name":"Cobresal","estimated":true}'::jsonb),
  ('lenda-marcelo-salas', 'Marcelo Salas', 88, 'ATA', null, 'marcelo-salas', '{"kind":"lenda","nationality":"CHI","club_name":"Universidad de Chile","estimated":true}'::jsonb),
  ('lenda-clodoaldo', 'Clodoaldo', 87, 'VOL', 'santos', 'clodoaldo', '{"kind":"lenda","nationality":"BRA","club_name":"Santos","estimated":true}'::jsonb),
  ('lenda-domingos-da-guia', 'Domingos da Guia', 87, 'ZAG', 'flamengo', 'domingos-da-guia', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-dida', 'Dida', 87, 'GOL', 'cruzeiro', 'dida', '{"kind":"lenda","nationality":"BRA","club_name":"Cruzeiro","estimated":true}'::jsonb),
  ('lenda-pepe', 'Pepe', 87, 'PE', 'santos', 'pepe', '{"kind":"lenda","nationality":"BRA","club_name":"Santos","estimated":true}'::jsonb),
  ('lenda-marcelinho-carioca', 'Marcelinho Carioca', 87, 'MEI', 'corinthians', 'marcelinho-carioca', '{"kind":"lenda","nationality":"BRA","club_name":"Corinthians","estimated":true}'::jsonb),
  ('lenda-ze-roberto', 'Zé Roberto', 87, 'LE', 'palmeiras', 'ze-roberto', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-muller', 'Müller', 87, 'ATA', 'sao-paulo', 'muller', '{"kind":"lenda","nationality":"BRA","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-luis-fabiano', 'Luís Fabiano', 87, 'ATA', 'sao-paulo', 'luis-fabiano', '{"kind":"lenda","nationality":"BRA","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-jose-luis-chilavert', 'José Luis Chilavert', 87, 'GOL', null, 'jose-luis-chilavert', '{"kind":"lenda","nationality":"PAR","club_name":"Vélez Sarsfield","estimated":true}'::jsonb),
  ('lenda-marco-etcheverry', 'Marco Etcheverry', 87, 'MEI', 'bolivar', 'marco-etcheverry', '{"kind":"lenda","nationality":"BOL","club_name":"Bolívar","estimated":true}'::jsonb),
  ('lenda-claudio-pizarro', 'Claudio Pizarro', 87, 'ATA', null, 'claudio-pizarro', '{"kind":"lenda","nationality":"PER","club_name":"Alianza Lima","estimated":true}'::jsonb),
  ('lenda-bellini', 'Bellini', 86, 'ZAG', 'vasco', 'bellini', '{"kind":"lenda","nationality":"BRA","club_name":"Vasco da Gama","estimated":true}'::jsonb),
  ('lenda-emerson-leao', 'Emerson Leão', 86, 'GOL', 'palmeiras', 'emerson-leao', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-juan', 'Juan', 86, 'ZAG', 'flamengo', 'juan', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-andrade', 'Andrade', 86, 'VOL', 'flamengo', 'andrade', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-mauro-silva', 'Mauro Silva', 86, 'VOL', 'bragantino', 'mauro-silva', '{"kind":"lenda","nationality":"BRA","club_name":"Red Bull Bragantino","estimated":true}'::jsonb),
  ('lenda-djalminha', 'Djalminha', 86, 'MEI', 'palmeiras', 'djalminha', '{"kind":"lenda","nationality":"BRA","club_name":"Palmeiras","estimated":true}'::jsonb),
  ('lenda-diego-ribas', 'Diego Ribas', 86, 'MEI', 'flamengo', 'diego-ribas', '{"kind":"lenda","nationality":"BRA","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-jardel', 'Jardel', 86, 'ATA', 'gremio', 'jardel', '{"kind":"lenda","nationality":"BRA","club_name":"Grêmio","estimated":true}'::jsonb),
  ('lenda-fred', 'Fred', 86, 'ATA', 'fluminense', 'fred', '{"kind":"lenda","nationality":"BRA","club_name":"Fluminense","estimated":true}'::jsonb),
  ('lenda-eder-aleixo', 'Éder Aleixo', 86, 'PE', 'atletico-mg', 'eder-aleixo', '{"kind":"lenda","nationality":"BRA","club_name":"Atlético-MG","estimated":true}'::jsonb),
  ('lenda-dejan-petkovic', 'Dejan Petković', 86, 'MEI', 'flamengo', 'dejan-petkovic', '{"kind":"lenda","nationality":"SRB","club_name":"Flamengo","estimated":true}'::jsonb),
  ('lenda-diego-lugano', 'Diego Lugano', 86, 'ZAG', 'sao-paulo', 'diego-lugano', '{"kind":"lenda","nationality":"URU","club_name":"São Paulo","estimated":true}'::jsonb),
  ('lenda-carlos-gamarra', 'Carlos Gamarra', 86, 'ZAG', 'corinthians', 'carlos-gamarra', '{"kind":"lenda","nationality":"PAR","club_name":"Corinthians","estimated":true}'::jsonb),
  ('lenda-oscar-ruggeri', 'Oscar Ruggeri', 86, 'ZAG', 'boca-juniors', 'oscar-ruggeri', '{"kind":"lenda","nationality":"ARG","club_name":"Boca Juniors","estimated":true}'::jsonb),
  ('lenda-juan-pablo-sorin', 'Juan Pablo Sorín', 86, 'LE', 'cruzeiro', 'juan-pablo-sorin', '{"kind":"lenda","nationality":"ARG","club_name":"Cruzeiro","estimated":true}'::jsonb),
  ('lenda-andres-d-alessandro', 'Andrés D''Alessandro', 86, 'MEI', 'internacional', 'andres-d-alessandro', '{"kind":"lenda","nationality":"ARG","club_name":"Internacional","estimated":true}'::jsonb),
  ('lenda-marcos-senna', 'Marcos Senna', 85, 'VOL', null, 'marcos-senna', '{"kind":"lenda","nationality":"ESP","club_name":"Villarreal","estimated":true}'::jsonb)
  ) as v(id, name, ovr, pos, club, pkey, meta)
on conflict (id) do update set name = excluded.name, tier = excluded.tier, overall = excluded.overall, position = excluded.position,
  club_id = excluded.club_id, player_key = excluded.player_key, image = excluded.image, active = true, meta = excluded.meta;

-- 4) caixa diária: todo dia, 1 caixa Destaque garantida (sem sorteio)
update public.box_sources set draws = 0, guaranteed = '{destaque}' where source = 'daily';

commit;

select tier, count(*) filter (where active) as ativas from public.cards group by tier order by tier;
