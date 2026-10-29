# Cartas base e recompensas

## Inventário de dependências antes da alteração

Frontend: App (rota cards), Home/useInbox/DailyRewardsModal/CardsHub/useCollectionSummary, CardsScreen/CollectionTab/InboxTab/BoxOpener, CardView/AutoCard, StoreScreen (vitrines/roleta/mercado/energia/visual/extrato), ProfileScreen/FeaturedCardPanel/FriendProfile/privacidade, EventsScreen/StreakPanel/AdminEvents/RewardChip, SeasonsScreen/PostMatch, TeamTab/Pitch/PlayerPicker/PlayerSheet/MatchLive/MatchLineupEditor. Serviços cardsApi/storeApi/profileApi/managerApi/eventsApi. Não há URL independente: a navegação é controlada no App.

Banco: cards/card_tiers/user_cards/reward_boxes/box_sources/career_card_state; shop_sections/shop_prices/shop_purchases; wheel_config/wheel_segments/wheel_state/wheel_spins; market_listings/market_events/market_config/market_price_limits; event_rewards/event_objectives/event_completions/streak_rewards; player_profiles.featured_card; careers/wallet_ledger/econ_requests; sim_players/sim_player_attrs/sim_player_pos_ratings/mgr_players/mgr_lineups/mgr_coach/mgr_matches/season_fixtures. As RPCs de aquisição, gatilhos de vitória/eventos e funções administrativas precisam ser bloqueados no servidor, além da remoção dos componentes.

## Conversão v1 (definida antes de executar)

| Carta, por cópia | Moedas | Diamantes | Energia bônus |
| --- | ---: | ---: | ---: |
| Destaque | 2300 | 16 | 2 |
| Lenda | 21600 | 130 | 4 |
| Épica | 43200 | 260 | 6 |

Destaques e lendas usam os tetos das tabelas atuais da loja, iguais para todas as cópias da mesma raridade. Épicas recebem o dobro de moedas/diamantes de uma lenda. Energia cresce por raridade e não expira no reset. Quantidades são multiplicadas integralmente, sem reduzir saldos anteriores. Cartas reservadas em anúncios ativos retornam ao inventário antes da conversão. Anúncios já vendidos não geram ressarcimento adicional. A compensação registra origem, quantidade, versão e valores efetivos em auditoria com chave única por carreira/origem, em conjunto com os lançamentos da carteira.

Caixas pendentes, se existirem, são encerradas com compensação determinística: valor de descarte da carta da raridade + teto de moedas/diamantes/energia que a caixa concedia. Para a caixa base, o valor da carta é seu descarte (15 moedas), mantendo o jogador não sorteado como recurso equivalente, sem criar novas cartas. Caixas já abertas permanecem apenas como histórico. A consulta inicial encontrou 109 cópias base, 24 Destaques nos inventários e nenhuma caixa pendente; anúncios reservados são contabilizados separadamente na prévia final.

## Regras finais

- CardView/AutoCard existentes são reutilizados, sempre como base. Overall de Temporadas vem do elenco/posição atual, não do overall estático de uma carta antiga. Nenhum atributo é regravado para adaptar o visual.
- Cartas base possuídas continuam no inventário, com suas quantidades. Cada atleta aparece uma vez por carreira: cópias não permitem escalar o mesmo jogador duas vezes. O vínculo usa cards.player_key = sim_players.id, sem aproximações de nome; a migração aborta se uma carta possuída não tiver correspondência.
- Atletas base possuídos integram o clube comandado naquela carreira, mantendo condição, lesões, suspensões e histórico. A sincronização acompanha mudanças de clube; partidas já abertas mantêm seus participantes/estado. Não altera o catálogo mundial nem outras carreiras.
- Loja mantém energia, troca de diamantes, visuais e extrato. O mercado antigo só negociava cartas especiais e é encerrado; históricos financeiros e de compras são preservados para auditoria.
- Partidas pagam somente moedas, com uma energia bônus adicional nas vitórias, incluindo vitória nos pênaltis. Empate/derrota mantêm suas moedas existentes; XP de partida deixa de ser concedido. XP/níveis já acumulados e prêmios próprios de encerramento de competições são preservados.
- Eventos/sequência diária continuam, com recursos, visuais e insígnias; caixas/cartas deixam de ser recompensas. Recompensas futuras de caixas/cartas são substituídas por recursos segundo a tabela, sem pagar novamente conclusões antigas. Objetivos impossíveis de abertura/coleta/negociação e insígnias ainda bloqueadas desses mecanismos são aposentados; conquistas já obtidas ficam no histórico.
- Catálogo especial e tabelas antigas necessários a chaves estrangeiras/históricos ficam arquivados, com aquisição e acesso público bloqueados. Não se apagam resultados, economia antiga, identidades, amizades, privacidade ou personalizações.
- Manutenção permanece ativa até ordem explícita do titular.

## Validação e implantação

Testar em PostgreSQL local antes de implantar: quantidades/raridades, anúncios reservados, caixas pendentes, soma dos três recursos, reaplicação sem pagamento duplicado, mapeamento base e mudança de clube, isolamento/RLS, vitórias/empates/derrotas/pênaltis/repetição, eventos e bloqueio das RPCs antigas. Testar login e interfaces em tela pequena e desktop, incluindo filtro, banco, detalhe e cansaço. Produção: nova cópia lógica privada e comparação de resultados/progresso, prévia de compensação, aplicação transacional e conferência final. Nenhum teste pode avançar carreiras reais permanentemente.

## Prévia de produção

Na conferência anterior à migração: 24 cópias Destaque nos inventários e uma Lenda reservada em anúncio, distribuídas por sete carreiras. Compensação prevista: 76.800 moedas, 514 diamantes e 52 energias bônus. Nenhuma caixa pendente. Há 109 cópias base, todas com correspondência exata de jogador. A cópia lógica privada contém 119 tabelas e os metadados/funções anteriores; não é um ponto de restauração gerenciado pelo provedor.

Para reproduzir os testes locais: `python scripts/build-base-card-functions.py`, `node scripts/build-base-cards-release.mjs`, `python scripts/test-seasons-db.py --base-cards --ui-fixtures /tmp/base-cards-ui-fixtures.json`, `python tests/base_cards_ui_smoke.py /tmp/base-cards-ui-fixtures.json`. O Vite deve estar disponível localmente na porta 5173; navegador e API são fictícios/interceptados. As opções `--skip-existing-tests` e `--keep-db` servem apenas para depuração local, após validar a suíte existente.

## Implantação concluída

Migrações 21–23 aplicadas no Supabase real em uma transação com verificações adicionais de backup, crédito esperado por carreira, integridade e manutenção. Resultado confirmado: 25 cópias especiais convertidas em sete carreiras, 76.800 moedas/514 diamantes/52 energias bônus; 109 cópias base mantidas e 106 atletas vinculados, sem jogador elegível faltando no elenco. Zero inventários especiais, caixas pendentes, anúncios ativos ou RPCs antigas acessíveis aos papéis da API. Nenhuma recompensa de partida retroativa foi criada.

Preservação confirmada: nove carreiras, 17 temporadas, 14.190 partidas, 7.952 resultados e uma partida v1 em andamento. Comparações dentro da transação protegeram resultados, estado individual dos atletas, saldos anteriores, perfil (exceto destaque removido), formações/táticas, insígnias/visuais conquistados e lançamentos financeiros anteriores. O vínculo entre carta base e jogador usa o identificador exato, não semelhança de nomes.

Validações aprovadas: suíte anterior do treinador/competições, continuidade v1, calendário e sorteios, calibração; testes novos de todos os níveis de raridade/quantidades/escrow/caixas, RLS, importação e mudança de clube, vitória/empate/derrota/pênaltis, partida v2 real fictícia até o fim, resgates, reaplicação e duas conexões simultâneas. Navegador com API inteiramente interceptada: 390/1280 px, clubes brasileiros/europeus, login e recuperação de sessão, campo/banco/filtros/ficha/cansaço, loja/extrato, perfil/eventos, alteração do time ao vivo e pós-jogo. Chamadas de validação no Supabase real percorreram as nove carreiras (hub/elenco/ficha/perfil/energia/visuais/eventos/isolamento) e foram revertidas ao final; não avançaram partidas reais. Build aprovado; lint dos componentes novos verificados passou. O lint geral ainda contém 50 erros existentes nas demais partes do projeto.

Também foi corrigido o botão "Simular até o fim" para retomar o relógio caso a partida estivesse pausada, problema encontrado no teste integrado. A manutenção permanece ativa e não foi publicada nenhuma mudança na configuração do ambiente de nuvem.
