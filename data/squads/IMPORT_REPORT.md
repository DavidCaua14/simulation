# Relatório de importação dos elencos

Gerado por `node scripts/build-squads.mjs` em 2026-10-25.

- **Clubes com elenco:** 141 de 141
- **Jogadores importados:** 4245
- **Posição detalhada estimada** (fonte só informava GOL/DEF/MEI/ATA): 3445
- **Conflitos resolvidos** (jogador em duas listas): 30

> **Atributos:** são uma *estimativa de gameplay*, não estatísticas oficiais. Método: v1: força do clube (sim_clubs.strength) + papel no elenco (camisa/capitão/base) + perfil da posição + variação determinística por jogador.
> Para curar um jogador, edite os atributos em `sim_player_attrs` e marque `estimated = false` — a importação não sobrescreve.

## Clubes

| Clube | Jogadores | GOL/DEF/MEI/ATA | Pos. estimadas | Data do elenco | Fonte |
|---|---:|---|---:|---|---|
| AEK Atenas | 30 | 4/8/10/8 | 0 | 2026-09-02 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_AEK_Athens_F.C._season) |
| Always Ready | 24 | 3/8/8/5 | 21 | 2026-03-14 | [link](https://en.wikipedia.org/wiki/Club_Always_Ready) |
| América-MG | 36 | 4/13/9/10 | 32 | desconhecida | [link](https://en.wikipedia.org/wiki/Am%C3%A9rica_Futebol_Clube_(MG)) |
| Arsenal | 23 | 3/9/6/5 | 20 | 2026-09-15 | [link](https://en.wikipedia.org/wiki/Arsenal_F.C.) |
| Aston Villa | 26 | 2/8/10/6 | 24 | 2026-08-30 | [link](https://en.wikipedia.org/wiki/Aston_Villa_F.C.) |
| Athletic | 36 | 5/11/13/7 | 31 | 2026-10-25 | [link](https://www.sofascore.com/pt/time/futebol/athletic-club/342775) |
| Athletico-PR | 38 | 5/14/9/10 | 33 | 2026-09-22 | [link](https://en.wikipedia.org/wiki/Club_Athletico_Paranaense) |
| Atlético-GO | 34 | 4/10/11/9 | 30 | 2026-09-12 | [link](https://en.wikipedia.org/wiki/Atl%C3%A9tico_Clube_Goianiense) |
| Atlético de Madrid | 24 | 3/6/11/4 | 21 | 2026-09-02 | [link](https://en.wikipedia.org/wiki/Atl%C3%A9tico_Madrid) |
| Atlético-MG | 33 | 4/9/14/6 | 29 | 2026-08-17 | [link](https://en.wikipedia.org/wiki/2026_Clube_Atl%C3%A9tico_Mineiro_season) |
| Avaí | 34 | 4/12/11/7 | 30 | 2026-04-15 | [link](https://en.wikipedia.org/wiki/Ava%C3%AD_FC) |
| Bahia | 40 | 5/10/13/12 | 35 | 2026-09-22 | [link](https://en.wikipedia.org/wiki/Esporte_Clube_Bahia) |
| Barcelona | 24 | 3/8/8/5 | 21 | 2026-08-29 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_FC_Barcelona_season) |
| Barcelona SC | 31 | 3/9/7/12 | 28 | 2026-09-26 | [link](https://en.wikipedia.org/wiki/Barcelona_S.C.) |
| Bayern de Munique | 30 | 4/10/9/7 | 26 | 2026-10-13 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_FC_Bayern_Munich_season) |
| Real Betis | 24 | 1/8/9/6 | 23 | desconhecida | [link](https://en.wikipedia.org/wiki/Real_Betis) |
| Birmingham City | 28 | 3/8/11/6 | 25 | desconhecida | [link](https://en.wikipedia.org/wiki/Birmingham_City_F.C.) |
| Blackburn Rovers | 34 | 4/13/10/7 | 30 | 2026-05-19 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Blackburn_Rovers_F.C._season) |
| Boca Juniors | 30 | 4/7/13/6 | 26 | 2026-08-18 | [link](https://en.wikipedia.org/wiki/Boca_Juniors) |
| Bodø/Glimt | 25 | 3/7/8/7 | 22 | desconhecida | [link](https://en.wikipedia.org/wiki/FK_Bod%C3%B8/Glimt) |
| Bolívar | 29 | 3/9/11/6 | 26 | 2026-02-13 | [link](https://en.wikipedia.org/wiki/Club_Bol%C3%ADvar) |
| Bolton Wanderers | 26 | 4/8/6/8 | 22 | 2026-09-19 | [link](https://en.wikipedia.org/wiki/Bolton_Wanderers_F.C.) |
| Botafogo | 51 | 5/18/17/11 | 46 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/botafogo-2x94b2pn1o1tb5l1bbu8x9yu9/) |
| Botafogo-SP | 31 | 4/12/8/7 | 27 | 2026-04-15 | [link](https://en.wikipedia.org/wiki/Botafogo_Futebol_Clube_(SP)) |
| Bournemouth | 28 | 3/10/8/7 | 25 | 2026-09-08 | [link](https://en.wikipedia.org/wiki/AFC_Bournemouth) |
| Red Bull Bragantino | 45 | 5/13/18/9 | 40 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/bragantino-4ayjm36vlnc5j8jhwpsdwxuph/) |
| Brentford | 29 | 3/10/9/7 | 26 | 2026-08-21 | [link](https://en.wikipedia.org/wiki/Brentford_F.C.) |
| Brighton | 30 | 3/10/12/5 | 27 | desconhecida | [link](https://en.wikipedia.org/wiki/Brighton_%26_Hove_Albion_F.C.) |
| Bristol City | 29 | 3/10/11/5 | 26 | 2026-09-03 | [link](https://en.wikipedia.org/wiki/Bristol_City_F.C.) |
| Burnley | 27 | 2/8/6/11 | 25 | 2026-09-06 | [link](https://en.wikipedia.org/wiki/Burnley_F.C.) |
| Cardiff City | 26 | 3/10/9/4 | 23 | 2026-09-19 | [link](https://en.wikipedia.org/wiki/Cardiff_City_F.C.) |
| Ceará | 25 | 4/10/7/4 | 21 | 2026-06-18 | [link](https://en.wikipedia.org/wiki/Cear%C3%A1_Sporting_Club) |
| Cerro Porteño | 30 | 1/11/9/9 | 29 | 2026-06-27 | [link](https://en.wikipedia.org/wiki/Cerro_Porte%C3%B1o) |
| Chapecoense | 38 | 5/13/10/10 | 33 | 2026-05-26 | [link](https://en.wikipedia.org/wiki/Associa%C3%A7%C3%A3o_Chapecoense_de_Futebol) |
| Charlton Athletic | 31 | 3/11/10/7 | 28 | desconhecida | [link](https://en.wikipedia.org/wiki/Charlton_Athletic_F.C.) |
| Chelsea | 30 | 4/11/8/7 | 0 | 2026-10-10 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Chelsea_F.C._season) |
| Club Brugge | 27 | 3/8/9/7 | 24 | 2026-08-31 | [link](https://en.wikipedia.org/wiki/Club_Brugge_KV) |
| Como | 21 | 2/7/8/4 | 19 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/Como_1907) |
| Coquimbo Unido | 37 | 5/10/10/12 | 32 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/coquimbo-bw2py3aiws1rq61pokete3kv2/) |
| Corinthians | 33 | 2/11/13/7 | 31 | 2026-08-11 | [link](https://en.wikipedia.org/wiki/2026_SC_Corinthians_Paulista_season) |
| Coritiba | 35 | 4/10/9/12 | 31 | 2026-09-11 | [link](https://en.wikipedia.org/wiki/Coritiba_Foot_Ball_Club) |
| Coventry City | 29 | 3/10/7/9 | 26 | 2026-09-16 | [link](https://en.wikipedia.org/wiki/Coventry_City_F.C.) |
| CRB | 25 | 4/9/5/7 | 21 | desconhecida | [link](https://en.wikipedia.org/wiki/Clube_de_Regatas_Brasil) |
| Criciúma | 31 | 4/11/7/9 | 27 | 2026-09-22 | [link](https://en.wikipedia.org/wiki/Crici%C3%BAma_Esporte_Clube) |
| Cruzeiro | 34 | 5/9/7/13 | 29 | 2026-08-06 | [link](https://en.wikipedia.org/wiki/2026_Cruzeiro_Esporte_Clube_season) |
| Crystal Palace | 28 | 3/10/6/9 | 25 | 2026-09-04 | [link](https://en.wikipedia.org/wiki/Crystal_Palace_F.C.) |
| Cuiabá | 25 | 2/10/4/9 | 23 | 2026-04-15 | [link](https://en.wikipedia.org/wiki/Cuiab%C3%A1_Esporte_Clube) |
| Cusco FC | 25 | 4/7/8/6 | 21 | 2026-03-16 | [link](https://en.wikipedia.org/wiki/Cusco_FC) |
| Derby County | 30 | 4/9/10/7 | 26 | desconhecida | [link](https://en.wikipedia.org/wiki/Derby_County_F.C.) |
| Borussia Dortmund | 30 | 4/10/12/4 | 26 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Borussia_Dortmund_season) |
| Estudiantes | 30 | 3/10/8/9 | 27 | 2026-09-15 | [link](https://en.wikipedia.org/wiki/Estudiantes_de_La_Plata) |
| Everton | 24 | 3/7/8/6 | 21 | 2026-08-14 | [link](https://en.wikipedia.org/wiki/Everton_F.C.) |
| Fenerbahçe | 32 | 4/12/10/6 | 28 | 2026-05-17 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Fenerbah%C3%A7e_S.K._season) |
| Feyenoord | 30 | 4/11/8/7 | 26 | 2026-10-10 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Feyenoord_season) |
| Flamengo | 26 | 3/9/8/6 | 0 | 2026-08-30 | [link](https://en.wikipedia.org/wiki/2026_CR_Flamengo_season) |
| Fluminense | 30 | 3/11/8/8 | 27 | 2026-09-22 | [link](https://en.wikipedia.org/wiki/Fluminense_FC) |
| Fortaleza | 37 | 3/13/10/11 | 34 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/fortaleza-1vvaya787s5wg5geudzacya7m/) |
| Fulham | 27 | 3/8/11/5 | 24 | 2026-09-02 | [link](https://en.wikipedia.org/wiki/Fulham_F.C.) |
| Galatasaray | 32 | 5/10/10/7 | 27 | desconhecida | [link](https://en.wikipedia.org/wiki/Galatasaray_S.K._(football)) |
| Goiás | 27 | 4/8/8/7 | 23 | 2026-09-06 | [link](https://en.wikipedia.org/wiki/Goi%C3%A1s_Esporte_Clube) |
| Grêmio | 36 | 4/13/10/9 | 0 | 2026-10-07 | [link](https://en.wikipedia.org/wiki/2026_Gr%C3%AAmio_FBPA_season) |
| Hull City | 32 | 3/10/12/7 | 0 | desconhecida | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Hull_City_A.F.C._season) |
| Independiente del Valle | 29 | 3/10/8/8 | 26 | 2026-08-16 | [link](https://en.wikipedia.org/wiki/Independiente_del_Valle) |
| Independiente Medellín | 30 | 3/6/10/11 | 27 | desconhecida | [link](https://en.wikipedia.org/wiki/Independiente_Medell%C3%ADn) |
| Independiente Rivadavia | 28 | 3/9/10/6 | 25 | 2026-03-05 | [link](https://en.wikipedia.org/wiki/Independiente_Rivadavia) |
| Inter de Milão | 24 | 3/8/8/5 | 0 | 2026-09-05 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Inter_Milan_season) |
| Internacional | 45 | 4/17/13/11 | 41 | 2026-07-25 | [link](https://en.wikipedia.org/wiki/2026_Sport_Club_Internacional_season) |
| Ipswich Town | 28 | 4/7/6/11 | 24 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/Ipswich_Town_F.C.) |
| Junior Barranquilla | 28 | 2/9/7/10 | 26 | desconhecida | [link](https://en.wikipedia.org/wiki/Atl%C3%A9tico_Junior) |
| Juventude | 38 | 4/15/10/9 | 34 | 2026-09-23 | [link](https://en.wikipedia.org/wiki/Esporte_Clube_Juventude) |
| Deportivo La Guaira | 39 | 3/15/11/10 | 36 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/deportivo-la-guaira-em31nnti82q57le3wp7g5lsrj/) |
| Lanús | 29 | 2/10/10/7 | 27 | 2026-09-19 | [link](https://en.wikipedia.org/wiki/Club_Atl%C3%A9tico_Lan%C3%BAs) |
| LASK | 25 | 3/10/6/6 | 22 | 2026-09-02 | [link](https://en.wikipedia.org/wiki/LASK) |
| LDU Quito | 36 | 5/8/17/6 | 31 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/ldu-quito-cxb4hqite921i36gwrezdts7c/) |
| Leeds United | 23 | 3/7/8/5 | 20 | 2026-08-29 | [link](https://en.wikipedia.org/wiki/Leeds_United_F.C.) |
| RB Leipzig | 30 | 3/9/10/8 | 27 | 2026-09-03 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_RB_Leipzig_season) |
| Lens | 26 | 4/11/7/4 | 22 | desconhecida | [link](https://en.wikipedia.org/wiki/RC_Lens) |
| Libertad | 38 | 3/14/16/5 | 35 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/libertad-984ibdjplnlwb36kt6wbgwe97/) |
| Lille | 27 | 3/9/5/10 | 24 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/Lille_OSC) |
| Lincoln City | 28 | 3/11/6/8 | 25 | 2026-08-30 | [link](https://en.wikipedia.org/wiki/Lincoln_City_F.C.) |
| Liverpool | 31 | 6/10/9/6 | 25 | 2026-07-01 | [link](https://en.wikipedia.org/wiki/Liverpool_F.C.) |
| Londrina | 35 | 5/11/10/9 | 30 | 2026-04-15 | [link](https://en.wikipedia.org/wiki/Londrina_Esporte_Clube) |
| Manchester City | 25 | 3/9/8/5 | 22 | desconhecida | [link](https://en.wikipedia.org/wiki/Manchester_City_F.C.) |
| Manchester United | 30 | 4/10/9/7 | 26 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/Manchester_United_F.C.) |
| Middlesbrough | 27 | 2/10/10/5 | 25 | 2026-08-30 | [link](https://en.wikipedia.org/wiki/Middlesbrough_F.C.) |
| Millwall | 32 | 5/9/9/9 | 27 | 2026-09-02 | [link](https://en.wikipedia.org/wiki/Millwall_F.C.) |
| Mirassol | 31 | 4/10/8/9 | 27 | 2026-08-13 | [link](https://en.wikipedia.org/wiki/Mirassol_Futebol_Clube) |
| Nacional | 28 | 3/9/8/8 | 25 | 2026-09-30 | [link](https://en.wikipedia.org/wiki/Club_Nacional_de_Football) |
| Napoli | 26 | 3/10/7/6 | 23 | 2026-08-23 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_SSC_Napoli_season) |
| Náutico | 28 | 3/10/9/6 | 25 | desconhecida | [link](https://en.wikipedia.org/wiki/Clube_N%C3%A1utico_Capibaribe) |
| Newcastle United | 25 | 4/7/7/7 | 21 | desconhecida | [link](https://en.wikipedia.org/wiki/Newcastle_United_F.C.) |
| Norwich City | 35 | 4/10/15/6 | 31 | 2026-08-19 | [link](https://en.wikipedia.org/wiki/Norwich_City_F.C.) |
| Nottingham Forest | 24 | 3/9/6/6 | 0 | 2026-09-12 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Nottingham_Forest_F.C._season) |
| Novorizontino | 36 | 5/11/10/10 | 31 | desconhecida | [link](https://en.wikipedia.org/wiki/Gr%C3%AAmio_Novorizontino) |
| Operário-PR | 27 | 3/8/9/7 | 24 | desconhecida | [link](https://en.wikipedia.org/wiki/Oper%C3%A1rio_Ferrovi%C3%A1rio_Esporte_Clube) |
| Palmeiras | 25 | 3/10/8/4 | 22 | 2026-08-31 | [link](https://en.wikipedia.org/wiki/2026_SE_Palmeiras_season) |
| Peñarol | 31 | 3/12/12/4 | 28 | 2026-02-23 | [link](https://en.wikipedia.org/wiki/Pe%C3%B1arol) |
| Platense | 35 | 3/10/10/12 | 32 | 2026-03-06 | [link](https://en.wikipedia.org/wiki/Club_Atl%C3%A9tico_Platense) |
| Ponte Preta | 33 | 3/12/8/10 | 30 | 2026-06-07 | [link](https://en.wikipedia.org/wiki/Associa%C3%A7%C3%A3o_Atl%C3%A9tica_Ponte_Preta) |
| Porto | 29 | 4/10/7/8 | 25 | desconhecida | [link](https://en.wikipedia.org/wiki/FC_Porto) |
| Portsmouth | 31 | 3/8/7/13 | 28 | desconhecida | [link](https://en.wikipedia.org/wiki/Portsmouth_F.C.) |
| Preston North End | 24 | 2/10/8/4 | 22 | 2026-08-29 | [link](https://en.wikipedia.org/wiki/Preston_North_End_F.C.) |
| Paris Saint-Germain | 24 | 3/8/6/7 | 0 | 2026-09-04 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Paris_Saint-Germain_FC_season) |
| PSV Eindhoven | 29 | 3/9/8/9 | 26 | desconhecida | [link](https://en.wikipedia.org/wiki/PSV_Eindhoven) |
| Queens Park Rangers | 27 | 3/9/10/5 | 24 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/Queens_Park_Rangers_F.C.) |
| Real Madrid | 26 | 2/10/7/7 | 24 | 2026-09-02 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Real_Madrid_CF_season) |
| Remo | 35 | 3/11/11/10 | 32 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/2026_Clube_do_Remo_season) |
| Roma | 25 | 4/10/6/5 | 0 | 2026-10-11 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_AS_Roma_season) |
| Rosario Central | 35 | 4/15/11/5 | 31 | 2026-02-24 | [link](https://en.wikipedia.org/wiki/Rosario_Central) |
| Sabah | 31 | 3/9/15/4 | 28 | 2026-09-19 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_Sabah_FC_season) |
| Santa Fe | 32 | 4/11/10/7 | 28 | desconhecida | [link](https://en.wikipedia.org/wiki/Independiente_Santa_Fe) |
| Santos | 40 | 5/11/13/11 | 0 | 2026-10-08 | [link](https://en.wikipedia.org/wiki/2026_Santos_FC_season) |
| São Bernardo | 37 | 4/11/11/11 | 20 | 2026-10-25 | [link](https://www.saobernardofc.com/elenco.php) |
| São Paulo | 38 | 5/14/9/10 | 33 | 2026-09-17 | [link](https://en.wikipedia.org/wiki/S%C3%A3o_Paulo_FC) |
| Shakhtar Donetsk | 31 | 3/9/10/9 | 28 | desconhecida | [link](https://en.wikipedia.org/wiki/FC_Shakhtar_Donetsk) |
| Sheffield United | 30 | 3/12/8/7 | 27 | 2026-09-06 | [link](https://en.wikipedia.org/wiki/Sheffield_United_F.C.) |
| Slavia Praga | 29 | 4/10/10/5 | 25 | 2026-09-04 | [link](https://en.wikipedia.org/wiki/SK_Slavia_Prague) |
| Slovan Bratislava | 31 | 3/8/9/11 | 28 | desconhecida | [link](https://en.wikipedia.org/wiki/%C5%A0K_Slovan_Bratislava) |
| Southampton | 22 | 4/7/9/2 | 18 | desconhecida | [link](https://en.wikipedia.org/wiki/Southampton_F.C.) |
| Sport | 30 | 4/10/9/7 | 26 | desconhecida | [link](https://en.wikipedia.org/wiki/Sport_Club_do_Recife) |
| Sporting | 29 | 4/10/7/8 | 25 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/Sporting_CP) |
| Sporting Cristal | 36 | 4/11/12/9 | 32 | 2026-08-12 | [link](https://en.wikipedia.org/wiki/Sporting_Cristal) |
| Stoke City | 30 | 3/10/9/8 | 27 | 2026-06-26 | [link](https://en.wikipedia.org/wiki/Stoke_City_F.C.) |
| Stuttgart | 33 | 4/12/9/8 | 29 | desconhecida | [link](https://en.wikipedia.org/wiki/VfB_Stuttgart) |
| Sunderland | 29 | 3/9/9/8 | 26 | 2026-09-03 | [link](https://en.wikipedia.org/wiki/Sunderland_A.F.C.) |
| Swansea City | 26 | 3/8/8/7 | 23 | 2026-09-11 | [link](https://en.wikipedia.org/wiki/Swansea_City_A.F.C.) |
| Deportes Tolima | 33 | 4/11/8/10 | 29 | desconhecida | [link](https://en.wikipedia.org/wiki/Deportes_Tolima) |
| Tottenham Hotspur | 27 | 3/8/7/9 | 24 | desconhecida | [link](https://en.wikipedia.org/wiki/Tottenham_Hotspur_F.C.) |
| Universidad Católica | 27 | 3/10/8/6 | 24 | desconhecida | [link](https://en.wikipedia.org/wiki/2026_Club_Deportivo_Universidad_Cat%C3%B3lica_season) |
| Universidad Central | 30 | 4/9/9/8 | 26 | 2026-03-10 | [link](https://en.wikipedia.org/wiki/Universidad_Central_de_Venezuela_F.C.) |
| Universitario | 28 | 3/5/12/8 | 25 | 2026-07-10 | [link](https://libero.pe/futbol-peruano/universitario/2026/07/10/asi-quedo-plantel-de-universitario-torneo-clausura-2026-salidas-fichajes-491800) |
| Vasco da Gama | 39 | 3/13/13/10 | 0 | 2026-10-13 | [link](https://en.wikipedia.org/wiki/2026_CR_Vasco_da_Gama_season) |
| Viking | 30 | 3/12/6/9 | 27 | desconhecida | [link](https://en.wikipedia.org/wiki/Viking_FK) |
| Vila Nova | 22 | 2/6/6/8 | 20 | 2026-09-14 | [link](https://en.wikipedia.org/wiki/Vila_Nova_Futebol_Clube) |
| Villarreal | 27 | 3/8/8/8 | 24 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/Villarreal_CF) |
| Vitória | 36 | 3/12/10/11 | 33 | 2026-09-12 | [link](https://en.wikipedia.org/wiki/Esporte_Clube_Vit%C3%B3ria) |
| Watford | 28 | 3/9/5/11 | 25 | 2026-09-11 | [link](https://en.wikipedia.org/wiki/Watford_F.C.) |
| West Bromwich Albion | 22 | 2/7/7/6 | 20 | 2026-09-03 | [link](https://en.wikipedia.org/wiki/West_Bromwich_Albion_F.C.) |
| West Ham United | 23 | 2/7/8/6 | 7 | 2026-06-20 | [link](https://en.wikipedia.org/wiki/2026%E2%80%9327_West_Ham_United_F.C._season) |
| Wolverhampton | 28 | 3/8/8/9 | 25 | 2026-09-12 | [link](https://en.wikipedia.org/wiki/Wolverhampton_Wanderers_F.C.) |
| Wrexham | 29 | 3/11/10/5 | 26 | desconhecida | [link](https://en.wikipedia.org/wiki/Wrexham_A.F.C.) |

## Conflitos resolvidos

Quando o mesmo jogador aparece em duas listas, fica no clube cuja lista é mais recente.

| Jogador | Ficou em | (data) | Removido de | (data) | Critério |
|---|---|---|---|---|---|
| Aaron Wan-Bissaka | aston-villa | 2026-08-30 | west-ham | 2026-06-20 | mesmo nome completo e nacionalidade |
| Léo Aragão | cruzeiro | 2026-08-06 | avai | 2026-04-15 | mesmo nome completo e nacionalidade |
| Zé Ricardo | remo | 2026-09-01 | avai | 2026-04-15 | mesmo nome completo e nacionalidade |
| Alejo Véliz | bahia | 2026-09-22 | rosario-central | 2026-02-24 | mesmo nome completo e nacionalidade |
| Ruan Pablo | bahia | 2026-09-22 | botafogo-sp | 2026-04-15 | mesmo nome completo e nacionalidade |
| Dominik Livaković | barcelona | 2026-08-29 | fenerbahce | 2026-05-17 | mesmo nome completo e nacionalidade |
| Sebastián Villa | boca-juniors | 2026-08-18 | ind-rivadavia | 2026-03-05 | mesmo nome completo e nacionalidade |
| Callum Wilson | brentford | 2026-08-21 | west-ham | 2026-06-20 | mesmo nome completo e nacionalidade |
| El Hadji Malick Diouf | brentford | 2026-08-21 | west-ham | 2026-06-20 | mesmo nome completo e nacionalidade |
| Chema Andrés | brighton | desconhecida | stuttgart | desconhecida | mesmo nome completo e nacionalidade |
| Largie Ramazani | burnley | 2026-09-06 | leeds | 2026-08-29 | mesmo nome completo e nacionalidade |
| Juan Alano | ceara | 2026-06-18 | sport | desconhecida | mesmo nome completo e nacionalidade |
| Luiz Otávio | ceara | 2026-06-18 | cuiaba | 2026-04-15 | mesmo nome completo e nacionalidade |
| Alexis Martín Arias | nacional-uru | 2026-09-30 | cerro-porteno | 2026-06-27 | mesmo nome completo e nacionalidade |
| Luis Amarilla | juventude | 2026-09-23 | cerro-porteno | 2026-06-27 | mesmo nome completo e nacionalidade |
| Neto Pessoa | chapecoense | 2026-05-26 | sport | desconhecida | mesmo nome completo e nacionalidade |
| Higor Meritão | vila-nova | 2026-09-14 | chapecoense | 2026-05-26 | mesmo nome completo e nacionalidade |
| Freddie Potts | club-brugge | 2026-08-31 | west-ham | 2026-06-20 | mesmo nome completo e nacionalidade |
| Iliman Ndiaye | everton | 2026-08-14 | man-city | desconhecida | mesmo nome completo e nacionalidade |
| Tim Iroegbunam | everton | 2026-08-14 | hull | desconhecida | mesmo nome completo e nacionalidade |
| Anthony Musaba | norwich | 2026-08-19 | fenerbahce | 2026-05-17 | mesmo nome completo e nacionalidade |
| Sorba Thomas | stoke | 2026-06-26 | hull | desconhecida | mesmo nome completo e nacionalidade |
| Alfonso Simarra | u-central | 2026-03-10 | ind-medellin | desconhecida | mesmo nome completo e nacionalidade |
| Curtis Jones | inter | 2026-09-05 | liverpool | 2026-07-01 | mesmo nome completo e nacionalidade |
| William Pottker | ponte-preta | 2026-06-07 | londrina | 2026-04-15 | mesmo nome completo e nacionalidade |
| James Ward-Prowse | west-ham | 2026-06-20 | southampton | desconhecida | mesmo nome completo e nacionalidade |
| Juan Manuel Cuesta | sporting-cristal | 2026-08-12 | u-central | 2026-03-10 | mesmo nome completo e nacionalidade |
| Mateus Fernandes | west-ham | 2026-06-20 | tottenham | desconhecida | mesmo nome completo e nacionalidade |
| L. Monzón | botafogo | 2026-10-24 | junior | desconhecida | nome abreviado + sobrenome + nacionalidade |
| Brandão | ponte-preta | 2026-06-07 | coritiba | 2026-09-11 | emprestado por coritiba |

## Avisos e dados ausentes

- betis: elenco curto em alguma linha (GOL 1, DEF 8, MEI 9, ATA 6)
- cerro-porteno: elenco curto em alguma linha (GOL 1, DEF 11, MEI 9, ATA 9)
- southampton: elenco curto em alguma linha (GOL 4, DEF 7, MEI 9, ATA 2)

### Listas anteriores à janela do meio do ano (podem estar defasadas)

- Always Ready: 2026-03-14
- América-MG: desconhecida
- Avaí: 2026-04-15
- Real Betis: desconhecida
- Birmingham City: desconhecida
- Blackburn Rovers: 2026-05-19
- Bodø/Glimt: desconhecida
- Bolívar: 2026-02-13
- Botafogo-SP: 2026-04-15
- Brighton: desconhecida
- Ceará: 2026-06-18
- Cerro Porteño: 2026-06-27
- Chapecoense: 2026-05-26
- Charlton Athletic: desconhecida
- CRB: desconhecida
- Cuiabá: 2026-04-15
- Cusco FC: 2026-03-16
- Derby County: desconhecida
- Fenerbahçe: 2026-05-17
- Galatasaray: desconhecida
- Hull City: desconhecida
- Independiente Medellín: desconhecida
- Independiente Rivadavia: 2026-03-05
- Junior Barranquilla: desconhecida
- Lens: desconhecida
- Londrina: 2026-04-15
- Manchester City: desconhecida
- Náutico: desconhecida
- Newcastle United: desconhecida
- Novorizontino: desconhecida
- Operário-PR: desconhecida
- Peñarol: 2026-02-23
- Platense: 2026-03-06
- Ponte Preta: 2026-06-07
- Porto: desconhecida
- Portsmouth: desconhecida
- PSV Eindhoven: desconhecida
- Rosario Central: 2026-02-24
- Santa Fe: desconhecida
- Shakhtar Donetsk: desconhecida
- Slovan Bratislava: desconhecida
- Southampton: desconhecida
- Sport: desconhecida
- Stoke City: 2026-06-26
- Stuttgart: desconhecida
- Deportes Tolima: desconhecida
- Tottenham Hotspur: desconhecida
- Universidad Católica: desconhecida
- Universidad Central: 2026-03-10
- Viking: desconhecida
- West Ham United: 2026-06-20
- Wrexham: desconhecida

### Campos sem fonte

- **Idade / data de nascimento e pé preferido:** as fontes de elenco não trazem — ficam como desconhecidos (null).
- **Nacionalidade:** desconhecida quando a fonte não informa (ex.: Universitario).
- **Número da camisa:** "-" quando a fonte não informa (listas do canchallena).
- Athletic: a fonte não informa números nem nacionalidades ("?"); 4 estrangeiros não identificados
- Botafogo: lista de fev/2026 da Wikipedia estava desatualizada; usado o plantel do canchallena (La Nación)
- Cruzeiro: Matías Viña incluído a partir da lista do artigo principal (https://en.wikipedia.org/wiki/Cruzeiro_EC)
- Platense: reserve-team list (numbers 35-56) not imported
- São Bernardo: o site oficial não informa nacionalidades ("?"); posições pelos títulos das seções
- Universitario: a fonte não informa nacionalidade nem numeração
