# Correção de contratação na entressafra

Uma proposta válida não podia ser assinada após o encerramento do campeonato regional: `mgr_offer_respond` ignorava a temporada devolvida por `cw_activate_region` e procurava apenas temporadas ativas. O jogador recebia “Atualize o calendário regional antes de assumir o clube”, enquanto a proteção de propostas impedia avançar o calendário sem uma decisão.

## Comportamento corrigido

- A contratação no país atual pode ser assinada durante a entressafra, na mesma data do save. A próxima temporada começa pelo fluxo normal do jogo.
- A temporada encerrada mantém o clube histórico, resumo, resultados e sequência originais. O novo vínculo altera o empregador atual e usa os valores negociados na proposta.
- Ao assumir em outro país cujo campeonato já terminou, o jogo prepara ou reutiliza o próximo calendário regional sem avançar a data global nem reabrir o campeonato encerrado.
- A mesma assinatura pode ser repetida com segurança: não duplica luvas nem contratos. A versão do runtime muda uma vez para impedir avanço com dados de uma aba antiga.
- As validações de proprietário, prazo da proposta, partida em andamento e capacidade financeira do clube continuam aplicadas.
- A interface informa quando a contratação ocorreu na entressafra e que a data foi mantida.

A instalação substitui somente a função e suas permissões, sem executar contratações ou avançar saves. O jogador deve tentar **Assinar contrato** novamente; não precisa avançar dias para desbloquear a proposta.

## Arquivos e aplicação

1. Fonte da função: `supabase/evolution/51_offseason_job_acceptance.sql`.
2. Migração nova em `supabase/migrations/*_offseason_job_acceptance.sql`, posterior às migrações existentes. Não editar nem reaplicar migrações antigas.
3. Antes da aplicação, manter um backup privado consistente por carreira, incluindo esquema e funções. Os snapshots não devem ser enviados ao GitHub.
4. A migração bloqueia as carreiras em ordem e compara contagem/hash dos dados protegidos antes e depois. Qualquer diferença aborta toda a transação.
5. Conferir a versão efetivamente registrada no Supabase e usar o mesmo número no arquivo local para manter o check Supabase Preview sincronizado.
6. Verificar a função, permissões, proposta e data após a instalação, sem aceitar a proposta em nome do jogador.

## Validação

- Backup privado das nove carreiras restaurado em PostgreSQL local isolado.
- Erro original reproduzido na cópia do save reportado.
- Migração e reaplicação verificadas comparando todas as linhas públicas preexistentes: sem mudança de dados.
- Na cópia, a proposta original foi aceita na mesma data, mantendo integralmente a temporada encerrada, jogadores, contratos de atletas, resultados, estatísticas, nível e XP. Luvas creditadas uma vez e condições contratuais conferidas.
- Repetição da assinatura, rejeição de aba desatualizada e avanço posterior de um dia testados. Todas as ações de jogo de teste foram revertidas.
- Testes sintéticos cobrem contratação durante a temporada, proposta vencida, partida em andamento, entressafra no mesmo país e troca internacional com calendário encerrado.
- Regressão do runtime regional, build de produção e lint do componente alterado executados.

Para repetir os testes locais, usar `python scripts/test-seasons-db.py --scoped-runtime`. O teste específico é `supabase/evolution/tests/offseason_job_acceptance_tests.sql` e só aceita bases descartáveis com prefixo `simulation_validation_`.

O utilitário de backup também recebeu uma correção nos filtros de registros órfãos: consultas correlacionadas que excediam o timeout foram substituídas por verificações diretas de relacionamento. O backup completo foi exportado e restaurado com esse filtro.

## Liberação

A migração `20261101153311_offseason_job_acceptance` foi aplicada no Supabase em 01/11/2026. A verificação posterior confirmou a função corrigida, execução permitida apenas ao papel autenticado e a proposta reportada ainda pendente, com os mesmos termos e a mesma data de jogo. Nenhuma contratação foi executada em produção para validar a correção.
