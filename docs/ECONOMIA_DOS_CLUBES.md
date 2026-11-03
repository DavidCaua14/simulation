# Economia dos clubes: reais, salários e contratação direta

## Resultado

As finanças dos clubes usam reais na interface: salários de R$ 50 mil, R$ 80 mil e R$ 100 mil nos níveis iniciais, e valores de milhões para atletas de alto nível. A curva de qualidade continua no servidor, junto das exigências esportivas e da verificação de orçamento.

Bilheteria de liga: Sport, R$ 270 mil por jogo em casa; Flamengo, R$ 1,5 milhão; clubes de maior prestígio chegam a R$ 2–3 milhões. Copas e torneios continentais têm multiplicadores, com bilheteria limitada a R$ 3 milhões por partida. São valores calibrados para o simulador a partir dos dados do catálogo, não uma importação da contabilidade real dos clubes.

O prêmio por vitória entra no caixa do clube, de onde saem salários, luvas e contratações. O resumo da partida apresenta prêmio e bilheteria. Energia, XP e conquistas mantêm suas regras. Os novos pagamentos comuns por partida deixam de gerar moedas pessoais; os já recebidos não são estornados. Prêmios de conquista e outros sistemas pessoais continuam separados.

Atletas realmente livres recebem uma proposta contratual diretamente: salário, luvas, anos, papel e bônus. Não há formulário de taxa ao clube, parcelamento ou pré-contrato nesse fluxo. O atleta ainda precisa aceitar o projeto, e o clube precisa sustentar o contrato.

## Unidade monetária e preservação

A unidade canônica de armazenamento e dos RPCs existentes passa a ser documentada como **milhares de reais**: um valor interno de `80` representa **R$ 80.000**. A API do mundo informa `economy.currency = BRL` e `economy.unit_scale = 1000`.

Isso evita multiplicar ou reescrever os saldos e históricos dos saves. Caixa, dívidas, patrimônio, contratos, valores de mercado, propostas, parcelas e recibos conservam suas quantidades registradas e suas relações financeiras. Não é concedido dinheiro adicional aos usuários pela mudança de escala, nem há cobrança retroativa.

A interface mostra reais completos e converte os campos de entrada para a unidade canônica antes de enviar ao servidor. Exemplo: salário digitado de **R$ 1.800.000** envia `p_salary = 1800`. Os campos monetários usam passos de R$ 1.000. **Não multiplicar novamente as colunas do banco ou os parâmetros dos RPCs por mil.**

`clubMoney`, `toClubReais` e `fromClubReais` centralizam a conversão. A carteira pessoal continua em moedas, com a quantidade original. Um investimento de uma moeda financia R$ 1.000 no clube. Salário de treinador sai do caixa nessa equivalência e é creditado na carteira em moedas, sem inflação de mil vezes. Luvas pessoais de treinador continuam identificadas como moedas.

A instalação preserva todas as linhas públicas preexistentes. As únicas tabelas adicionadas são modelos financeiros compartilhados por clube e marcadores de adoção da política por carreira/clube; ambas privadas, com RLS e sem acesso direto de clientes.

## Receitas e despesas

- O mandante recebe a bilheteria. Em campo neutro, as equipes dividem a arrecadação sem duplicar o total.
- A operação do estádio custa 20% da bilheteria e aparece separada no extrato.
- A vitória de liga paga aproximadamente R$ 516 mil ao Sport e R$ 1,2 milhão ao Flamengo. Copas e continentais aplicam multiplicadores. Em empate, cada clube recebe um terço do prêmio correspondente; desempate por pênaltis considera o vencedor.
- Cada lançamento usa uma referência única por partida. Alterar estatísticas ou repetir uma resposta não gera outra arrecadação.
- O fechamento mensal contabiliza patrocínios, transmissão e receitas comerciais. Não soma a bilheteria novamente. A operação mensal continua em 12% dessas receitas.
- O modelo comercial de um clube novo parte da folha de referência do catálogo, com margem para operação e gestão. A receita não cresce automaticamente a cada contratação feita pelo usuário.
- Ao adotar a política numa carreira existente, o processamento normal preserva pelo menos sua receita comercial anterior, o modelo de referência e a cobertura da folha já assumida. Caixa e dívidas não são alterados por essa adoção. O marcador impede recalcular essa proteção a cada nova contratação.
- O limite de contratações por janela, os seis meses de reserva do acréscimo da folha, as exigências de luvas e a recusa de projetos incompatíveis continuam ativos.

## Atleta livre

O RPC `career_free_agent_offer` recebe a proposta completa e o identificador do pedido. O servidor verifica o dono efetivo do atleta e a existência de contrato ativo. Um vínculo da IA projetado pelas regras de recuperação não pode ser contornado enviando `club_id = null` pelo navegador.

A negociação fica em análise do jogador, com vendedor nulo, taxa zero e uma parcela técnica sem cobrança de transferência. O mesmo pedido repetido devolve o recibo original. Uma falha de salário, luvas ou orçamento reverte a operação inteira, sem deixar negociação parcial ou reserva perdida.

Uma negociação contratual válida já aberta pode ser reutilizada. Contratações ainda respeitam a janela e o limite de registros: apresentar a proposta não registra o jogador imediatamente nem consome uma vaga. Os caminhos de transferência entre clubes e renovação seguem disponíveis.

## Arquivos

- Fonte de banco: `supabase/evolution/54_club_economy.sql`.
- Migração nova: `supabase/migrations/*_club_financial_scale.sql`. Não editar migrações já aplicadas.
- Formatação: `src/features/seasons/utils/clubMoney.js` e `world/ClubMoneyInput.jsx`.
- Interface: Mundo, contratos de atleta, termos do treinador, resumo da partida e campos de caixa no painel administrativo.

## Validação

Backup privado atualizado dos nove saves, restaurado num PostgreSQL local novo. Instalação e reaplicação verificadas por hashes das linhas preexistentes. Nenhum teste de contratação ou de avanço é executado em produção.

Cobertura:

- Formatação de R$ 50 mil, R$ 80 mil, R$ 100 mil e R$ 3,216 milhões; normalização do formulário; moedas pessoais sem multiplicação.
- Bilheteria, custo operacional, prêmio de vitória e empate nos destinatários corretos; recibo único; energia de vitória mantida.
- Contratação direta com taxa zero; validação de salário, dono, luvas e orçamento; falha atômica e repetição sem duplicar vínculo ou pagamento.
- Partida ao vivo concluída pelo endpoint real, resumo com renda do clube e repetição do resultado sem novo crédito.
- Fechamento mensal único, sem duplicar bilheteria e sem multiplicar salário pessoal do treinador.
- Navegador móvel de 320 pixels e desktop de 1280 pixels, com API interceptada: salário/luvas em reais, negociação direta em um formulário, transferência com clube mantida e nenhum avanço de data ao negociar.
- Build de produção, lint e regressões do runtime, sessões e economia.

Uma temporada financeira de doze meses foi testada com jogos de liga, salários e operações, sem transferências ou aportes. O cenário distribui vitórias, empates e derrotas; não é uma previsão de lucro para todos os saves.

| Clube | Caixa inicial | Caixa final | Bilheteria anual | Prêmios por resultado | Salários anuais |
| --- | ---: | ---: | ---: | ---: | ---: |
| Sport | R$ 36.944.000 | R$ 52.028.000 | R$ 5.130.000 | R$ 11.868.000 | R$ 61.296.000 |
| Flamengo | R$ 197.000.000 | R$ 241.256.000 | R$ 28.500.000 | R$ 27.600.000 | R$ 427.440.000 |

Ambos pagaram salários sem dívidas ou atrasos no cenário. Receitas comerciais e despesas operacionais também foram conciliadas com o caixa final. As transações de teste foram revertidas.

Para repetir: `python scripts/test-seasons-db.py --scoped-runtime --skip-existing-tests` e `node --test tests/clubMoney.test.mjs`. Com Vite e as fixtures do runner: `python tests/career_world_ui_smoke.py <fixtures.json> --club-economy`. Esses fluxos usam somente bancos descartáveis ou respostas interceptadas.

## Aplicação

A migração `20261103181732_club_financial_scale` foi aplicada no Supabase em 03/11/2026. A verificação transacional de 20 tabelas protegidas concluiu sem diferenças. A consulta posterior confirmou os 141 modelos compartilhados, RLS nas duas tabelas novas, auxiliares privados, o RPC direto restrito a usuários autenticados e a unidade BRL com escala 1.000. O valor interno 80 foi confirmado como R$ 80.000; o piso de Yamal, como R$ 3.216.000. Não houve contratação nem avanço de calendário executado para verificar produção.
