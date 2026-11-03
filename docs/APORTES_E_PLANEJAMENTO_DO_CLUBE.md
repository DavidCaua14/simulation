# Aportes e planejamento do clube

A evolução 56 dá uma finalidade concreta às moedas pessoais: ajudar o treinador a financiar contratações e renovações desejadas. Reaproveita Mundo → Finanças. Não introduz gestão de estádio, departamento comercial, categorias de base ou aumentos artificiais das despesas existentes.

## Experiência

- **Negociações:** ao editar uma proposta, uma consulta de leitura calcula taxa, luvas, bônus de transferência, reserva da folha atual, seis meses do acréscimo da folha, dívidas e outros compromissos. A reserva da própria negociação é descontada para evitar contagem dupla. Há uma estimativa antes da proposta ao clube e um cálculo com as condições exibidas na negociação contratual.
- **Aporte contextual:** se faltar orçamento e dinheiro puder resolver a pendência, a tela informa a diferença e o menor número de moedas necessário, já considerando o complemento disponível da diretoria. Um aporte nunca apresenta a proposta automaticamente. O usuário continua podendo rever os termos ou reunir moedas pelo salário do treinador e pelas recompensas existentes.
- **Exigências esportivas:** janela fechada, projeto incompatível, salário ou luvas insuficientes, restrição financeira e limites de elenco/contratações não são removidos por um aporte. Nessas situações, a consulta informa a restrição e não oferece um aporte como solução. As APIs de negociação continuam sendo a autoridade para o aceite e registro.
- **Renovações:** contratos do próprio elenco nos últimos seis meses recebem aviso na ficha do atleta em Mundo → Contratos. O formulário de renovação do Time também possui planejamento e aporte contextual. Na tela inicial, contratos nos últimos 90 dias podem gerar um cartão com vencimento, salário pretendido e acesso aos contratos. A renovação continua permitida com a janela fechada.
- **Página inicial:** mostra no máximo um cartão. Prioriza uma negociação já iniciada com falta de orçamento; depois, uma renovação próxima; por último, uma previsão conservadora de caixa para três meses. O cálculo considera receitas comerciais, operação mensal já existente, folha, dívida e parcelas. Bilheteria, premiações e vendas futuras são explicitamente apresentadas como receitas incertas, não incluídas na previsão. Um clube equilibrado sem pendências não recebe cobrança para investir.
- **Dispensar aviso:** a decisão é salva por carreira e clube. A mesma situação não reaparece só porque passou um dia ou porque o usuário abriu outra aba. Uma mudança relevante, como novo contrato, salário exigido ou necessidade financeira, pode produzir outro aviso. O cartão não pausa o calendário nem abre uma cobrança automaticamente.
- **Finanças:** o aporte existente passa a ter uma revisão explícita. Mostra carteira antes/depois, valor do aporte, parcela da diretoria e caixa antes/depois. Todo dinheiro aportado permanece no clube se o treinador sair.

## Diretoria

A diretoria acrescenta 20% aos novos aportes, dentro de uma única campanha por clube e temporada. O limite é compartilhado por todos os aportes dessa campanha:

| Força do clube no catálogo | Complemento máximo da diretoria | Moedas que atingem o limite |
| --- | ---: | ---: |
| Menor que 70 | R$ 200 mil | 1.000 |
| De 70 a 79 | R$ 400 mil | 2.000 |
| A partir de 80 | R$ 1 milhão | 5.000 |

A campanha pode ser aproveitada em parcelas. O arredondamento considera a soma acumulada: fracionar o aporte não gera benefício adicional. A troca de treinador ou a saída e volta ao clube não recriam o limite na mesma carreira, clube e temporada. A temporada é a temporada principal corrente da carreira; não depende do relógio real. As contribuições anteriores à implantação não são reprocessadas nem recebem crédito retroativo.

A conversão da evolução 54 permanece: uma moeda pessoal financia uma unidade canônica do clube, equivalente a R$ 1.000. O complemento da diretoria entra apenas no caixa do clube; não gera moedas pessoais e não pode ser sacado pelo treinador.

## Servidor e proteção

- `career_funding_quote` calcula o planejamento sem materializar clubes, simular jogos, abrir negociações ou movimentar valores.
- `career_club_investment_preview` mostra a revisão atual sem debitar moedas.
- `career_club_investment_confirm` exige que clube, carteira, caixa e complemento ainda correspondam aos valores revisados. Se outra aba mudar esses dados, o usuário deve atualizar a prévia e confirmar novamente.
- `career_club_invest` mantém a assinatura anterior para compatibilidade, com recibo idempotente, débito pessoal e créditos no caixa na mesma transação. O comprovante da diretoria é separado no histórico financeiro.
- As requisições de aporte são serializadas pela carreira. Repetir um UUID já concluído retorna seu recibo; duas confirmações diferentes da mesma prévia não debitam a carteira duas vezes. O frontend também bloqueia clique duplo e mantém o UUID ao repetir uma tentativa.
- `cw_board_contributions` guarda apenas o acumulado da campanha; `cw_funding_dismissals`, uma chave de aviso dispensado por clube. As tabelas têm RLS e nenhum acesso direto para `anon` ou `authenticated`. Os auxiliares SQL são privados; as APIs identificam a carreira pelo usuário autenticado.
- A nova informação do cartão e da campanha acompanha `career_world_status`, sem uma nova rotina de simulação na página inicial. Só até três negociações existentes são consideradas por leitura.

## Implantação e verificação

1. Fazer backup privado consistente por carreira e das definições atuais, fora do repositório público.
2. Restaurar em banco local descartável. Aplicar a nova migração e comparar todas as tabelas anteriores; reaplicar e repetir a comparação.
3. A migração de produção possui proteção atômica: bloqueia as carreiras, compara contagens e hashes em vinte tabelas de progresso e aborta se qualquer valor mudar. A instalação só cria estruturas vazias, funções e permissões. Não realiza aportes nem avança dias.
4. Executar `python scripts/test-seasons-db.py --scoped-runtime --skip-existing-tests`, incluindo `club_investment_tests.sql` e `club_investment_concurrency.py`. Os testes cobrem cálculo real de contratação livre e renovação, confirmação, arredondamento, limites da diretoria, duas abas, privacidade, avisos e datas.
5. Executar `python tests/career_world_ui_smoke.py <fixtures> --club-investment` e `--renewal-window`, além de build, lint e utilitários monetários. Verificar celular, desktop, carteira insuficiente, cancelamento, clique duplo, dispensa e navegação do cartão.
6. Aplicar no Supabase somente o SQL testado. Conferir as funções, permissões e a versão efetivamente instalada. Alinhar o nome da nova migração local a essa versão, sem editar migrações antigas.
7. Publicar o frontend no `main` e conferir Vercel e Supabase Preview. Em produção, não usar saves reais para testar aportes ou propostas.

Nenhum saldo, contrato, elenco, nível, título ou resultado existente é recalculado na implantação. Os novos efeitos financeiros dependem de um aporte futuro escolhido pelo usuário.

## Verificação desta versão

Migração de produção: `20261103200339_club_investment_guidance.sql`. Aplicação e reaplicação na restauração dos nove saves passaram sem alterar as tabelas existentes; a proteção atômica conferiu 180 comparações nas vinte tabelas de progresso. A suíte de banco apresentou 143 verificações aprovadas, incluindo concorrência. Os testes específicos adicionais de contratação livre, renovação e previsão, sete cenários de interface em celular/desktop, utilitários monetários, build e lint também passaram. Em produção foram conferidas as definições e permissões, sem testar aportes em contas reais.
