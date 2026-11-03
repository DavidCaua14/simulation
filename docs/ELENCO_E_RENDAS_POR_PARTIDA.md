# Elenco após contratação e rendas por partida

A evolução 57 melhora a sincronização e a localização dos reforços e limita a renda futura ao porte do clube. A implantação não refaz contratações, não cobra taxas novamente e não recalcula valores já recebidos.

## Diagnóstico e elenco

Na carreira examinada, os reforços concluídos tinham contrato ativo, vínculo correto com o clube e disponibilidade na API de elenco. A cópia local retornou os 38 atletas, incluindo os reforços mencionados na investigação. Não foi necessário restaurar propriedade, aceitar ofertas ou criar contratos nessa carreira.

A tela Time tinha uma fragilidade de sincronização: uma resposta antiga de elenco podia substituir uma mais recente, e a atualização não acompanhava explicitamente mudanças de elenco no mesmo dia. A correção passa a ignorar respostas ultrapassadas e a observar a data do mundo e uma revisão calculada da composição do elenco. A revisão não exige nova tabela nem simulação de outros clubes.

- **Atualizar elenco:** consulta novamente a lista atual. Um rascunho de escalação em edição mantém suas escolhas válidas; a atualização não grava nem substitui a escalação salva. Jogadores que já não pertencem ao clube são removidos apenas desse rascunho local.
- **Buscar no elenco:** o seletor de vaga permite buscar por nome, sem diferenciar maiúsculas ou acentos. A interface avisa quando o filtro de disponibilidade oculta lesionados/suspensos e permite mostrar todos. Na escolha de reservas, explica que os titulares já escalados não aparecem nessa lista.
- **Contrato registrado:** a negociação informa que o atleta integra o elenco e oferece “Ver atleta no Time”, abrindo sua ficha.
- **Etapas da contratação:** acerto com o clube, análise do atleta e acordo aguardando registro são distinguidos da contratação concluída. Janela fechada ou início futuro mostram a data de registro. Não há inscrição fora da janela para contornar a espera.
- **Histórico:** uma contratação antiga cujo atleta já saiu não é usada para devolvê-lo ao clube. A informação de chegada considera a propriedade atual e o contrato vigente.
- **Conclusão no servidor:** o registro inicializa somente metadados pessoais ausentes daquele atleta e exige o vínculo com o elenco antes de declarar a contratação concluída. Não sobrescreve atributos ou histórico existentes.

## Rendas futuras

Foram encontrados lançamentos históricos de bilheteria de R$ 2,7 milhões para um clube pequeno. O cálculo então vigente já havia reduzido o valor-base, mas continuava permitindo que o prestígio elevasse muito a renda. A nova regra usa a força de catálogo como aproximação estável do porte econômico. O prestígio altera a estimativa em no máximo 10%, respeitando os tetos.

| Situação | Bilheteria bruta | Bônus de vitória |
| --- | ---: | ---: |
| Cuiabá, liga, prestígio-base | R$ 250 mil | R$ 125 mil |
| Clube pequeno, teto em liga | R$ 300 mil | R$ 175 mil |
| Clube pequeno, teto continental | R$ 375 mil | R$ 200 mil |
| Clube grande | Faixa de milhões, limitada a R$ 3 milhões | Conforme porte e competição |

“Clube pequeno” corresponde a força de catálogo abaixo de 70. Clubes intermediários e grandes seguem faixas próprias. Jogos de copa e continentais têm multiplicadores limitados, sem transformar o prestígio esportivo de um clube pequeno em bilheteria de milhões. A divisão do jogo não reescreve esses perfis de catálogo.

No exemplo de vitória em casa do Cuiabá, entram R$ 250 mil de bilheteria e R$ 125 mil de bônus; a operação da partida desconta R$ 50 mil. O saldo da partida é R$ 325 mil. O resumo passa a separar bilheteria bruta, bônus pelo resultado, custo de operação e saldo no caixa. Bilheteria continua pertencendo ao mandante, e o tratamento de campo neutro permanece existente.

Os valores armazenados continuam em milhares de reais: `250` corresponde a R$ 250.000. A carteira pessoal e as moedas do treinador não recebem essas receitas. Os créditos são idempotentes por partida.

**Histórico preservado:** saldos e recibos de partidas anteriores, inclusive valores altos do modelo antigo, permanecem como foram efetivamente registrados. Reabrir um resumo não aplica a renda nova retroativamente. As novas faixas valem para receitas futuras.

## Verificações

1. Backup privado das nove carreiras, funções e permissões; restauração em banco descartável.
2. Aplicação e reaplicação da migração, comparando todas as tabelas anteriores. A proteção atômica da migração compara vinte tabelas de progresso e aborta se qualquer valor mudar.
3. `roster_revenue_tests.sql`: proposta, registro, retorno no elenco, seleção e gravação na escalação de uma carreira sintética; revisão do elenco no mesmo dia; estado pessoal ausente; recibos idempotentes; espera por janela; limites de renda com prestígio extremo e conciliação do extrato.
4. Suíte de regressão `python scripts/test-seasons-db.py --scoped-runtime --skip-existing-tests`, incluindo os testes anuais de solvência, renovações, mercado, aportes e concorrência.
5. `python tests/career_world_ui_smoke.py <fixtures> --roster-refresh`: celular e desktop, resposta antiga chegando depois da nova, preservação do rascunho, busca sem acento e acesso direto à ficha do reforço.
6. O mesmo teste de interface executado também com o elenco real extraído da restauração local, por API interceptada. Os arquivos dessa validação permanecem privados, fora do repositório.
7. `python tests/career_world_ui_smoke.py <fixtures> --match-revenue`: fluxo de partida e resumo com bilheteria, bônus, operação e saldo separados. Build e lint dos componentes alterados.
8. Em produção, conferir apenas definições, permissões e histórico de migrações. Não avançar datas nem gravar escalações de usuários para testar.

## Implantação

Migração de produção: `20261103203618_transfer_roster_match_revenue.sql`. A aplicação e reaplicação na restauração dos nove saves passaram sem alterar as tabelas existentes, incluindo lançamentos financeiros históricos e contratos. As cinco funções instaladas e suas permissões são verificadas contra a versão testada. O histórico de migrações deve permanecer alinhado entre o Supabase e o repositório.
