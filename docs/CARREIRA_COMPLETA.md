# Carreira completa — integração e etapas

Pedido integral: CARREIRA_COMPLETA_REQUISITOS.md. Manutenção permanece ativa.

## Diagnóstico e decisões

O motor e as escalações já usam atletas e atributos individuais por carreira; o catálogo mundial é compartilhado e imutável para ações do usuário. O calendário e as ofertas, porém, ainda pressupõem uma região ativa. Não existem caixa dos clubes, folha salarial, contratos de atletas nem negociações esportivas; o mercado de cartas foi aposentado. Ele não será reintroduzido.

Integração: serviços SQL modulares em 24 (modelos), 25 (calendário/universo), 26 (finanças/contratos), 27 (negociações/IA), 28 (empregos/notícias), 29 (adaptação às RPCs existentes). Interface móvel mantém as cinco abas inferiores; a gestão adicional fica em painéis da Carreira, sem acrescentar uma barra de navegação larga. Mercado esportivo usa cartas base existentes e fichas atuais.

Cada carreira possui data global persistente e temporadas regionais independentes (Brasil: janeiro–dezembro; Inglaterra/Europa: julho–junho). O usuário pode assumir um clube de outra região sem recriar resultados: a temporada regional correspondente passa a ser a temporada controlada. As demais seguem como `world`, com participantes classificados por seu próprio histórico. Ligas estrangeiras não cadastradas continuam representadas apenas por equipes de referência nas copas existentes.

As cartas base importadas continuam no inventário e seus atletas/estados atuais tornam-se os elencos iniciais contratados. A antiga sincronização deixa de mover um atleta de volta depois de uma venda ou de transportá-lo gratuitamente quando o treinador muda de emprego. Nenhuma carta especial, caixa, roleta ou mercado de cartas retorna.

Finanças usam moedas de jogo, não valores oficiais em reais/euros. Estimativas de porte, salários, idade desconhecida e potencial ficam identificadas como parâmetros de simulação. Caixa e patrimônio do clube são separados da carteira pessoal. Datas, lançamentos, salários e operações possuem referências únicas e pertencem à carreira. Contratos são versionados para ratear salários na troca de clube e preservar o passado. Dívidas restringem gastos e acionam recuperação limitada; não apagam o clube nem forçam vendas do clube do usuário.

Negociações têm revisão do clube, contraproposta, revisão do atleta, acordo, registro/janela, conclusão, recusa, expiração e cancelamento. Taxa fixa, parcelas, bônus, salário, duração, luvas e papel são suportados; trocas de atletas são opcionais no pedido e não serão simuladas sem um fluxo consistente. Pré-contratos exigem até seis meses restantes e registro após o encerramento do vínculo anterior. Reservas de recursos impedem comprometer o mesmo orçamento várias vezes.

Simulação de partidas reutiliza o motor existente, inclusive no exterior, para que campeão, artilharia e melhor atleta derivem de eventos/estatísticas armazenadas. Processamento de atualização é limitado por lote e pode ser retomado, sem sortear novamente decisões, pagar outra vez ou pular acontecimentos. Partidas reais em andamento não são alteradas.

## Etapas de trabalho

- [x] Modelos, relações compostas, RLS, configurações e migração sem perda.
- [x] Calendário global, regiões paralelas, retomada e passagem de temporada.
- [x] Caixa, razão financeira, folha salarial, investimentos, contratos e recuperação.
- [x] Pesquisa internacional, propostas entre clubes/atletas, parcelas e pré-contratos.
- [x] Mercado de IA, propostas recebidas, satisfação e renovação.
- [x] Empregos internacionais, contratos do treinador, reputação e demissões.
- [x] Notícias, campeões/MVP/recordes e apresentação de contratações.
- [x] Interface responsiva integrada às cinco abas existentes.
- [x] Testes de ciclo, concorrência, RLS, preservação e interface; pacote de implantação preparado e testado localmente.

Cada etapa deve ser validada em PostgreSQL descartável. Antes de produção, gerar novo backup privado, prévia e verificações transacionais de resultados/saldos/estados antigos. Publicação e testes reais mantêm a manutenção, com a exceção administrativa existente.

## Cobertura dos 13 tópicos

| Pedido | Implementação integrada | Validação |
| --- | --- | --- |
| 1. Carreira e empregos | Nacionalidade continua influenciando a entrada; buscas posteriores alcançam as duas regiões. Diretoria, reputação, títulos e credibilidade limitam o nível do clube. Salário, prazo e orçamento são negociáveis; passagens e contratos ficam registrados. | Mudança internacional sem recriar jogos; renovação; demissão financeira; encerramento natural sem punição de credibilidade. |
| 2. Temporadas paralelas | Data global e temporadas regionais persistentes. Todas as nove competições cadastradas avançam pelo motor existente. Histórico determina classificação e participantes seguintes. | Ciclo completo de calendário, campeões, novas temporadas e Libertadores com origem `qualified`. |
| 3. Finanças | Caixa, dívidas, patrimônio, receitas comerciais/bilheteria, operação, folha de atletas e treinador, prêmios, vendas e investimentos. Salários proporcionais às datas dos contratos, bônus por atuação/gol e atrasados. | Pagamento e repetição do mês; investimento; atraso e quitação; crise, demissão e recuperação sem apagar clubes. |
| 4. Mercado internacional | Busca mundial por nome, posição, região, país do clube e valor. Os dois sentidos Brasil–Europa usam o mesmo fluxo e atualizam o vínculo individual. | Compra europeia por clube brasileiro e compra brasileira por clube inglês; venda internacional autorizada. |
| 5. Acordo entre clubes | Taxa, até 24 parcelas e bônus após dez atuações. Valor considera idade, potencial, qualidade, desempenho recente, contrato, papel, finanças, rivalidade e concorrência. Contrapropostas têm limite e prazo. | Aceite, contraproposta, reserva de recursos, parcelas, expiração e repetição sem duplicar. |
| 6. Acordo com atleta | Salário, anos, luvas, bônus por jogo/gol e promessa de participação. Prestígio, remuneração, papel e satisfação influenciam respostas. Livres e pré-contratos possuem regras próprias. | Duas aprovações antes da mudança; renovação; pré-contrato sem antecipar saída; acordo comum aguardando janela correta. |
| 7. Mercado da IA | Decisões persistidas por clube/dia, orçamento e profundidade por posição, qualidade/potencial, estilo tático e preferências internacionais. Compras, vendas, renovações e liberação por término de contrato. | Transferências internacionais da IA durante o ciclo completo; ausência de atletas com dois contratos ativos. |
| 8. Propostas recebidas | Vendas do time controlado aguardam aceitar, recusar ou contrapropor. Satisfação considera minutos reais, papel e salários atrasados; há aviso antes do pedido de saída. | Nenhuma venda antes da decisão; contraproposta e conclusão; renovação e alteração de promessa disponíveis. |
| 9. Anúncios | Notícias de contratações importantes trazem carta base, posição, overall, clubes e valor. Transferências comuns usam uma notícia simples. | Carta base e anúncio no navegador, sem cartas especiais. |
| 10. Notícias e tempo | Resultados, zebras, títulos, vice, melhor atleta do campeão, artilheiro, disputas, recordes da carreira, transferências, emprego, contratos e finanças. Chaves únicas e leitura persistida. | Premiação conferida contra as atuações reais; deduplicação de notícia e prêmio; prioridade do clube atual no feed. |
| 11. Decisões dos clubes | Perfis de investimento e posição, atributos, potencial, salário, satisfação, profundidade e atração esportiva. Uma oferta alta pode ser recusada por falta de reposição; atleta pode recusar o projeto. | Negociações por etapas e mercado da IA com decisões persistidas; reservas impedem comprometer o mesmo caixa. |
| 12. Isolamento e retomada | Relações compostas por carreira, RLS, funções internas privadas, travas da carreira e UUID de requisição. Atuações e lançamentos têm identidade própria. | Duas carreiras com o mesmo atleta; bloqueio de identificador estrangeiro; duas conexões concorrentes; repetição de lotes e investimentos. |
| 13. Integração e testes | Módulos SQL 24–29, APIs de carreira, painéis móveis, pacote transacional e runner descartável. Motor, táticas, cartas base, recompensas e histórico preservados. | Instalação limpa/reaplicação, SQL, concorrência, ciclo completo, build e navegador em quatro larguras. |

## Regras e limites explícitos

- Competições disponíveis: Brasileirão, Série B, Copa do Brasil, Libertadores, Premier League, Championship, FA Cup, EFL Cup e Champions League. Clubes de outras ligas continuam no mercado e nas copas cadastradas; esta mudança não inventa campeonatos domésticos sem dados. As simplificações dos formatos e vagas continuam documentadas em `TEMPORADAS_V2.md`.
- Brasil usa janeiro–dezembro; Inglaterra usa julho–junho. Na entrada de uma carreira antiga, a data é inferida do ano/dia legado e do último encerramento regional registrado; os resultados já realizados não são recalculados. A outra região pode precisar processar partidas anteriores à data de entrada. Essa primeira atualização leva mais tempo e tem progresso retomável.
- Os lotes possuem limite de partidas e uma parada entre jogos após aproximadamente dois segundos; os serviços do dia e uma partida individual precisam terminar atomicamente. A interface pode sair da gestão e retomar depois. O relógio para antes da partida do clube controlado, durante uma partida ao vivo e na virada da temporada até o usuário iniciar a próxima. Anos regionais antigos são reaproveitados; propostas podem assumir a temporada seguinte já preparada durante a pré-temporada.
- Janelas são parâmetros de gameplay: Brasil, 03/01–20/04 e 10/07–02/09; Inglaterra, 10/06–01/09 e 01/01–02/02. Não são uma afirmação sobre todas as datas oficiais de uma federação. Negociação aprovada após o fechamento aguarda a próxima janela. Pré-contrato nos últimos 180 dias registra somente após o vínculo anterior terminar; livres e renovações não exigem janela.
- Valores econômicos e potenciais são estimativas do jogo. Idade ausente no catálogo recebe estimativa identificada na interface. O valor incorpora avaliação, idade, potencial e atuações recentes; a reserva da taxa total impede usar parcelas para gastar um orçamento inexistente.
- O clube reserva dois meses da folha prevista, incluindo salário do treinador e estimativas de bônus por papel/posição. O atleta avalia salário, luvas e bônus previstos como um pacote. O extrato registra os pagamentos efetivos, conforme as atuações realmente realizadas.
- Bônus de transferência exige dez atuações pelo clube comprador em até um ano. Salários e bônus de atletas saem do clube, não da carteira pessoal. O salário efetivamente pago ao treinador entra na carteira; atrasados só entram quando quitados.
- Clubes podem acumular dívida e perder capacidade de contratação. Recuperação anual é limitada e registrada como financiamento; receitas, redução de compromissos e pagamento de atrasados permitem recuperação. Não existe remoção do clube nem venda automática do elenco do usuário.
- Trocas diretas de atletas e empréstimos novos não são oferecidos nesta versão; eram opcionais no pedido. Taxa, parcelas, bônus, renovação, livres e pré-contratos possuem fluxo completo.
- O arquivo `cw_appearances` captura as atuações antes da compactação das partidas da IA. `cw_stats_opening` preserva os agregados anteriores à migração para premiações. Súmulas antigas já descartadas pelo motor não podem ser reconstruídas; não são inventadas. Jogadores e estados de partidas em andamento permanecem no motor com que começaram.
- Inventários base continuam preservados. A posse contratual dos elencos é independente do inventário visual; vender um atleta ou mudar de emprego não o teletransporta de volta. Caixas, cartas especiais, roleta e compra de cartas permanecem encerradas.

## Testes reproduzíveis

Somente em container PostgreSQL descartável. O runner cria um banco com prefixo `simulation_validation_`; não aceita URL de produção.

```sh
python scripts/test-seasons-db.py --career-world --world-cycle --ui-fixtures /tmp/career-world-fixtures.json
npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
python tests/career_world_ui_smoke.py /tmp/career-world-fixtures.json
python tests/base_cards_ui_smoke.py /tmp/career-world-fixtures.json
node --test tests/sessionRecovery.test.mjs tests/maintenance.test.mjs
python tests/session_smoke.py
npm run build
```

`--skip-existing-tests` pula somente as suítes antigas mais longas; continua executando a migração e regressão das cartas base, os testes novos, a reaplicação e a concorrência. O ciclo durável usa uma transação por chamada e repete UUIDs a cada 25 lotes. `tests/career_world_season_cycle.py <container> <banco-descartável> --resume` permite continuar uma execução local interrompida.

As novas suítes verificam fundação/preservação, compras nos dois sentidos, aprovação do atleta, propostas recebidas, parcelas, pré-contratos, janela fechada, salários e atrasados, investimentos, empregos, credibilidade, recuperação, prêmios reais, isolamento, permissões e concorrência. O navegador intercepta toda a API com dados fictícios e cobre 360, 390, 768 e 1280 px, anúncios, notícias, datas, orçamento, mercado, contratos e ausência de transbordamento horizontal. A regressão anterior cobre escalação, barras de cansaço, filtros, ficha, loja, perfil e eventos em Brasil e Europa.

A execução durável validada percorreu 2.914 partidas, quatro temporadas regionais (duas encerradas e duas seguintes criadas), nove notícias de títulos e 130 transferências internacionais concluídas da IA, sem contratos ativos duplicados. Esses números são de dados fictícios de teste, não do Supabase real. O build e o ESLint dos módulos novos passaram. O lint global continua com 50 erros preexistentes nas demais áreas; não foi ampliado o escopo para reescrever essas telas.

## Implantação em produção — manutenção mantida

Implantação autorizada em 29/10/2026. O pacote 24–29 foi aplicado ao Supabase real após backup lógico privado de 126 tabelas e cópia das funções, políticas e permissões. A restauração isolada do schema e dos dados públicos reais passou pela migração e pela abertura das nove carreiras, preservando recursos, resultados, partida em andamento e estados dos atletas.

A comparação após a migração confirmou os dados originais das 91 tabelas públicas: nove carreiras, 17 temporadas, 8.048 partidas realizadas e uma partida em andamento. O backend novo e suas permissões foram conferidos; os universos continuam sendo ativados gradualmente ao abrir o modo Temporadas. As três tarefas agendadas foram pausadas durante a implantação e tiveram sua configuração de ativação restaurada. O backup fica fora do repositório; não é um ponto de restauração gerenciado pelo provedor.

**A manutenção permanece habilitada**, tanto no arquivo público quanto no hook REST/RPC. A exceção administrativa existente foi preservada. O código é enviado à `main` para o deploy automático configurado na Vercel, sem reabrir o acesso dos testadores.

O pacote completo e transacional é `supabase/releases/carreira_completa.sql`, gerado por:

```sh
node scripts/build-career-world-release.mjs
```

Procedimento para futuras implantações autorizadas:

1. Manter a tela e o hook REST/RPC de manutenção ativos, incluindo a exceção administrativa existente. Verificar serviços agendados que poderiam escrever durante a implantação.
2. Fazer **novo backup** de dados, funções, políticas e permissões do projeto real, verificar sua integridade e guardar fora do repositório. Os backups de etapas anteriores não substituem uma cópia atual.
3. Confirmar que a migração de cartas base 21–23 foi concluída. O preflight do pacote recusa inventários especiais e caixas pendentes. Testar o pacote completo numa restauração de homologação com o schema real.
4. Executar o arquivo completo numa única transação. Não executar somente uma seleção parcial do SQL Editor. O pacote usa trava de implantação, limite de espera de cinco segundos, timeout de 90 segundos e verificações que comparam carreiras, resultados realizados e partidas ao vivo antes/depois; qualquer divergência aborta a transação.
5. Conferir o commit e as funções instaladas antes de repetir uma chamada com erro de rede. A ativação dos universos é gradual, pela primeira abertura de cada carreira; não existe processamento massivo de salários ou transferência na migração.
6. Publicar a aplicação somente quando autorizado, com manutenção mantida, e validar a conta administrativa: retomada de partida antiga, atualização do mundo, escalação, finanças, mercado, proposta, contrato e próximo ano. O acesso dos testadores só é reaberto mediante a instrução expressa do usuário.

Uma falha antes de `COMMIT` desfaz a migração. Após uso do universo novo, não se deve remover tabelas ou restaurar funções antigas indiscriminadamente: os contratos, parcelas e temporadas já criados são progresso e precisam ser preservados numa correção ou restauração planejada.
