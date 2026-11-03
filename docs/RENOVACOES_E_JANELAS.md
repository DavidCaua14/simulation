# Renovações e janela de transferências

A evolução 55 fecha as exceções que permitiam contratar atletas livres fora da janela e renovar indefinidamente jogadores de elite em um projeto incompatível. Não altera retroativamente contratos, salários, elencos ou resultados dos saves existentes.

## Regras

- Toda nova negociação de contratação exige janela aberta no país do clube comprador. Isso inclui atletas livres, pré-contratos, contrapropostas de compra e apresentação do contrato ao atleta. A contratação de um atleta livre continua sendo negociada diretamente com ele, sem taxa ao clube.
- Nenhum registro de contratação é concluído com a janela do comprador fechada. A restrição também vale para a IA, elencos curtos e acordos antigos. As outras validações de orçamento, salário, projeto e limite de registros continuam valendo.
- Acordos já aprovados aguardam a próxima janela. O adiamento não cancela o acordo nem movimenta caixa, muda o elenco ou consome uma contratação. Os compromissos reservados acompanham a nova data de registro. A aprovação não garante conclusão caso as demais condições do acordo deixem de ser atendidas.
- Renovações de atletas do próprio elenco podem ser negociadas e concluídas com a janela fechada. É necessário comprovar tanto a posse atual do atleta quanto um contrato ainda vigente com o mesmo clube. Um vínculo vencido, uma negociação antiga ou a identificação da negociação como renovação não permite contratar outro atleta.
- Ao tentar renovar, o atleta avalia o salário atualizado e o nível esportivo do clube. Pertencer ao elenco não concede dispensa dessas exigências. As condições do contrato atual continuam valendo até o término; não há reajuste compulsório dos contratos antigos.
- Um atleta incompatível com o projeto pode recusar já na abertura da renovação. Propostas de renovação ainda pendentes também passam pela avaliação ao serem respondidas. A recusa não rescinde o vínculo atual. Sem renovação aprovada, o atleta fica livre quando o contrato vence, pelo fluxo normal do jogo.
- Termos de acordos já aprovados antes da política de integridade continuam protegidos pela regra de transição existente; a janela de registro e a exigência de posse nas renovações se aplicam a todos.
- A janela de atletas não restringe propostas de emprego do treinador. A carteira pessoal, moedas, nível, energia, títulos e histórico permanecem separados dessas operações.

## Implementação e implantação

1. Exportar backup privado dos saves e das definições atuais. Não versionar dados pessoais, arquivos de backup nem credenciais.
2. Restaurar o backup em banco local descartável, incluindo contratos, elencos, resultados, permissões e funções.
3. Aplicar `supabase/evolution/55_renewal_window_rules.sql` nas instalações de desenvolvimento. Para produção, usar somente a nova migração de mesmo nome em `supabase/migrations`, com sua versão registrada no Supabase. Não modificar migrações antigas.
4. A migração bloqueia as carreiras na mesma transação e compara contagens e hashes de vinte tabelas de progresso antes e depois. Qualquer divergência aborta a implantação. Apenas definições de funções e permissões são atualizadas; nenhum dia de jogo é avançado.
5. Verificar a preservação de todas as tabelas existentes na cópia local, aplicar novamente e repetir a comparação para comprovar idempotência.
6. Executar os testes de servidor e interface abaixo, build e lint. Em produção, verificar apenas definições e permissões; nunca aceitar propostas ou avançar saves como teste.
7. Publicar no `main`, conferir Supabase Preview e Vercel e manter a versão do arquivo local igual à versão efetivamente instalada no Supabase.

## Validação

- `python scripts/test-seasons-db.py --scoped-runtime --skip-existing-tests`: evolução, reaplicação, preservação, fluxos de carreira, economia, concorrência e regressões de renovação/janelas.
- `supabase/evolution/tests/renewal_window_tests.sql`: renovação de salário legado, recusa de salário baixo, renovação fora da janela, recibos idempotentes, validação de posse, APIs de contratação fechadas, acordos preservados até a próxima janela, IA sem exceção por elenco curto, recusa de elite e saída somente após o vencimento. Todas as ações sintéticas são revertidas.
- `python tests/career_world_ui_smoke.py <fixtures> --renewal-window`: telas de 320 e 1280 pixels; contratação livre, compra e pré-contrato bloqueados na janela fechada; formulário de renovação utilizável; negociações abertas continuam funcionando; nenhuma data avança nesses cenários.
- `npm run build` e lint dos componentes alterados.

Os valores de clube continuam armazenados em milhares de reais, conforme a evolução 54: `80` corresponde a R$ 80.000. Nenhum multiplicador é aplicado novamente aos dados salvos.

## Resultado desta implantação

Migração de produção: `20261103191928_renewal_window_rules.sql`. A aplicação e reaplicação na restauração local dos nove saves passaram sem alterar valores de nenhuma tabela existente. A proteção atômica verificou 180 comparações nas vinte tabelas de progresso. Suíte de servidor, concorrência, quatro cenários de interface, build, lint e testes de utilitários aprovados. As funções instaladas e permissões foram verificadas em produção sem executar ações nas carreiras.
