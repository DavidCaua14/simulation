# Integridade do mercado, salários e contratos

## Problemas confirmados

1. O limite de seis contratações contava negociações em `agreed`, embora o atleta ainda não estivesse registrado. Em um save restaurado havia sete acordos para a próxima janela e zero contratações registradas. A mensagem também calculava a próxima janela a partir de uma data futura, podendo indicar uma espera maior que a necessária.
2. O serviço financeiro encerrava contratos em todos os países, enquanto o mercado regional renovava apenas no país ativo. Clubes de ligas inativas perdiam atletas sem a rotina equivalente de gestão.
3. A renovação da IA dependia do dia 15. Avanços por intervalos podiam pular essa data e chegar ao vencimento antes de uma avaliação de renovação.
4. O salário de um atleta livre perdia a referência do vínculo anterior e dependia fortemente da avaliação de mercado, que diminui com a idade. A exceção esportiva para veteranos deixava de proteger atletas de alta qualidade quando a idade era estimada ou a carreira já estava avançada.

## Regras corrigidas

### Propostas e registros

- Propostas, recusas, cancelamentos e acordos aguardando janela não consomem a cota.
- A cota de seis é verificada com contratações efetivamente registradas na janela do clube. O período tem começo e fim explícitos; a próxima janela é calculada após o fim da atual.
- Recibos internos de registro sobrevivem à limpeza do histórico detalhado de negociações. Repetir uma solicitação não duplica o registro nem os pagamentos.
- O registro bloqueia a carreira antes de verificar a cota. Duas assinaturas simultâneas disputam a mesma vaga de forma serializada.
- Um novo acordo que exceda as seis vagas permanece aprovado e aguarda a próxima janela, com reservas mantidas e data explicada. Não é perdido por expiração.
- Acordos que já estavam aprovados antes desta atualização são preservados. Eles seguem os termos anteriores e podem excepcionalmente superar a nova fiscalização da cota; registros novos passam a contar normalmente.

### Salários, luvas e viabilidade

- O piso mensal cresce com a avaliação esportiva do atleta e continua relevante mesmo para veteranos. O cálculo não modifica notas, idades ou salários já contratados.
- A pretensão considera o piso, o salário conhecido e o desnível de prestígio entre os clubes. O salário mensal precisa atingir a exigência: bônus elevados não substituem o piso.
- Atletas realmente livres exigem também luvas de pelo menos dois salários pretendidos. Não há taxa de transferência para um agente livre legítimo.
- O orçamento precisa suportar taxas, luvas, bônus, dívidas, as reservas existentes e seis meses do acréscimo da folha. A verificação acontece na proposta contratual e novamente no registro.
- Um grande desnível esportivo causa recusa independentemente do dinheiro oferecido ou da idade estimada. Atletas com nota 85+ toleram no máximo dez pontos de diferença para o prestígio do clube e recusam divisões inferiores; os demais toleram até quatorze pontos. Esses limites não impedem renovar um atleta que já pertence ao clube.
- A interface apresenta salário pretendido, luvas e motivo de incompatibilidade. Os formulários usam os valores fornecidos pelo servidor. O servidor aplica as mesmas restrições mesmo se a interface for contornada.

A curva salarial foi comparada com elencos e receitas locais de Sport, Flamengo, Barcelona, Arsenal e Manchester United. Valores continuam em moedas do simulador. Não há injeção de dinheiro, aumento retroativo de receitas nem alteração da carteira dos treinadores.

### Continuidade dos clubes da IA

- Ligas inativas mantêm seus vínculos por continuidade simplificada, sem simular partidas, transferências ou pagamentos fora do país ativo. Ao vencer, o prazo do contrato da IA é estendido preservando salário e proprietário.
- No país ativo, contratos da IA são avaliados antes do vencimento, sem depender de passar exatamente pelo dia 15. Renovações precisam caber em caixa e receita; o clube do usuário continua exigindo decisão do próprio treinador.
- Para corrigir o estoque histórico, um atleta livre com nota 80+ pode recuperar um vínculo da IA, uma única vez, quando há origem conhecida e capacidade financeira. Prioriza-se o último clube contratante conhecido, com o catálogo como referência quando o contrato antigo já foi arquivado.
- A recuperação exclui atletas vinculados, acordos ou negociações válidas em aberto e histórico de posse, passagem ou liberação por clubes comandados pelo usuário. Clubes sem condições financeiras não recebem o atleta por esse mecanismo.
- A busca projeta esse vínculo de forma somente leitura. A gravação ocorre numa ação real de negociação ou no próximo processamento normal dos contratos. Não é necessário criar campeonatos estrangeiros.
- Uma recuperação já realizada não se repete indefinidamente após outra liberação. Agentes livres legítimos continuam existindo e passam pelas exigências esportivas e financeiras.

## Preservação do progresso

A instalação não altera nenhuma linha preexistente dos saves: perfis, moedas, XP, níveis, resultados, jogadores, contratos, clubes e propostas. Novas tabelas privadas guardam apenas recibos de registro, a relação de acordos já aprovados e futuras recuperações da IA. Elas têm RLS habilitado e não são acessíveis diretamente pelo cliente.

Os atletas já contratados pelo usuário permanecem no elenco, inclusive as contratações mencionadas no relato. Salários e prazos desses contratos permanecem como foram assinados. As novas exigências valem para próximas decisões de contratação ou renovação. Não há multa, retirada de atleta ou cobrança retroativa.

A correção do mundo da IA ocorre durante as próximas ações normais; preserva o clube, os contratos e a data do treinador. Uma proposta ainda não aprovada segue sujeita à avaliação esportiva e financeira, como parte da negociação.

## Arquivos e liberação

- Fonte: `supabase/evolution/53_transfer_integrity.sql`.
- Migração nova: `supabase/migrations/*_realistic_transfer_integrity.sql`.
- Interface: `src/features/seasons/world/WorldPanel.jsx`.
- Não editar ou reaplicar migrações antigas em produção. Usar no arquivo o número efetivamente registrado pelo Supabase.
- A migração usa bloqueio das carreiras em ordem, limites de espera e comparações de contagem/hash em 17 tabelas protegidas. Qualquer diferença nessas linhas aborta a instalação.
- Backup privado atualizado dos nove saves restaurado em PostgreSQL local. Arquivos privados e chaves ficam fora do GitHub.

## Verificação

- Instalação e reaplicação comparadas com todas as linhas públicas preexistentes: sem mudanças.
- Save com sete acordos e zero registros: nova proposta válida aceita, data/carteira/acordos anteriores preservados; teste revertido.
- Save avançado com atletas de alto nível já no Sport: elenco e contratos do usuário intactos. Recuperação de 304 atletas da IA em cerca de 1,1 segundo na cópia local; teste revertido. Essa medição cobre essa rotina nesse save, não o tempo total de avançar uma partida.
- Testes de janela, repetição de pedido, histórico durável, recusa esportiva de veteranos, piso salarial, luvas, orçamento, renovação da IA, liga inativa e proteção de liberações humanas e negociações em aberto.
- Duas conexões simultâneas: uma sexta contratação concluída, um acordo preservado para julho, um único pagamento de luvas e nenhuma mudança de data ou carteira pessoal.
- Navegador em 320 e 1280 pixels com API interceptada: aviso de projeto incompatível, botão bloqueado, salário/luvas preenchidos pelo servidor e nenhum avanço de dia.
- Regressão do runtime regional, build de produção e lint do componente alterado.

Para repetir os testes locais: `python scripts/test-seasons-db.py --scoped-runtime --skip-existing-tests`. O runner instala a base, as evoluções e suas regressões; usa somente bancos novos descartáveis. Testes específicos: `supabase/evolution/tests/transfer_integrity_tests.sql` e `python tests/transfer_registration_concurrency.py <container-local> <simulation_validation_banco>`.

Com Vite em `127.0.0.1:5173` e fixtures geradas pelo runner, executar `python tests/career_world_ui_smoke.py <fixtures.json> --market-policy`. Todas as chamadas ao Supabase são interceptadas.

## Aplicação

A migração `20261103170252_realistic_transfer_integrity` foi aplicada no Supabase em 03/11/2026, após aprovação do aviso do conector. A comparação transacional das 17 tabelas protegidas concluiu sem diferenças. A verificação posterior confirmou a regra de cota, RLS nas três tabelas novas, auxiliares privados e zero recuperações de atletas executadas durante a instalação. No save antes bloqueado, os sete acordos continuavam pendentes e a contagem de contratações registradas era zero.

O piso de referência verificado para Lamine Yamal foi de 3.216 moedas mensais, antes dos ajustes da pretensão por vínculo e prestígio. Isso não muda o salário de contratos que já estavam assinados.
