-- MODO ONLINE — Fases 21 e 22 em um arquivo só, para o SQL Editor do Supabase.
-- Lendas que evoluem (300 novas), 100 destaques, Brasileirão no mercado e preço das lendas.
-- Rode inteiro, uma vez. Registra as migrações 20261114190000, 20261114190100 e 20261114200000.
begin;
-- MODO ONLINE — Fase 21: catálogo maior e lendas que evoluem.
--  • Lendas são lendas do futebol (em atividade ou não), não só aposentados. on_legends ganha pot: a lenda
--    evolui no treino até ele, e o pot pode passar de 100 (Messi 98 → 107). As lendas antigas ganham pot também:
--    nota + 9 (96+), + 7 (92+), + 6 (88+) ou + 5.
--  • on_catalog_extra: jogadores reais que faltavam no catálogo do jogo (sim_players), só para o modo online:
--    destaques de ligas fora do catálogo e jogadores conhecidos do Brasileirão. Se o mesmo nome aparecer em
--    sim_players, vale o de sim_players (o extra some do on_pool).
--  • Cartas base: as faixas 2, 3 e 4 preferem jogadores da Série A do Brasil (sim_clubs.tier = 'serie_a' ou
--    extra marcado br), para o Brasileirão aparecer toda hora no mercado.

alter table public.on_legends add column if not exists pot smallint;
update public.on_legends set pot=rating+case when rating>=96 then 9 when rating>=92 then 7 when rating>=88 then 6 else 5 end
 where pot is null or pot<rating;
do $$ begin
 if not exists(select 1 from pg_constraint where conname='on_legends_pot_check') then
  alter table public.on_legends add constraint on_legends_pot_check check (pot is null or pot between rating and 110);
 end if;
end $$;

create table if not exists public.on_catalog_extra(
 id text primary key check (id like 'ex-%'),
 name text not null,
 pos text not null references public.sim_positions(code),
 sec text[] not null default '{}',
 nat text not null,
 rating smallint not null check (rating between 50 and 95),
 age smallint not null check (age between 16 and 45),
 pot smallint not null,
 br boolean not null default false,
 check (pot between rating and 99)
);
alter table public.on_catalog_extra enable row level security;
revoke all on public.on_catalog_extra from anon,authenticated;

-- Catálogo do modo: reais do jogo, extras (sem repetir nome do jogo) e lendas com o pot próprio.
create or replace view public.on_pool as
 select p.id,coalesce(nullif(p.short_name,''),p.full_name) name,p.position pos,coalesce(p.secondary_positions,'{}') sec,
  coalesce(p.nationality,'BRA') nat,coalesce(b.rating,p.attr_level)::numeric rating,
  coalesce(b.age0,p.age,25)::int age,coalesce(b.potential,p.attr_level+2)::int pot,false legend
 from public.sim_players p left join public.sim_player_base b on b.player_id=p.id
 where p.career_id is null and p.active and coalesce(b.rating,p.attr_level) is not null
 union all
 select e.id,e.name,e.pos,e.sec,e.nat,e.rating::numeric,e.age::int,e.pot::int,false from public.on_catalog_extra e
 where not exists(select 1 from public.sim_players s where s.career_id is null and s.active
  and (lower(s.full_name)=lower(e.name) or lower(s.short_name)=lower(e.name)))
 union all
 select l.id,l.name,l.pos,l.sec,l.nat,l.rating::numeric,30,coalesce(l.pot,l.rating)::int,true from public.on_legends l;
revoke all on public.on_pool from anon,authenticated;

-- Jogador do Brasileirão (Série A): clube do catálogo ou extra marcado.
create or replace function public.on_is_br(p_id text) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.sim_players s join public.sim_clubs c on c.id=s.club_id where s.id=p_id and c.tier='serie_a')
  or exists(select 1 from public.on_catalog_extra e where e.id=p_id and e.br)
$$;

-- Lenda pode passar de 95 de potencial (até 110).
do $$ begin
 perform public.on_patch('public.on_real_insert(text,integer,integer,integer,boolean,integer,integer)',
  'greatest(a.lvl,least(95,p.pot))::smallint',
  'greatest(a.lvl,least(case when p.legend then 110 else 95 end,p.pot))::smallint');
end $$;

-- Carta base da faixa p_tier (1 a 5) na posição p_pos. Faixas 2, 3 e 4 preferem o Brasileirão.
create or replace function public.on_gen_base(p_seed text,p_tier int,p_pos text) returns text
language plpgsql security definer set search_path=public as $$
declare t int:=greatest(1,least(5,p_tier));
 v_lo numeric:=(array[78,75,72,66,60])[t];v_hi numeric:=(array[80.5,78,75,74,74])[t];
 v_age int:=(array[40,40,27,23,21])[t];v_gap int:=(array[0,0,0,6,10])[t];v_br boolean:=t in(2,3,4);
 v_end int:=(select max(id) from public.on_seasons)+1+floor(public.sim_hash01(p_seed||':ct')*2)::int;
 v_src text;v_id text;
begin
 select p.id into v_src from public.on_pool p
 where not p.legend and p.rating>=v_lo and p.rating<v_hi and p.age<=v_age and p.pot>=round(p.rating)+v_gap
  and not exists(select 1 from public.on_players o where o.src=p.id)
 order by case when v_br and not public.on_is_br(p.id) then 2 else 0 end+(p.pos is distinct from p_pos)::int,
  public.sim_hash01(p_seed||':'||p.id) limit 1;
 v_src:=coalesce(v_src,public.on_real_pick(p_pos,v_lo,v_hi,p_seed),public.on_real_pick(null,v_lo,v_hi,p_seed));
 if v_src is not null then
  v_id:=public.on_real_insert(v_src,null,null,v_end);
  update public.on_players set star=level>=80 where id=v_id;
  return v_id;
 end if;
 -- catálogo sem ninguém livre na faixa: jogador gerado com o mesmo perfil
 insert into public.on_players(club_id,name,pos,age,level,pot,ovr,wage,contract_end,agg,disc,star)
 select null,public.cw_regen_name('BRA',p_seed),coalesce(p_pos,'MC'),a.age,a.lvl,
  least(94,a.lvl+v_gap+floor(public.sim_hash01(p_seed||':pot')*6)::int),
  a.lvl,public.on_wage(a.lvl),v_end,35+floor(public.sim_hash01(p_seed||':agg')*40)::int,40+floor(public.sim_hash01(p_seed||':disc')*45)::int,a.lvl>=80
 from(select 18+floor(public.sim_hash01(p_seed||':age')*(least(v_age,32)-17))::int age,
  floor(v_lo+public.sim_hash01(p_seed||':lvl')*(least(v_hi,80.5)-v_lo))::int lvl) a
 returning id into v_id;
 return v_id;
end $$;

-- Lendas já contratadas passam a evoluir até o pot novo.
update public.on_players p set pot=l.pot from public.on_legends l where p.src=l.id and p.legend and p.pot<l.pot;

revoke all on function public.on_is_br(text),public.on_gen_base(text,int,text) from public,anon,authenticated;

-- MODO ONLINE — Fase 21 (dados): 300 lendas novas, 100 destaques e jogadores do Brasileirão que faltavam no catálogo.
-- Lendas: nota do auge e pot (nota + 9 a + 5); podem passar de 100 no treino. Extras: nota, idade e pot atuais aproximados.
-- Nomes conferidos contra o catálogo do jogo (data/squads, data/tier-b e seeds): nenhum repete jogador existente.
insert into public.on_legends(id,name,pos,sec,nat,rating,pot) values
('lg-lionel-messi','Lionel Messi','PD','{MEI,ATA}','ARG',98,107),
('lg-cristiano-ronaldo','Cristiano Ronaldo','ATA','{PE}','POR',97,106),
('lg-neymar-jr','Neymar Jr','PE','{MEI}','BRA',93,100),
('lg-karim-benzema','Karim Benzema','ATA','{}','FRA',92,99),
('lg-robert-lewandowski','Robert Lewandowski','ATA','{}','POL',92,99),
('lg-sergio-ramos','Sergio Ramos','ZAG','{}','ESP',91,97),
('lg-mohamed-salah','Mohamed Salah','PD','{ATA}','EGY',91,97),
('lg-arthur-friedenreich','Arthur Friedenreich','ATA','{}','BRA',91,97),
('lg-dani-alves','Dani Alves','LD','{}','BRA',90,96),
('lg-coutinho','Coutinho','ATA','{}','BRA',90,96),
('lg-domingos-da-guia','Domingos da Guia','ZAG','{}','BRA',90,96),
('lg-ademir-de-menezes','Ademir de Menezes','ATA','{}','BRA',90,96),
('lg-jose-manuel-moreno','José Manuel Moreno','ATA','{MEI}','ARG',90,96),
('lg-valentino-mazzola','Valentino Mazzola','MEI','{}','ITA',90,96),
('lg-gunnar-nordahl','Gunnar Nordahl','ATA','{}','SWE',90,96),
('lg-antoine-griezmann','Antoine Griezmann','ATA','{MEI}','FRA',89,95),
('lg-sadio-mane','Sadio Mané','PE','{ATA}','SEN',89,95),
('lg-son-heung-min','Son Heung-min','PE','{ATA}','KOR',89,95),
('lg-casemiro','Casemiro','VOL','{}','BRA',89,95),
('lg-sergio-busquets','Sergio Busquets','VOL','{}','ESP',89,95),
('lg-edinson-cavani','Edinson Cavani','ATA','{}','URU',89,95),
('lg-radamel-falcao','Radamel Falcao','ATA','{}','COL',89,95),
('lg-adolfo-pedernera','Adolfo Pedernera','ATA','{}','ARG',89,95),
('lg-angel-labruna','Ángel Labruna','ATA','{}','ARG',89,95),
('lg-jose-leandro-andrade','José Leandro Andrade','MC','{}','URU',89,95),
('lg-willem-van-hanegem','Willem van Hanegem','MC','{}','NED',89,95),
('lg-rob-rensenbrink','Rob Rensenbrink','PE','{}','NED',89,95),
('lg-bernd-schuster','Bernd Schuster','MC','{}','GER',89,95),
('lg-wolfgang-overath','Wolfgang Overath','MEI','{}','GER',89,95),
('lg-sandro-mazzola','Sandro Mazzola','ATA','{MEI}','ITA',89,95),
('lg-silvio-piola','Silvio Piola','ATA','{}','ITA',89,95),
('lg-tom-finney','Tom Finney','PD','{}','ENG',89,95),
('lg-duncan-edwards','Duncan Edwards','MC','{}','ENG',89,95),
('lg-john-charles','John Charles','ATA','{ZAG}','WAL',89,95),
('lg-dragan-dzajic','Dragan Džajić','PE','{}','SRB',89,95),
('lg-florian-albert','Flórián Albert','ATA','{}','HUN',89,95),
('lg-jozsef-bozsik','József Bozsik','MC','{}','HUN',89,95),
('lg-eduard-streltsov','Eduard Streltsov','ATA','{}','RUS',89,95),
('lg-nils-liedholm','Nils Liedholm','MC','{}','SWE',89,95),
('lg-thomas-muller','Thomas Müller','MEI','{ATA}','GER',88,94),
('lg-mats-hummels','Mats Hummels','ZAG','{}','GER',88,94),
('lg-keylor-navas','Keylor Navas','GOL','{}','CRC',88,94),
('lg-hugo-lloris','Hugo Lloris','GOL','{}','FRA',88,94),
('lg-leonardo-bonucci','Leonardo Bonucci','ZAG','{}','ITA',88,94),
('lg-paul-pogba','Paul Pogba','MC','{}','FRA',88,94),
('lg-mario-coluna','Mário Coluna','MC','{}','POR',88,94),
('lg-toninho-cerezo','Toninho Cerezo','MC','{}','BRA',88,94),
('lg-pepe-macia','Pepe Macia','PE','{}','BRA',88,94),
('lg-zito','Zito','VOL','{}','BRA',88,94),
('lg-heleno-de-freitas','Heleno de Freitas','ATA','{}','BRA',88,94),
('lg-julinho-botelho','Julinho Botelho','PD','{}','BRA',88,94),
('lg-amadeo-carrizo','Amadeo Carrizo','GOL','{}','ARG',88,94),
('lg-ladislao-mazurkiewicz','Ladislao Mazurkiewicz','GOL','{}','URU',88,94),
('lg-alcides-ghiggia','Alcides Ghiggia','PD','{}','URU',88,94),
('lg-hector-scarone','Héctor Scarone','ATA','{}','URU',88,94),
('lg-faas-wilkes','Faas Wilkes','ATA','{}','NED',88,94),
('lg-helmut-rahn','Helmut Rahn','PD','{}','GER',88,94),
('lg-gianluca-vialli','Gianluca Vialli','ATA','{}','ITA',88,94),
('lg-walter-zenga','Walter Zenga','GOL','{}','ITA',88,94),
('lg-bryan-robson','Bryan Robson','MC','{}','ENG',88,94),
('lg-dixie-dean','Dixie Dean','ATA','{}','ENG',88,94),
('lg-graeme-souness','Graeme Souness','MC','{}','SCO',88,94),
('lg-telmo-zarra','Telmo Zarra','ATA','{}','ESP',88,94),
('lg-dejan-savicevic','Dejan Savićević','MEI','{}','MNE',88,94),
('lg-zoltan-czibor','Zoltán Czibor','PE','{}','HUN',88,94),
('lg-gunnar-gren','Gunnar Gren','MEI','{}','SWE',88,94),
('lg-kurt-hamrin','Kurt Hamrin','PD','{}','SWE',88,94),
('lg-allan-simonsen','Allan Simonsen','ATA','{}','DEN',88,94),
('lg-riyad-mahrez','Riyad Mahrez','PD','{}','ALG',87,92),
('lg-jordi-alba','Jordi Alba','LE','{}','ESP',87,92),
('lg-marco-reus','Marco Reus','MEI','{PE}','GER',87,92),
('lg-jerome-boateng','Jérôme Boateng','ZAG','{}','GER',87,92),
('lg-alexis-sanchez','Alexis Sánchez','PE','{ATA}','CHI',87,92),
('lg-marco-verratti','Marco Verratti','MC','{}','ITA',87,92),
('lg-ciro-immobile','Ciro Immobile','ATA','{}','ITA',87,92),
('lg-raphael-varane','Raphaël Varane','ZAG','{}','FRA',87,92),
('lg-thiago-alcantara','Thiago Alcântara','MC','{}','ESP',87,92),
('lg-roberto-firmino','Roberto Firmino','ATA','{MEI}','BRA',87,92),
('lg-eder-aleixo','Éder Aleixo','PE','{}','BRA',87,92),
('lg-clodoaldo','Clodoaldo','VOL','{}','BRA',87,92),
('lg-jair-da-rosa-pinto','Jair da Rosa Pinto','MEI','{}','BRA',87,92),
('lg-fernando-morena','Fernando Morena','ATA','{}','URU',87,92),
('lg-abe-lenstra','Abe Lenstra','ATA','{}','NED',87,92),
('lg-pierre-littbarski','Pierre Littbarski','PD','{}','GER',87,92),
('lg-jurgen-kohler','Jürgen Kohler','ZAG','{}','GER',87,92),
('lg-berti-vogts','Berti Vogts','LD','{}','GER',87,92),
('lg-toni-schumacher','Toni Schumacher','GOL','{}','GER',87,92),
('lg-stefan-effenberg','Stefan Effenberg','MC','{}','GER',87,92),
('lg-roberto-mancini','Roberto Mancini','ATA','{MEI}','ITA',87,92),
('lg-bruno-conti','Bruno Conti','PD','{}','ITA',87,92),
('lg-giuseppe-bergomi','Giuseppe Bergomi','ZAG','{LD}','ITA',87,92),
('lg-antonio-cabrini','Antonio Cabrini','LE','{}','ITA',87,92),
('lg-claudio-gentile','Claudio Gentile','ZAG','{}','ITA',87,92),
('lg-giancarlo-antognoni','Giancarlo Antognoni','MEI','{}','ITA',87,92),
('lg-angelo-peruzzi','Angelo Peruzzi','GOL','{}','ITA',87,92),
('lg-alessandro-costacurta','Alessandro Costacurta','ZAG','{}','ITA',87,92),
('lg-glenn-hoddle','Glenn Hoddle','MEI','{}','ENG',87,92),
('lg-john-barnes','John Barnes','PE','{}','ENG',87,92),
('lg-ray-clemence','Ray Clemence','GOL','{}','ENG',87,92),
('lg-geoff-hurst','Geoff Hurst','ATA','{}','ENG',87,92),
('lg-billy-wright','Billy Wright','ZAG','{}','ENG',87,92),
('lg-billy-bremner','Billy Bremner','MC','{}','SCO',87,92),
('lg-neville-southall','Neville Southall','GOL','{}','WAL',87,92),
('lg-pat-jennings','Pat Jennings','GOL','{}','NIR',87,92),
('lg-youri-djorkaeff','Youri Djorkaeff','MEI','{}','FRA',87,92),
('lg-andoni-zubizarreta','Andoni Zubizarreta','GOL','{}','ESP',87,92),
('lg-luis-arconada','Luis Arconada','GOL','{}','ESP',87,92),
('lg-amancio-amaro','Amancio Amaro','PD','{}','ESP',87,92),
('lg-jose-angel-iribar','José Ángel Iribar','GOL','{}','ESP',87,92),
('lg-jan-ceulemans','Jan Ceulemans','MEI','{}','BEL',87,92),
('lg-michel-preudhomme','Michel Preud''homme','GOL','{}','BEL',87,92),
('lg-predrag-mijatovic','Predrag Mijatović','ATA','{}','MNE',87,92),
('lg-safet-susic','Safet Sušić','MEI','{}','BIH',87,92),
('lg-gyula-grosics','Gyula Grosics','GOL','{}','HUN',87,92),
('lg-georgi-asparuhov','Georgi Asparuhov','ATA','{}','BUL',87,92),
('lg-igor-belanov','Igor Belanov','ATA','{}','UKR',87,92),
('lg-preben-elkjr','Preben Elkjær','ATA','{}','DEN',87,92),
('lg-herbert-prohaska','Herbert Prohaska','MC','{}','AUT',87,92),
('lg-kalidou-koulibaly','Kalidou Koulibaly','ZAG','{}','SEN',87,92),
('lg-salif-keita','Salif Keïta','ATA','{}','MLI',87,92),
('lg-lorenzo-insigne','Lorenzo Insigne','PE','{}','ITA',86,91),
('lg-diego-costa','Diego Costa','ATA','{}','ESP',86,91),
('lg-santi-cazorla','Santi Cazorla','MC','{MEI}','ESP',86,91),
('lg-victor-valdes','Víctor Valdés','GOL','{}','ESP',86,91),
('lg-vitor-baia','Vítor Baía','GOL','{}','POR',86,91),
('lg-david-luiz','David Luiz','ZAG','{}','BRA',86,91),
('lg-filipe-luis','Filipe Luís','LE','{}','BRA',86,91),
('lg-branco','Branco','LE','{}','BRA',86,91),
('lg-muller','Müller','ATA','{}','BRA',86,91),
('lg-emerson-leao','Emerson Leão','GOL','{}','BRA',86,91),
('lg-paulo-cesar-caju','Paulo César Caju','PE','{}','BRA',86,91),
('lg-mauro-ramos','Mauro Ramos','ZAG','{}','BRA',86,91),
('lg-bellini','Bellini','ZAG','{}','BRA',86,91),
('lg-dirceu-lopes','Dirceu Lopes','MEI','{}','BRA',86,91),
('lg-evaristo-de-macedo','Evaristo de Macedo','ATA','{}','BRA',86,91),
('lg-danilo-alvim','Danilo Alvim','VOL','{}','BRA',86,91),
('lg-dejan-petkovic','Dejan Petković','MEI','{}','SRB',86,91),
('lg-marcelinho-carioca','Marcelinho Carioca','MEI','{}','BRA',86,91),
('lg-renato-gaucho','Renato Gaúcho','PD','{}','BRA',86,91),
('lg-mario-jardel','Mário Jardel','ATA','{}','BRA',86,91),
('lg-antonio-rattin','Antonio Rattín','VOL','{}','ARG',86,91),
('lg-norberto-alonso','Norberto Alonso','MEI','{}','ARG',86,91),
('lg-osvaldo-ardiles','Osvaldo Ardiles','MC','{}','ARG',86,91),
('lg-jorge-valdano','Jorge Valdano','ATA','{}','ARG',86,91),
('lg-ramon-diaz','Ramón Díaz','ATA','{}','ARG',86,91),
('lg-luis-cubilla','Luis Cubilla','PD','{}','URU',86,91),
('lg-carlos-caszely','Carlos Caszely','ATA','{}','CHI',86,91),
('lg-julio-cesar-romero','Julio César Romero','MEI','{}','PAR',86,91),
('lg-johnny-rep','Johnny Rep','PD','{}','NED',86,91),
('lg-arie-haan','Arie Haan','MC','{}','NED',86,91),
('lg-phillip-cocu','Phillip Cocu','MC','{}','NED',86,91),
('lg-rafael-van-der-vaart','Rafael van der Vaart','MEI','{}','NED',86,91),
('lg-sami-khedira','Sami Khedira','MC','{}','GER',86,91),
('lg-thomas-haler','Thomas Häßler','MEI','{}','GER',86,91),
('lg-andreas-kopke','Andreas Köpke','GOL','{}','GER',86,91),
('lg-jens-lehmann','Jens Lehmann','GOL','{}','GER',86,91),
('lg-uli-hoene','Uli Hoeneß','MC','{}','GER',86,91),
('lg-franco-causio','Franco Causio','PD','{}','ITA',86,91),
('lg-gianluca-pagliuca','Gianluca Pagliuca','GOL','{}','ITA',86,91),
('lg-francesco-toldo','Francesco Toldo','GOL','{}','ITA',86,91),
('lg-demetrio-albertini','Demetrio Albertini','MC','{}','ITA',86,91),
('lg-roberto-donadoni','Roberto Donadoni','PD','{}','ITA',86,91),
('lg-pietro-vierchowod','Pietro Vierchowod','ZAG','{}','ITA',86,91),
('lg-ciro-ferrara','Ciro Ferrara','ZAG','{}','ITA',86,91),
('lg-mauro-tassotti','Mauro Tassotti','LD','{}','ITA',86,91),
('lg-antonio-di-natale','Antonio Di Natale','ATA','{}','ITA',86,91),
('lg-peter-beardsley','Peter Beardsley','MEI','{}','ENG',86,91),
('lg-martin-peters','Martin Peters','MC','{}','ENG',86,91),
('lg-ian-wright','Ian Wright','ATA','{}','ENG',86,91),
('lg-robbie-fowler','Robbie Fowler','ATA','{}','ENG',86,91),
('lg-paul-mcgrath','Paul McGrath','ZAG','{}','IRL',86,91),
('lg-liam-brady','Liam Brady','MC','{}','IRL',86,91),
('lg-danny-blanchflower','Danny Blanchflower','MC','{}','NIR',86,91),
('lg-nicolas-anelka','Nicolas Anelka','ATA','{}','FRA',86,91),
('lg-patrice-evra','Patrice Evra','LE','{}','FRA',86,91),
('lg-manuel-amoros','Manuel Amoros','LD','{}','FRA',86,91),
('lg-maxime-bossis','Maxime Bossis','ZAG','{}','FRA',86,91),
('lg-marius-tresor','Marius Trésor','ZAG','{}','FRA',86,91),
('lg-luis-fernandez','Luis Fernández','VOL','{}','FRA',86,91),
('lg-jose-antonio-camacho','José Antonio Camacho','LE','{}','ESP',86,91),
('lg-rafael-gordillo','Rafael Gordillo','LE','{}','ESP',86,91),
('lg-michel-gonzalez','Míchel González','PD','{}','ESP',86,91),
('lg-carlos-santillana','Carlos Santillana','ATA','{}','ESP',86,91),
('lg-juanito','Juanito','PD','{}','ESP',86,91),
('lg-eric-gerets','Eric Gerets','LD','{}','BEL',86,91),
('lg-sinisa-mihajlovic','Siniša Mihajlović','ZAG','{LE}','SRB',86,91),
('lg-miralem-pjanic','Miralem Pjanić','MC','{}','BIH',86,91),
('lg-wodzimierz-lubanski','Włodzimierz Lubański','ATA','{}','POL',86,91),
('lg-antonin-panenka','Antonín Panenka','MEI','{}','CZE',86,91),
('lg-ivo-viktor','Ivo Viktor','GOL','{}','CZE',86,91),
('lg-krasimir-balakov','Krasimir Balakov','MEI','{}','BUL',86,91),
('lg-valentin-ivanov','Valentin Ivanov','ATA','{}','RUS',86,91),
('lg-albert-shesternyov','Albert Shesternyov','ZAG','{}','RUS',86,91),
('lg-morten-olsen','Morten Olsen','ZAG','{}','DEN',86,91),
('lg-bruno-pezzey','Bruno Pezzey','ZAG','{}','AUT',86,91),
('lg-lefter-kucukandonyadis','Lefter Küçükandonyadis','ATA','{}','TUR',86,91),
('lg-thomas-nkono','Thomas N''Kono','GOL','{}','CMR',86,91),
('lg-laurent-pokou','Laurent Pokou','ATA','{}','CIV',86,91),
('lg-lakhdar-belloumi','Lakhdar Belloumi','MEI','{}','ALG',86,91),
('lg-mahmoud-el-khatib','Mahmoud El Khatib','ATA','{}','EGY',86,91),
('lg-kunishige-kamamoto','Kunishige Kamamoto','ATA','{}','JPN',86,91),
('lg-dimitri-payet','Dimitri Payet','MEI','{}','FRA',85,90),
('lg-juan-mata','Juan Mata','MEI','{}','ESP',85,90),
('lg-fernando-couto','Fernando Couto','ZAG','{}','POR',85,90),
('lg-pauleta','Pauleta','ATA','{}','POR',85,90),
('lg-jose-aguas','José Águas','ATA','{}','POR',85,90),
('lg-fernando-chalana','Fernando Chalana','PE','{}','POR',85,90),
('lg-humberto-coelho','Humberto Coelho','ZAG','{}','POR',85,90),
('lg-joao-pinto','João Pinto','MEI','{}','POR',85,90),
('lg-willian','Willian','PD','{}','BRA',85,90),
('lg-douglas-costa','Douglas Costa','PE','{}','BRA',85,90),
('lg-alexandre-pato','Alexandre Pato','ATA','{}','BRA',85,90),
('lg-jorginho-putinatti','Jorginho Putinatti','LD','{}','BRA',85,90),
('lg-zinho','Zinho','MEI','{}','BRA',85,90),
('lg-ricardo-rocha','Ricardo Rocha','ZAG','{}','BRA',85,90),
('lg-wilson-piazza','Wilson Piazza','ZAG','{VOL}','BRA',85,90),
('lg-castilho','Castilho','GOL','{}','BRA',85,90),
('lg-canhoteiro','Canhoteiro','PE','{}','BRA',85,90),
('lg-moacir-barbosa','Moacir Barbosa','GOL','{}','BRA',85,90),
('lg-bauer','Bauer','VOL','{}','BRA',85,90),
('lg-emerson-ferreira','Emerson Ferreira','VOL','{}','BRA',85,90),
('lg-edilson','Edílson','ATA','{}','BRA',85,90),
('lg-dario-conca','Darío Conca','MEI','{}','ARG',85,90),
('lg-andres-dalessandro','Andrés D''Alessandro','MEI','{}','ARG',85,90),
('lg-evair','Evair','ATA','{}','BRA',85,90),
('lg-ricardo-gomes','Ricardo Gomes','ZAG','{}','BRA',85,90),
('lg-carlos-mozer','Carlos Mozer','ZAG','{}','BRA',85,90),
('lg-juan-pablo-sorin','Juan Pablo Sorín','LE','{}','ARG',85,90),
('lg-daniel-bertoni','Daniel Bertoni','PD','{}','ARG',85,90),
('lg-leopoldo-luque','Leopoldo Luque','ATA','{}','ARG',85,90),
('lg-sergio-goycochea','Sergio Goycochea','GOL','{}','ARG',85,90),
('lg-ruben-sosa','Rubén Sosa','ATA','{}','URU',85,90),
('lg-ruben-paz','Rubén Paz','MEI','{}','URU',85,90),
('lg-hector-castro','Héctor Castro','ATA','{}','URU',85,90),
('lg-willington-ortiz','Willington Ortiz','PD','{}','COL',85,90),
('lg-andres-escobar','Andrés Escobar','ZAG','{}','COL',85,90),
('lg-hugo-sotil','Hugo Sotil','ATA','{}','PER',85,90),
('lg-cesar-cueto','César Cueto','MEI','{}','PER',85,90),
('lg-wim-suurbier','Wim Suurbier','LD','{}','NED',85,90),
('lg-ronald-de-boer','Ronald de Boer','MEI','{}','NED',85,90),
('lg-giovanni-van-bronckhorst','Giovanni van Bronckhorst','LE','{}','NED',85,90),
('lg-mark-van-bommel','Mark van Bommel','VOL','{}','NED',85,90),
('lg-horst-hrubesch','Horst Hrubesch','ATA','{}','GER',85,90),
('lg-klaus-allofs','Klaus Allofs','ATA','{}','GER',85,90),
('lg-oliver-bierhoff','Oliver Bierhoff','ATA','{}','GER',85,90),
('lg-mehmet-scholl','Mehmet Scholl','MEI','{}','GER',85,90),
('lg-torsten-frings','Torsten Frings','VOL','{}','GER',85,90),
('lg-lukas-podolski','Lukas Podolski','PE','{}','GER',85,90),
('lg-antonio-cassano','Antonio Cassano','ATA','{}','ITA',85,90),
('lg-raheem-sterling','Raheem Sterling','PE','{}','ENG',85,90),
('lg-jamie-carragher','Jamie Carragher','ZAG','{}','ENG',85,90),
('lg-gary-neville','Gary Neville','LD','{}','ENG',85,90),
('lg-chris-waddle','Chris Waddle','PD','{}','ENG',85,90),
('lg-teddy-sheringham','Teddy Sheringham','ATA','{}','ENG',85,90),
('lg-stuart-pearce','Stuart Pearce','LE','{}','ENG',85,90),
('lg-nobby-stiles','Nobby Stiles','VOL','{}','ENG',85,90),
('lg-jack-charlton','Jack Charlton','ZAG','{}','ENG',85,90),
('lg-trevor-francis','Trevor Francis','ATA','{}','ENG',85,90),
('lg-michael-carrick','Michael Carrick','MC','{}','ENG',85,90),
('lg-matt-le-tissier','Matt Le Tissier','MEI','{}','ENG',85,90),
('lg-jim-baxter','Jim Baxter','MC','{}','SCO',85,90),
('lg-mark-hughes','Mark Hughes','ATA','{}','WAL',85,90),
('lg-emmanuel-petit','Emmanuel Petit','MC','{}','FRA',85,90),
('lg-william-gallas','William Gallas','ZAG','{}','FRA',85,90),
('lg-samir-nasri','Samir Nasri','MEI','{}','FRA',85,90),
('lg-dominique-rocheteau','Dominique Rocheteau','PD','{}','FRA',85,90),
('lg-gaizka-mendieta','Gaizka Mendieta','MC','{}','ESP',85,90),
('lg-quini','Quini','ATA','{}','ESP',85,90),
('lg-guti','Guti','MEI','{}','ESP',85,90),
('lg-dries-mertens','Dries Mertens','ATA','{PE}','BEL',85,90),
('lg-jan-vertonghen','Jan Vertonghen','ZAG','{}','BEL',85,90),
('lg-toby-alderweireld','Toby Alderweireld','ZAG','{}','BEL',85,90),
('lg-alen-boksic','Alen Bokšić','ATA','{}','CRO',85,90),
('lg-branislav-ivanovic','Branislav Ivanović','LD','{ZAG}','SRB',85,90),
('lg-jan-tomaszewski','Jan Tomaszewski','GOL','{}','POL',85,90),
('lg-karel-poborsky','Karel Poborský','PD','{}','CZE',85,90),
('lg-lajos-detari','Lajos Détári','MEI','{}','HUN',85,90),
('lg-gheorghe-popescu','Gheorghe Popescu','ZAG','{VOL}','ROU',85,90),
('lg-adrian-mutu','Adrian Mutu','ATA','{}','ROU',85,90),
('lg-cristian-chivu','Cristian Chivu','ZAG','{LE}','ROU',85,90),
('lg-serhiy-rebrov','Serhiy Rebrov','ATA','{}','UKR',85,90),
('lg-aleksandr-mostovoi','Aleksandr Mostovoi','MEI','{}','RUS',85,90),
('lg-igor-akinfeev','Igor Akinfeev','GOL','{}','RUS',85,90),
('lg-tomas-brolin','Tomas Brolin','MEI','{}','SWE',85,90),
('lg-toni-polster','Toni Polster','ATA','{}','AUT',85,90),
('lg-andreas-herzog','Andreas Herzog','MEI','{}','AUT',85,90),
('lg-arda-turan','Arda Turan','MEI','{}','TUR',85,90),
('lg-emmanuel-adebayor','Emmanuel Adebayor','ATA','{}','TOG',85,90),
('lg-rashidi-yekini','Rashidi Yekini','ATA','{}','NGA',85,90),
('lg-mohamed-timoumi','Mohamed Timoumi','MEI','{}','MAR',85,90),
('lg-noureddine-naybet','Noureddine Naybet','ZAG','{}','MAR',85,90),
('lg-badou-zaki','Badou Zaki','GOL','{}','MAR',85,90),
('lg-tony-yeboah','Tony Yeboah','ATA','{}','GHA',85,90),
('lg-kalusha-bwalya','Kalusha Bwalya','MEI','{}','ZAM',85,90),
('lg-hong-myung-bo','Hong Myung-bo','ZAG','{}','KOR',85,90),
('lg-shinji-kagawa','Shinji Kagawa','MEI','{}','JPN',85,90),
('lg-majed-abdullah','Majed Abdullah','ATA','{}','KSA',85,90),
('lg-blaise-matuidi','Blaise Matuidi','MC','{}','FRA',84,89),
('lg-javier-hernandez','Javier Hernández','ATA','{}','MEX',84,89),
('lg-carlos-vela','Carlos Vela','PD','{}','MEX',84,89)
on conflict(id) do update set name=excluded.name,pos=excluded.pos,sec=excluded.sec,nat=excluded.nat,rating=excluded.rating,pot=excluded.pot;

-- br = jogador conhecido do Brasileirão (entra na preferência das cartas base).
insert into public.on_catalog_extra(id,name,pos,sec,nat,rating,age,pot,br) values
('ex-ruben-neves','Rúben Neves','MC','{VOL}','POR',84,29,84,false),
('ex-sergej-milinkovic-savic','Sergej Milinković-Savić','MC','{MEI}','SRB',85,31,85,false),
('ex-malcom','Malcom','PD','{}','BRA',83,29,83,false),
('ex-aleksandar-mitrovic','Aleksandar Mitrović','ATA','{}','SRB',84,32,84,false),
('ex-yassine-bounou','Yassine Bounou','GOL','{}','MAR',86,35,86,false),
('ex-theo-hernandez','Theo Hernández','LE','{}','FRA',86,29,86,false),
('ex-darwin-nunez','Darwin Núñez','ATA','{}','URU',83,27,85,false),
('ex-kingsley-coman','Kingsley Coman','PE','{PD}','FRA',84,30,84,false),
('ex-joao-felix','João Félix','MEI','{ATA}','POR',83,27,85,false),
('ex-inigo-martinez','Iñigo Martínez','ZAG','{}','ESP',83,35,83,false),
('ex-marcelo-brozovic','Marcelo Brozović','VOL','{}','CRO',84,33,84,false),
('ex-fabinho-tavares','Fabinho Tavares','VOL','{}','BRA',82,33,82,false),
('ex-houssem-aouar','Houssem Aouar','MC','{}','ALG',81,28,81,false),
('ex-steven-bergwijn','Steven Bergwijn','PE','{}','NED',81,29,81,false),
('ex-ivan-toney','Ivan Toney','ATA','{}','ENG',84,30,84,false),
('ex-edouard-mendy','Édouard Mendy','GOL','{}','SEN',83,34,83,false),
('ex-merih-demiral','Merih Demiral','ZAG','{}','TUR',82,28,82,false),
('ex-galeno','Galeno','PE','{}','BRA',82,28,82,false),
('ex-enzo-millot','Enzo Millot','MEI','{}','FRA',81,24,85,false),
('ex-nahitan-nandez','Nahitan Nández','MC','{LD}','URU',81,30,81,false),
('ex-rodrigo-de-paul','Rodrigo De Paul','MC','{}','ARG',84,32,84,false),
('ex-roger-ibanez','Roger Ibañez','ZAG','{}','BRA',82,27,84,false),
('ex-matteo-retegui','Matteo Retegui','ATA','{}','ITA',82,27,84,false),
('ex-marcos-leonardo','Marcos Leonardo','ATA','{}','BRA',81,23,85,false),
('ex-mohamed-simakan','Mohamed Simakan','ZAG','{}','FRA',82,26,84,false),
('ex-ederson-moraes','Ederson Moraes','GOL','{}','BRA',86,33,86,false),
('ex-dusan-vlahovic','Dušan Vlahović','ATA','{}','SRB',84,26,86,false),
('ex-tijjani-reijnders','Tijjani Reijnders','MC','{}','NED',85,28,85,false),
('ex-julian-brandt','Julian Brandt','MEI','{}','GER',83,30,83,false),
('ex-marc-andre-ter-stegen','Marc-André ter Stegen','GOL','{}','GER',87,34,87,false),
('ex-gabriel-martinelli','Gabriel Martinelli','PE','{}','BRA',84,25,86,false),
('ex-ollie-watkins','Ollie Watkins','ATA','{}','ENG',85,30,85,false),
('ex-romelu-lukaku','Romelu Lukaku','ATA','{}','BEL',84,33,84,false),
('ex-mason-greenwood','Mason Greenwood','PD','{}','ENG',84,25,86,false),
('ex-alexandre-lacazette','Alexandre Lacazette','ATA','{}','FRA',82,35,82,false),
('ex-viktor-tsygankov','Viktor Tsygankov','PD','{}','UKR',81,28,81,false),
('ex-salem-al-dawsari','Salem Al-Dawsari','PE','{}','KSA',82,34,82,false),
('ex-bento-krepski','Bento Krepski','GOL','{}','BRA',81,26,83,false),
('ex-wesley-gassova','Wesley Gassova','PE','{}','BRA',81,21,88,false),
('ex-youssef-en-nesyri','Youssef En-Nesyri','ATA','{}','MAR',82,29,82,false),
('ex-koen-casteels','Koen Casteels','GOL','{}','BEL',81,34,81,false),
('ex-yannick-carrasco','Yannick Carrasco','PE','{}','BEL',82,33,82,false),
('ex-said-benrahma','Saïd Benrahma','PE','{}','ALG',81,31,81,false),
('ex-roger-martinez','Roger Martínez','ATA','{}','COL',81,32,81,false),
('ex-moussa-dembele','Moussa Dembélé','ATA','{}','FRA',81,30,81,false),
('ex-ahmed-hegazi','Ahmed Hegazi','ZAG','{}','EGY',81,35,81,false),
('ex-riqui-puig','Riqui Puig','MC','{}','ESP',81,27,83,false),
('ex-hirving-lozano','Hirving Lozano','PD','{}','MEX',82,31,82,false),
('ex-emil-forsberg','Emil Forsberg','MEI','{}','SWE',81,35,81,false),
('ex-evander-ferreira','Evander Ferreira','MEI','{}','BRA',81,28,81,false),
('ex-denis-bouanga','Denis Bouanga','PE','{}','GAB',82,31,82,false),
('ex-anders-dreyer','Anders Dreyer','PD','{}','DEN',81,28,81,false),
('ex-kevin-denkey','Kévin Denkey','ATA','{}','TOG',81,25,83,false),
('ex-lucas-ocampos','Lucas Ocampos','PD','{}','ARG',81,32,81,false),
('ex-german-berterame','Germán Berterame','ATA','{}','MEX',81,28,81,false),
('ex-juan-brunetta','Juan Brunetta','MEI','{}','ARG',81,29,81,false),
('ex-allan-saint-maximin','Allan Saint-Maximin','PE','{}','FRA',81,29,81,false),
('ex-orkun-kokcu','Orkun Kökçü','MC','{}','TUR',83,26,85,false),
('ex-wilfred-ndidi','Wilfred Ndidi','VOL','{}','NGA',81,30,81,false),
('ex-paul-onuachu','Paul Onuachu','ATA','{}','NGA',81,33,81,false),
('ex-callum-mcgregor','Callum McGregor','MC','{}','SCO',81,33,81,false),
('ex-cameron-carter-vickers','Cameron Carter-Vickers','ZAG','{}','USA',81,28,81,false),
('ex-kasper-schmeichel','Kasper Schmeichel','GOL','{}','DEN',81,40,81,false),
('ex-maximilian-arnold','Maximilian Arnold','MC','{}','GER',81,32,81,false),
('ex-ayoub-el-kaabi','Ayoub El Kaabi','ATA','{}','MAR',82,33,82,false),
('ex-daniel-podence','Daniel Podence','PE','{}','POR',81,30,81,false),
('ex-gelson-martins','Gelson Martins','PD','{}','POR',81,31,81,false),
('ex-steven-berghuis','Steven Berghuis','MEI','{}','NED',81,34,81,false),
('ex-paulo-gazzaniga','Paulo Gazzaniga','GOL','{}','ARG',81,34,81,false),
('ex-alexis-vega','Alexis Vega','PE','{}','MEX',81,29,81,false),
('ex-jesus-corona','Jesús Corona','PD','{}','MEX',81,33,81,false),
('ex-gonzalo-plata','Gonzalo Plata','PD','{}','ECU',81,25,83,false),
('ex-giacomo-bonaventura','Giacomo Bonaventura','MC','{}','ITA',81,37,81,false),
('ex-akram-afif','Akram Afif','PE','{}','QAT',82,29,82,false),
('ex-roger-guedes','Roger Guedes','PE','{}','BRA',81,30,81,false),
('ex-joselu','Joselu','ATA','{}','ESP',81,36,81,false),
('ex-rafa-mujica','Rafa Mújica','ATA','{}','ESP',81,27,83,false),
('ex-hany-mukhtar','Hany Mukhtar','MEI','{}','GER',81,31,81,false),
('ex-tadeo-allende','Tadeo Allende','PD','{}','ARG',81,27,83,false),
('ex-ryan-gauld','Ryan Gauld','MEI','{}','SCO',81,30,81,false),
('ex-rodrigo-aguirre','Rodrigo Aguirre','ATA','{}','URU',81,31,81,false),
('ex-helinho','Helinho','PD','{}','BRA',81,26,83,false),
('ex-brian-rodriguez','Brian Rodríguez','PE','{}','URU',81,26,83,false),
('ex-nicolas-ibanez','Nicolás Ibáñez','ATA','{}','ARG',81,31,81,false),
('ex-guido-pizarro','Guido Pizarro','VOL','{}','ARG',81,36,81,false),
('ex-luis-malagon','Luis Malagón','GOL','{}','MEX',81,29,81,false),
('ex-krzysztof-piatek','Krzysztof Piątek','ATA','{}','POL',81,31,81,false),
('ex-arne-engels','Arne Engels','MC','{}','BEL',81,23,85,false),
('ex-james-tavernier','James Tavernier','LD','{}','ENG',81,34,81,false),
('ex-vaclav-cerny','Václav Černý','PD','{}','CZE',81,28,81,false),
('ex-cyriel-dessers','Cyriel Dessers','ATA','{}','NGA',81,31,81,false),
('ex-douglas-santos','Douglas Santos','LE','{}','BRA',81,32,81,false),
('ex-eduard-spertsyan','Eduard Spertsyan','MEI','{}','ARM',82,26,84,false),
('ex-manfred-ugalde','Manfred Ugalde','ATA','{}','CRC',81,24,85,false),
('ex-aleksei-batrakov','Aleksei Batrakov','MEI','{}','RUS',81,20,88,false),
('ex-joakim-mhle','Joakim Mæhle','LE','{}','DEN',81,29,81,false),
('ex-andrija-zivkovic','Andrija Živković','PD','{}','SRB',81,30,81,false),
('ex-sergi-darder','Sergi Darder','MC','{}','ESP',81,32,81,false),
('ex-wendel','Wendel','MC','{}','BRA',81,28,81,false),
('ex-andrey-mostovoy','Andrey Mostovoy','PE','{}','RUS',81,28,81,false),
('ex-raphael-veiga','Raphael Veiga','MEI','{}','BRA',78,31,78,true),
('ex-facundo-torres','Facundo Torres','PE','{}','URU',78,26,80,true),
('ex-arthur-melo','Arthur Melo','MC','{}','BRA',76,30,76,true),
('ex-rafael-borre','Rafael Borré','ATA','{}','COL',76,31,76,true),
('ex-junior-alonso','Junior Alonso','ZAG','{}','PAR',76,33,76,true),
('ex-lucas-halter','Lucas Halter','ZAG','{}','BRA',73,26,75,true),
('ex-jeffinho','Jeffinho','PE','{}','BRA',72,26,74,true),
('ex-gregore','Gregore','VOL','{}','BRA',74,31,74,true),
('ex-adryelson','Adryelson','ZAG','{}','BRA',73,28,73,true),
('ex-tomas-rincon','Tomás Rincón','VOL','{}','VEN',72,38,72,true),
('ex-lucas-mugni','Lucas Mugni','MEI','{}','ARG',71,34,71,true),
('ex-luighi','Luighi','ATA','{}','BRA',70,20,77,true),
('ex-ferreirinha','Ferreirinha','PE','{}','BRA',73,28,73,true),
('ex-matheus-goncalves','Matheus Gonçalves','PD','{}','BRA',71,20,78,true),
('ex-wellington-rato','Wellington Rato','PD','{}','BRA',72,33,72,true),
('ex-ricardo-mathias','Ricardo Mathias','ATA','{}','BRA',72,22,76,true),
('ex-hugo-moura','Hugo Moura','VOL','{}','BRA',74,28,74,true),
('ex-cristian-olivera','Cristian Olivera','PE','{}','URU',76,24,80,true),
('ex-santiago-ramos-mingo','Santiago Ramos Mingo','ZAG','{}','ARG',74,24,78,true),
('ex-raniel','Raniel','ATA','{}','BRA',71,29,71,true),
('ex-nathan-fernandes','Nathan Fernandes','PD','{}','BRA',71,21,78,true),
('ex-thiago-galhardo','Thiago Galhardo','ATA','{}','BRA',72,36,72,true),
('ex-erison','Erison','ATA','{}','BRA',71,26,73,true),
('ex-renzo-saravia','Renzo Saravia','LD','{}','ARG',72,32,72,true),
('ex-gustavo-mosquito','Gustavo Mosquito','PD','{}','BRA',71,28,71,true),
('ex-giuliano-galoppo','Giuliano Galoppo','MEI','{}','ARG',73,26,75,true),
('ex-igor-coronado','Igor Coronado','MEI','{}','BRA',71,33,71,true),
('ex-mastriani','Mastriani','ATA','{}','URU',72,32,72,true),
('ex-bruno-tabata','Bruno Tabata','MEI','{}','BRA',71,28,71,true),
('ex-jonathan-copete','Jonathan Copete','PE','{}','COL',70,38,70,true),
('ex-rodrigo-caio','Rodrigo Caio','ZAG','{}','BRA',72,32,72,true),
('ex-gabriel-veron','Gabriel Veron','PD','{}','BRA',71,23,75,true),
('ex-kevin-kelsy','Kevin Kelsy','ATA','{}','VEN',72,21,79,true),
('ex-jhon-jhon','Jhon Jhon','MEI','{}','BRA',73,23,77,true),
('ex-lincoln','Lincoln','MEI','{}','BRA',71,25,73,true),
('ex-kaiky-fernandes','Kaiky Fernandes','ZAG','{}','BRA',71,22,75,true),
('ex-ivan-cavaleiro','Ivan Cavaleiro','PD','{}','POR',71,32,71,true),
('ex-talles-magno','Talles Magno','PE','{}','BRA',73,23,77,true),
('ex-bitello','Bitello','MC','{}','BRA',72,25,74,true),
('ex-alan-ruiz','Alan Ruiz','MEI','{}','ARG',70,32,70,true),
('ex-thiago-heleno','Thiago Heleno','ZAG','{}','BRA',70,37,70,true),
('ex-bruno-mendez','Bruno Méndez','LD','{}','URU',73,26,75,true),
('ex-renato-augusto','Renato Augusto','MC','{}','BRA',72,38,72,true),
('ex-giuliano','Giuliano','MEI','{}','BRA',71,36,71,true),
('ex-raul-gustavo','Raul Gustavo','ZAG','{}','BRA',70,26,72,true),
('ex-mateus-vital','Mateus Vital','MEI','{}','BRA',71,28,71,true),
('ex-gustavo-mantuan','Gustavo Mantuan','LD','{}','BRA',71,25,73,true),
('ex-leo-natel','Léo Natel','PE','{}','BRA',69,29,69,true),
('ex-ramiro','Ramiro','MC','{}','BRA',70,32,70,true),
('ex-jean-pyerre','Jean Pyerre','MEI','{}','BRA',70,28,70,true),
('ex-everton-galdino','Everton Galdino','PE','{}','BRA',69,29,69,true),
('ex-rodrigo-dourado','Rodrigo Dourado','VOL','{}','BRA',70,31,70,true),
('ex-taison','Taison','PE','{}','BRA',70,38,70,true)
on conflict(id) do update set name=excluded.name,pos=excluded.pos,sec=excluded.sec,nat=excluded.nat,rating=excluded.rating,age=excluded.age,pot=excluded.pot,br=excluded.br;

-- MODO ONLINE — Fase 22: lendas caras, e a lenda que passa de 100 é raridade.
-- Lance inicial (a moeda vale $ 1 no lance; um técnico bom junta uns $ 0,5–1 milhão por temporada):
--  • lenda com potencial acima de 100: $ 5 milhões + $ 500 mil por ponto acima de 101 (Messi, pot 107: $ 8 milhões);
--  • demais lendas: $ 800 mil + $ 120 mil por ponto de nota acima de 80 (84: $ 1,28 milhão; 93: $ 2,36 milhões);
--  • destaque (81+) e comum seguem iguais.
-- Leilões já abertos mantêm o preço com que foram criados.
create or replace function public.on_start_price(p public.on_players) returns bigint
language sql immutable set search_path=public as $$
 select case when p.legend and p.pot>100 then 5000000+(p.pot-101)*500000
  when p.legend then 800000+greatest(0,p.level-80)*120000
  when p.level>=81 then 400000+(p.level-80)*40000
  else greatest(500,round(public.on_value(p.ovr,p.age,p.pot)*.4)) end::bigint
$$;

insert into supabase_migrations.schema_migrations(version,name) values
 ('20261114190000','online_phase21_catalog_expansion'),('20261114190100','online_phase21_catalog_data'),('20261114200000','online_phase22_legend_prices')
 on conflict do nothing;
commit;
