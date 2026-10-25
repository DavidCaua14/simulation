# Relatório de importação dos elencos

Gerado por `node scripts/build-squads.mjs` em 2026-10-24.

- **Clubes com elenco:** 48 de 48
- **Jogadores importados:** 1613
- **Posição detalhada estimada** (fonte só informava GOL/DEF/MEI/ATA): 1315
- **Conflitos resolvidos** (jogador em duas listas): 7

> **Atributos:** são uma *estimativa de gameplay*, não estatísticas oficiais. Método: v1: força do clube (sim_clubs.strength) + papel no elenco (camisa/capitão/base) + perfil da posição + variação determinística por jogador.
> Para curar um jogador, edite os atributos em `sim_player_attrs` e marque `estimated = false` — a importação não sobrescreve.

## Clubes

| Clube | Jogadores | GOL/DEF/MEI/ATA | Pos. estimadas | Data do elenco | Fonte |
|---|---:|---|---:|---|---|
| Always Ready | 24 | 3/8/8/5 | 21 | 2026-03-14 | [link](https://en.wikipedia.org/wiki/Club_Always_Ready) |
| Athletico-PR | 38 | 5/14/9/10 | 33 | 2026-09-22 | [link](https://en.wikipedia.org/wiki/Club_Athletico_Paranaense) |
| Atlético-MG | 33 | 4/9/14/6 | 29 | 2026-08-17 | [link](https://en.wikipedia.org/wiki/2026_Clube_Atl%C3%A9tico_Mineiro_season) |
| Bahia | 40 | 5/10/13/12 | 35 | 2026-09-22 | [link](https://en.wikipedia.org/wiki/Esporte_Clube_Bahia) |
| Barcelona SC | 31 | 3/9/7/12 | 28 | 2026-09-26 | [link](https://en.wikipedia.org/wiki/Barcelona_S.C.) |
| Boca Juniors | 30 | 4/7/13/6 | 26 | 2026-08-18 | [link](https://en.wikipedia.org/wiki/Boca_Juniors) |
| Bolívar | 29 | 3/9/11/6 | 26 | 2026-02-13 | [link](https://en.wikipedia.org/wiki/Club_Bol%C3%ADvar) |
| Botafogo | 51 | 5/18/17/11 | 46 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/botafogo-2x94b2pn1o1tb5l1bbu8x9yu9/) |
| Red Bull Bragantino | 45 | 5/13/18/9 | 40 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/bragantino-4ayjm36vlnc5j8jhwpsdwxuph/) |
| Cerro Porteño | 30 | 1/11/9/9 | 29 | 2026-06-27 | [link](https://en.wikipedia.org/wiki/Cerro_Porte%C3%B1o) |
| Chapecoense | 39 | 5/13/11/10 | 34 | 2026-05-26 | [link](https://en.wikipedia.org/wiki/Associa%C3%A7%C3%A3o_Chapecoense_de_Futebol) |
| Coquimbo Unido | 37 | 5/10/10/12 | 32 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/coquimbo-bw2py3aiws1rq61pokete3kv2/) |
| Corinthians | 33 | 2/11/13/7 | 31 | 2026-08-11 | [link](https://en.wikipedia.org/wiki/2026_SC_Corinthians_Paulista_season) |
| Coritiba | 36 | 4/10/9/13 | 32 | 2026-09-11 | [link](https://en.wikipedia.org/wiki/Coritiba_Foot_Ball_Club) |
| Cruzeiro | 34 | 5/9/7/13 | 29 | 2026-08-06 | [link](https://en.wikipedia.org/wiki/2026_Cruzeiro_Esporte_Clube_season) |
| Cusco FC | 25 | 4/7/8/6 | 21 | 2026-03-16 | [link](https://en.wikipedia.org/wiki/Cusco_FC) |
| Estudiantes | 30 | 3/10/8/9 | 27 | 2026-09-15 | [link](https://en.wikipedia.org/wiki/Estudiantes_de_La_Plata) |
| Flamengo | 26 | 3/9/8/6 | 0 | 2026-08-30 | [link](https://en.wikipedia.org/wiki/2026_CR_Flamengo_season) |
| Fluminense | 30 | 3/11/8/8 | 27 | 2026-09-22 | [link](https://en.wikipedia.org/wiki/Fluminense_FC) |
| Fortaleza | 37 | 3/13/10/11 | 34 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/fortaleza-1vvaya787s5wg5geudzacya7m/) |
| Grêmio | 36 | 4/13/10/9 | 0 | 2026-10-07 | [link](https://en.wikipedia.org/wiki/2026_Gr%C3%AAmio_FBPA_season) |
| Independiente del Valle | 29 | 3/10/8/8 | 26 | 2026-08-16 | [link](https://en.wikipedia.org/wiki/Independiente_del_Valle) |
| Independiente Medellín | 30 | 3/6/10/11 | 27 | desconhecida | [link](https://en.wikipedia.org/wiki/Independiente_Medell%C3%ADn) |
| Independiente Rivadavia | 28 | 3/9/10/6 | 25 | 2026-03-05 | [link](https://en.wikipedia.org/wiki/Independiente_Rivadavia) |
| Internacional | 45 | 4/17/13/11 | 41 | 2026-07-25 | [link](https://en.wikipedia.org/wiki/2026_Sport_Club_Internacional_season) |
| Junior Barranquilla | 28 | 2/9/7/10 | 26 | desconhecida | [link](https://en.wikipedia.org/wiki/Atl%C3%A9tico_Junior) |
| Juventude | 38 | 4/15/10/9 | 34 | 2026-09-23 | [link](https://en.wikipedia.org/wiki/Esporte_Clube_Juventude) |
| Deportivo La Guaira | 39 | 3/15/11/10 | 36 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/deportivo-la-guaira-em31nnti82q57le3wp7g5lsrj/) |
| Lanús | 29 | 2/10/10/7 | 27 | 2026-09-19 | [link](https://en.wikipedia.org/wiki/Club_Atl%C3%A9tico_Lan%C3%BAs) |
| LDU Quito | 36 | 5/8/17/6 | 31 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/ldu-quito-cxb4hqite921i36gwrezdts7c/) |
| Libertad | 38 | 3/14/16/5 | 35 | 2026-10-24 | [link](https://canchallena.lanacion.com.ar/equipo/libertad-984ibdjplnlwb36kt6wbgwe97/) |
| Mirassol | 31 | 4/10/8/9 | 27 | 2026-08-13 | [link](https://en.wikipedia.org/wiki/Mirassol_Futebol_Clube) |
| Nacional | 28 | 3/9/8/8 | 25 | 2026-09-30 | [link](https://en.wikipedia.org/wiki/Club_Nacional_de_Football) |
| Palmeiras | 25 | 3/10/8/4 | 22 | 2026-08-31 | [link](https://en.wikipedia.org/wiki/2026_SE_Palmeiras_season) |
| Peñarol | 31 | 3/12/12/4 | 28 | 2026-02-23 | [link](https://en.wikipedia.org/wiki/Pe%C3%B1arol) |
| Platense | 35 | 3/10/10/12 | 32 | 2026-03-06 | [link](https://en.wikipedia.org/wiki/Club_Atl%C3%A9tico_Platense) |
| Remo | 35 | 3/11/11/10 | 32 | 2026-09-01 | [link](https://en.wikipedia.org/wiki/2026_Clube_do_Remo_season) |
| Rosario Central | 35 | 4/15/11/5 | 31 | 2026-02-24 | [link](https://en.wikipedia.org/wiki/Rosario_Central) |
| Santa Fe | 32 | 4/11/10/7 | 28 | desconhecida | [link](https://en.wikipedia.org/wiki/Independiente_Santa_Fe) |
| Santos | 40 | 5/11/13/11 | 0 | 2026-10-08 | [link](https://en.wikipedia.org/wiki/2026_Santos_FC_season) |
| São Paulo | 38 | 5/14/9/10 | 33 | 2026-09-17 | [link](https://en.wikipedia.org/wiki/S%C3%A3o_Paulo_FC) |
| Sporting Cristal | 36 | 4/11/12/9 | 32 | 2026-08-12 | [link](https://en.wikipedia.org/wiki/Sporting_Cristal) |
| Deportes Tolima | 33 | 4/11/8/10 | 29 | desconhecida | [link](https://en.wikipedia.org/wiki/Deportes_Tolima) |
| Universidad Católica | 27 | 3/10/8/6 | 24 | desconhecida | [link](https://en.wikipedia.org/wiki/2026_Club_Deportivo_Universidad_Cat%C3%B3lica_season) |
| Universidad Central | 30 | 4/9/9/8 | 26 | 2026-03-10 | [link](https://en.wikipedia.org/wiki/Universidad_Central_de_Venezuela_F.C.) |
| Universitario | 28 | 3/5/12/8 | 25 | 2026-07-10 | [link](https://libero.pe/futbol-peruano/universitario/2026/07/10/asi-quedo-plantel-de-universitario-torneo-clausura-2026-salidas-fichajes-491800) |
| Vasco da Gama | 39 | 3/13/13/10 | 0 | 2026-10-13 | [link](https://en.wikipedia.org/wiki/2026_CR_Vasco_da_Gama_season) |
| Vitória | 36 | 3/12/10/11 | 33 | 2026-09-12 | [link](https://en.wikipedia.org/wiki/Esporte_Clube_Vit%C3%B3ria) |

## Conflitos resolvidos

Quando o mesmo jogador aparece em duas listas, fica no clube cuja lista é mais recente.

| Jogador | Ficou em | (data) | Removido de | (data) | Critério |
|---|---|---|---|---|---|
| Alejo Véliz | bahia | 2026-09-22 | rosario-central | 2026-02-24 | mesmo nome completo e nacionalidade |
| Sebastián Villa | boca-juniors | 2026-08-18 | ind-rivadavia | 2026-03-05 | mesmo nome completo e nacionalidade |
| Alexis Martín Arias | nacional-uru | 2026-09-30 | cerro-porteno | 2026-06-27 | mesmo nome completo e nacionalidade |
| Luis Amarilla | juventude | 2026-09-23 | cerro-porteno | 2026-06-27 | mesmo nome completo e nacionalidade |
| Alfonso Simarra | u-central | 2026-03-10 | ind-medellin | desconhecida | mesmo nome completo e nacionalidade |
| Juan Manuel Cuesta | sporting-cristal | 2026-08-12 | u-central | 2026-03-10 | mesmo nome completo e nacionalidade |
| L. Monzón | botafogo | 2026-10-24 | junior | desconhecida | nome abreviado + sobrenome + nacionalidade |

## Avisos e dados ausentes

- cerro-porteno: elenco curto em alguma linha (GOL 1, DEF 11, MEI 9, ATA 9)

### Listas anteriores à janela do meio do ano (podem estar defasadas)

- Always Ready: 2026-03-14
- Bolívar: 2026-02-13
- Cerro Porteño: 2026-06-27
- Chapecoense: 2026-05-26
- Cusco FC: 2026-03-16
- Independiente Medellín: desconhecida
- Independiente Rivadavia: 2026-03-05
- Junior Barranquilla: desconhecida
- Peñarol: 2026-02-23
- Platense: 2026-03-06
- Rosario Central: 2026-02-24
- Santa Fe: desconhecida
- Deportes Tolima: desconhecida
- Universidad Católica: desconhecida
- Universidad Central: 2026-03-10

### Campos sem fonte

- **Idade / data de nascimento e pé preferido:** as fontes de elenco não trazem — ficam como desconhecidos (null).
- **Nacionalidade:** desconhecida quando a fonte não informa (ex.: Universitario).
- **Número da camisa:** "-" quando a fonte não informa (listas do canchallena).
- Botafogo: lista de fev/2026 da Wikipedia estava desatualizada; usado o plantel do canchallena (La Nación)
- Cruzeiro: Matías Viña incluído a partir da lista do artigo principal (https://en.wikipedia.org/wiki/Cruzeiro_EC)
- Platense: reserve-team list (numbers 35-56) not imported
- Universitario: a fonte não informa nacionalidade nem numeração
