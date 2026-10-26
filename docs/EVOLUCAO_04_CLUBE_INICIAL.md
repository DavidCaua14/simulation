# Etapa 4 — Clube inicial pela nacionalidade do treinador

## Como funciona
Ao criar o treinador, a nacionalidade escolhida define as duas propostas que o empresário apresenta:

| Nacionalidade | Propostas | Perfil |
|---|---|---|
| Brasil | 1 clube da **Série A** (sorteado entre os 6 mais fracos, como antes) + 1 clube da **Série B** (sorteado entre os 8 mais fortes da Série B) | Série A: padrão · Série B: **início acessível** |
| Inglaterra | 2 clubes **ingleses** sorteados entre os 10 mais modestos da Championship (sem o Cardiff, que é galês) | padrão |

* As propostas são sorteadas **uma vez** e gravadas: atualizar a página mostra as mesmas (testado no navegador).
* Uma nova carreira do mesmo usuário nunca recebe o mesmo conjunto de clubes de uma carreira anterior (até esgotar as
  combinações). Em 12 carreiras inglesas seguidas, 12 duplas diferentes.
* Só entram clubes que disputam a competição na temporada de referência e têm elenco cadastrado (mínimo de 18 jogadores).
* A tela de criação mostra, abaixo da bandeira, o que cada nacionalidade recebe (texto vindo do banco).
* Treinador inglês começa a carreira na Inglaterra (Championship, FA Cup e EFL Cup); brasileiro, no Brasil.

## "Início acessível" (Série B) — dificuldade, não resultado manipulado
O motor da partida é exatamente o mesmo para todos. O perfil muda só a **cobrança** durante as 2 primeiras temporadas:

| | Padrão | Início acessível |
|---|---|---|
| Quedas de confiança da diretoria | 100% | 70% |
| Quedas do humor da torcida | 100% | 75% |
| Ganho de reputação | 100% | 125% |
| Demissão no meio da temporada (confiança ≤) | 12 | 6 |
| Demissão no fim da temporada por objetivo principal falhado (confiança <) | 35 | 25 |
| Meta da liga | da tabela de objetivos | 1 posição mais folgada |

Além disso, a Série B naturalmente tem adversários mais fracos que a Série A, o que torna o início mais acessível pela
força relativa das equipes. O teste T5 avalia a mesma partida com os dois perfis: placar e prêmios idênticos, queda de
confiança menor no perfil acessível. Depois de 2 temporadas a carreira volta ao padrão, inclusive se trocar de clube.

## Arquitetura (tudo em um lugar)
`supabase/evolution/05_career_start.sql`:
* `sim_start_rules` — uma linha por nacionalidade. Cada opção define competições elegíveis, países, quantidade, ordem
  (mais fracos / mais fortes / aleatório), tamanho do sorteio, força mínima/máxima, clubes excluídos, elenco mínimo,
  perfil de dificuldade, faixa das luvas e frases dos clubes.
* `sim_difficulty_profiles` — perfis de dificuldade (números acima).
* `sim_start_candidates(opção)` — clubes elegíveis; `get_initial_offers()` — sorteio único; `choose_initial_club(proposta)`
  — aplica o clube e o perfil; `mgr_difficulty(carreira)` — perfil em vigor, lido pelo motor da carreira.
* Validação: `careers.country` passou a referenciar `sim_start_rules` (nacionalidade sem regra é recusada).
  As 3 carreiras existentes (BR) continuam válidas e com o perfil padrão.

Nova nacionalidade = uma linha em `sim_start_rules` + bandeira no front. Nenhuma outra função muda.

## Segurança
* Proposta é escolhida só pelo servidor, com a carreira travada (`for update`): duas abas não sorteiam em dobro.
* Não dá para escolher proposta de outra carreira, escolher duas vezes, nem gravar o clube direto na tabela
  (o navegador só pode inserir nickname/foto/país/idade).
* Uma carreira ativa por usuário (índice único) — atualizar a página não cria outra.

## Testes
`supabase/evolution/tests/career_start_tests.sql` (T1–T6) — **todos passaram**, 6 execuções seguidas (o sorteio é aleatório):
configuração; propostas do brasileiro e persistência; proteções; Série B com perfil e meta ajustada; placar igual com
perfis diferentes e expiração do perfil; inglês com variedade sem repetição e temporada na Inglaterra.
Os testes das etapas anteriores (competições T1–T7, carreira T0–T6) continuam passando. Navegador: criação e propostas
nas duas nacionalidades, recarregar a página e escolher o clube.

## Ajuste encontrado durante a etapa
* O desfazer (`99_rollback.sql`) da etapa 2/3 falhava por dependência de uma função; corrigido e testado numa cópia do banco.
