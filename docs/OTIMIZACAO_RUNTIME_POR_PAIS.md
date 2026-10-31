# Otimização do simulador: execução e operação

> Situação da entrega: código pronto e validado; migração do Supabase aguardando a confirmação exigida pelo conector. O frontend mantém compatibilidade com o backend atual. A publicação do código, sozinha, não ativa as alterações do banco.

Referência: `Plano_de_otimizacao_do_simulador_de_treinador.pdf`, 31/10/2026. Implementação das etapas 0–8 nas evoluções 45–50 e no frontend de Carreira. O PostgreSQL continua sendo a fonte de verdade; não existe um JSON mutável contendo o save inteiro.

## Mudanças para quem joga

- Preparação limitada ao país ativo e às competições desse contexto, incluindo as continentais. Uma rodada da IA é concluída na mesma transação; a partida do treinador continua interativa.
- Propostas de emprego, contrapropostas e vencimentos relevantes interrompem o avanço. “Continuar sem responder” é uma decisão explícita; a confirmação próxima do vencimento é independente da anterior. Abrir uma tela não renova prazos.
- Mercado automático doméstico. Uma contratação manual no exterior materializa somente o clube/elenco e os contratos necessários, sem ligar a liga estrangeira.
- Propostas internacionais futuras respeitam reputação, credibilidade e alcance do clube. Propostas anteriores continuam válidas pelas condições originais.
- Trocar de país mantém data, resultados, transferências e obrigações. O destino é atualizado por resumo; o contexto anterior deixa de rodar a cada avanço. Voltar reutiliza a temporada existente.
- Partidas da IA usam gols, assistências, finalizações, posse, disciplina, lesões e desempates resumidos. O placar e os pênaltis de uma partida registrada usam a semente do save e sua identificação. O motor detalhado humano mantém seu caminho anterior.
- O hub apenas lê. Calendário inicial de até 30 partidas, consulta das próprias partidas e páginas de 500 por competição aberta. Cache invalidado por versão da competição.
- UUID e resposta duráveis permitem recuperar uma preparação após falha/fechamento do navegador. Recibos do fluxo anterior são importados; uma operação antiga sem recibo exige atualização em vez de ser reaplicada automaticamente. A RPC nova verifica a versão esperada; duas abas desatualizadas não aplicam dois avanços.

## Mapa das entregas

| Etapa do PDF | Implementação | Evidência |
| --- | --- | --- |
| 0. Preservação | Exportação privada comprimida por carreira; esquema/funções instalados; restauração em PostgreSQL 17 isolado | Nove saves restaurados, contagens e chaves estrangeiras validadas; comparações de todas as tabelas anteriores |
| 1. Decisões | `cw_attention`, `career_attention_ack`, prazos por data do jogo e banner | Parada sem mover a data; duas propostas não reaparecem alternadamente após confirmação |
| 2. Leituras | `career_hub_read`, `career_calendar`, inicialização explícita e cache | Endpoints executados em transação somente leitura; interface móvel/desktop |
| 3. Contexto | `cw_domestic_clubs`, serviços filtrados e critérios internacionais | Brasil não cria liga inglesa; busca internacional não ativa campeonato |
| 4. IA resumida | `mgr_sim_fixture`, `cw_random`, `cw_poisson`, finalização original | Resultado repetível, estatísticas/atuações e disciplina; temporada doméstica e continental completa |
| 5. Estado sob demanda | Catálogo compartilhado com snapshot versionado, `cw_materialize_club`, `cw_player_clock` | Nova carreira não copia o elenco mundial; contratação estrangeira preserva a atribuição individual |
| 6. Saves existentes | Instalação aditiva, flag por carreira e adiamento de partidas ao vivo | Instalação/reaplicação sem diferença de registros; retomada do mesmo jogo sem cobrança duplicada de energia |
| 7. Banco/manutenção | Índices direcionados, filtros em conjuntos, folha de pagamento da IA agregada, retenção fora do clique | Jornada medida, fechamento mensal sem duplicação e manutenção limitada |
| 8. Liberação | Migração atômica e frontend compatível durante a transição; testes de UI, concorrência, recuperação e ciclo | Registro de liberação ao final deste documento |

## Arquivos e responsabilidades

- `supabase/evolution/45_scoped_runtime.sql`: configuração, versões, recibos, decisões e relógio de recuperação.
- `46_scoped_services.sql`: adaptações das definições realmente instaladas; compatibilidade das RPCs anteriores; serviços domésticos e materialização.
- `47_scoped_calendar.sql`: avanço por eventos, rodadas resumidas, métricas e controle de versão/concorrência.
- `48_context_activation.sql`: catálogo global de consulta, países inativos, desempates por semente e calendário paginado.
- `49_runtime_security.sql`: `search_path` fixo onde faltava e `(select auth.uid())` nas políticas aplicáveis.
- `50_runtime_maintenance.sql`: retenção periódica com as exceções existentes e fechamento financeiro fora da compactação extensa.
- `scripts/build-scoped-runtime.mjs`: monta a migração única a partir das seis etapas.
- `scripts/backup-scoped-runtime.py` e `support/scoped_backup_schema.sql`: exportação privada e restauração exclusivamente em banco local descartável.
- `src/features/seasons`: RPCs, controle de preparação, recuperação local do UUID, banner de decisão e calendário sob demanda.

Os arquivos 45–50 são as fontes editáveis. Depois de alterá-los, executar `node scripts/build-scoped-runtime.mjs`. O pacote em `supabase/migrations/20261031191218_scoped_career_runtime.sql` executa uma única transação, bloqueia as carreiras em ordem, registra contagens/hashes por carreira e tabela, instala as funções e compara novamente. Qualquer diferença protegida aborta a transação inteira. As alterações de código posteriores devem ser novas migrações; não editar uma migração já aplicada como forma de liberar um hotfix.

Não reaplicar as evoluções antigas 1–44 sobre uma instalação atualizada: elas contêm definições anteriores e algumas limpezas imediatas. Os wrappers `_before_v45` são dependências privadas, não endpoints de cliente nem um comando de rollback.

## Preservação e backup

A instalação não reinicia carreiras, não redefine a data, não recompõe elencos pelo catálogo, não altera atributos de conta e não recalcula partidas já realizadas. Resultados, táticas, condição, lesões, suspensões, contratos, parcelas, propostas, inventário e recompensas existentes entram nas comparações. Os registros antigos de países inativos permanecem; a economia vem principalmente de deixar de produzir trabalho/dados desnecessários no futuro.

O backup de pré-instalação contém snapshots consistentes de cada uma das nove carreiras, catálogos compartilhados, esquema e funções. Foi mantido privado fora do repositório. Não é um backup completo do serviço Supabase: usuários de Auth são representados por identificadores no ensaio local, sem senhas, sessões ou segredos de autenticação. Preservar também backups gerenciados/PITR do projeto quando disponíveis; no início desta execução a API não apresentou backups gerenciados e PITR estava desativado.

Para uma nova cópia, disponibilizar `SUPABASE_ACCESS_TOKEN` por ambiente seguro e executar, sem colocar o token na linha de comando:

```sh
python scripts/backup-scoped-runtime.py export \
  --project-id nkdbixmfsochlprcvkxl \
  --directory /caminho/privado/simulation-backup
```

O destino deve estar vazio e fora deste repositório público. Arquivos são privados; guardar `compressed.key` separadamente em armazenamento seguro e manter uma cópia durável dos arquivos exportados. Cada carreira é consistente em sua própria consulta; não há promessa de um único instante global entre carreiras independentes que continuam jogando.

Para ensaiar a restauração com Docker/PostgreSQL 17:

```sh
python scripts/backup-scoped-runtime.py restore-local \
  --directory /caminho/privado/simulation-backup \
  --database simulation_validation_restore_20261031
```

O utilitário aceita somente banco local novo com prefixo `simulation_validation_`. Ele não recebe uma URL de produção e não restaura sobre um banco existente. A restauração reconstitui tabelas, tipos do motor, funções, índices, chaves estrangeiras, políticas e permissões, confere contagens e ajusta as identidades.

O token compartilhado na conversa não está no código ou nesta documentação. Sua revogação e substituição devem ser feitas no painel da conta após o uso autorizado; não há gerenciamento de tokens pessoais nesse pacote.

## Configuração e manutenção

`cw_runtime_rules` é administrativa e não tem acesso direto pelos clientes:

| Campo | Valor inicial | Função |
| --- | --- | --- |
| `foreign_reputation` | 55 | Reputação mínima para propostas internacionais futuras |
| `foreign_credibility` | 45 | Credibilidade financeira mínima correspondente |
| `market_interval` | 3 dias | Limite do salto entre serviços, com paradas adicionais nos eventos necessários |
| `catalog_version` | `2026-10-31` | Versão do catálogo/snapshot para esta liberação |
| `enabled` | true | Autoriza avanço do calendário no novo fluxo |

A manutenção agenda `career-runtime-retention` no minuto 41 de cada hora quando `pg_cron` está disponível. Ela atende no máximo três carreiras por execução, no máximo uma vez ao dia por carreira, com bloqueio que ignora carreiras ocupadas e partidas humanas ao vivo. A instalação não executa a limpeza imediatamente.

Retenção mantém as finalidades da evolução 41: histórico financeiro dos clubes atuais/anteriores do treinador, resultados e cartões necessários ao fair play, totais da temporada e atuações exigidas por cláusulas em aberto. Recibos novos em `cw_operations` não entram na limpeza antiga de `econ_requests`. Não executar `VACUUM FULL`, apagar históricos de usuários ou eliminar índices sem medição para atingir um tamanho arbitrário.

O snapshot de catálogo é compartilhado e congelado para auditoria/recuperação. As consultas atuais continuam usando as tabelas relacionais compartilhadas, sobrepostas pelo estado individual. Alterações futuras do editor no catálogo exigem uma nova versão e adaptação explícita das leituras antes de oferecer catálogos diferentes simultâneos; registrar uma nova string de versão sozinho não implementa essa mudança.

## Recuperação após uma falha

1. Se a migração falhar antes do commit, o PostgreSQL desfaz o pacote. Investigar o erro e repetir o mesmo pacote apenas após validação.
2. Se houver falha após a liberação, manter o estado gravado e pausar o avanço de calendário com `update public.cw_runtime_rules set enabled=false where id=true` por acesso administrativo. Leituras e a partida humana já iniciada continuam disponíveis.
3. Coletar erro/UUID, versão, métricas e definições instaladas. Reproduzir em cópia isolada e liberar uma correção aditiva.
4. Não ligar o motor global antigo apenas alterando flags: ele pode exigir dados que o novo fluxo não produz. Não restaurar um backup anterior por cima de progresso adquirido depois da liberação.
5. Para corrupção comprovada, restaurar em ambiente separado, comparar por carreira e recuperar somente os registros identificados, com controle de concorrência e validação dos compromissos posteriores.

## Validação e medições

Testes de simulação e de alteração de carreira rodaram somente em bancos PostgreSQL locais descartáveis. Os testes de navegador interceptaram as APIs. Não houve simulações de diagnóstico em contas de produção.

Cobertura: novo save brasileiro, Inglaterra, negociação manual internacional, ida/retorno de país, mês e salários/bonificações, desemprego, temporada doméstica/continental e virada de ano, recibos após resposta perdida, duas abas com UUIDs iguais/diferentes, leitura sem escrita, decisões múltiplas, prazos, desempates inativos, retomada e adiamento de ativação de partida humana.

A suíte anterior às evoluções 45–50 passou antes das alterações. A nova suíte compara as tabelas antigas antes/depois e reaplicação. O build, testes JS e lint dos arquivos alterados são verificados. O lint geral possui erros anteriores fora deste escopo; eles não foram tratados como novos sucessos.

Amostra local dos saves restaurados, não um SLO de produção:

| Operação | Amostras | Média no servidor | p95 | Máximo | Maior resposta |
| --- | --- | --- | --- | --- | --- |
| Hub de leitura | 25 | 75,03 ms | 144,00 ms | 146,42 ms | 37.623 bytes |
| Prévia do calendário | 25 | 0,90 ms | 1,47 ms | 1,85 ms | 11.473 bytes |
| Avanço em saves restaurados | 5 | 810,71 ms | 1.862,64 ms | 2.068,41 ms | 500 bytes |

Essa amostra foi colhida no pacote final sobre a segunda restauração dos saves; seus valores não são uma medição comparativa definitiva nem garantia para a produção. O alvo de 1 segundo de p95 no avanço ainda exige observação real. As 25 leituras e cinco avanços não representam teste de carga de usuários simultâneos.

A preparação verifica um orçamento de 1,2 segundo entre etapas/rodadas, mas uma rodada indivisível pode ultrapassá-lo. Custos de inicialização, troca de país, primeira leitura e virada de temporada devem ser acompanhados separadamente. A suíte de ciclo completo inicial concluiu um ano e a próxima temporada em cerca de 176 segundos no ambiente local, distribuídos em chamadas duráveis; isso não é o tempo de um clique.

## Acompanhamento após a entrega

- Conferir erros, p50/p95/p99, quantidade de continuações, dias e jogos por clique com dados reais e rede móvel.
- Consultar `cw_runtime_metrics` para chamadas, tempo acumulado/máximo, partidas e dias. Comparar com `pg_stat_statements` e logs; a tabela de métricas não substitui percentis detalhados.
- Acompanhar tamanho por tabela e crescimento por temporada. O banco não passa imediatamente de aproximadamente 266 MB para 10 MB: catálogos, Auth, sistema, índices, histórico preservado e espaço reutilizável continuam existindo.
- Monitorar a primeira manutenção, viradas de mês e temporada e carreiras avançadas. A ativação prevista considera os poucos saves existentes, com adiamento automático de qualquer motor humano ao vivo.
- Revisar os avisos restantes dos advisors por finalidade. Funções `SECURITY DEFINER` públicas precisam validar proprietário; tabelas privadas com RLS sem políticas são intencionais. Não abrir políticas genéricas para silenciar avisos. Referências: [RLS sem política](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [índices de chaves estrangeiras](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).

## Registro de liberação

Validação local concluída: restauração em dois bancos isolados; instalação e reaplicação sem divergências nos nove saves; ciclo doméstico e continental completo; ano estrangeiro resumido sem copiar elenco ou conceder progresso pessoal; parada de decisões, fechamento com proposta pendente, mês, transferências, ida/retorno de país, partida humana e duas conexões concorrentes. Interface verificada em 320, 360, 390, 768 e 1280 pixels; build, testes JS e lint dos arquivos alterados aprovados.

A instalação em produção depende da confirmação de execução solicitada pelo conector Supabase. Duas solicitações expiraram antes da aplicação. O frontend tem fallback somente para ausência da RPC nova (PGRST202), mantendo o backend anterior utilizável enquanto a confirmação está pendente; erros de sessão e outras falhas continuam sendo propagados. As otimizações do banco e as novas paradas só estarão ativas após a migração. Nenhuma aprovação de mudança de custo/plano foi solicitada.
