Quero transformar o **Modo Temporadas** em um modo carreira completo de treinador de futebol, inspirado no PES 2013, FIFA/EA Sports FC e outros simuladores de gestão esportiva. Analise a arquitetura atual do projeto e implemente os sistemas de forma integrada, realista e persistente, sem comprometer as funcionalidades existentes.

## 1. Carreira do treinador e mercado de trabalho

- Ao criar o treinador, sua nacionalidade deve influenciar as oportunidades iniciais, mas não limitar sua carreira. Um treinador vinculado ao futebol brasileiro pode receber propostas de clubes europeus, e vice-versa.
- As propostas devem depender do desempenho, títulos, reputação, experiência, situação do clube interessado e nível de exigência da competição.
- Permita receber propostas de emprego, negociar condições contratuais, aceitar ou recusar ofertas e trocar de clube.
- Clubes de maior prestígio devem exigir resultados melhores. Demissões, títulos e boas campanhas devem alterar a reputação do treinador.
- Uma demissão por resultados ruins ou má gestão financeira deve reduzir a credibilidade no mercado e dificultar o recebimento de boas propostas.
- Preserve o histórico profissional, os títulos, as temporadas disputadas e as passagens por cada clube.

## 2. Temporadas brasileira e europeia em paralelo

Implemente a simulação simultânea do futebol brasileiro e europeu, mesmo quando o usuário estiver jogando em apenas uma dessas regiões.

- Os campeonatos devem avançar conforme o calendário, independentemente de o usuário acompanhar suas partidas.
- Ao término de cada competição, gere notícias informando o campeão, o adversário derrotado na final, quando houver, e o melhor jogador da equipe campeã, considerando seu desempenho real naquela competição.
- Inclua ligas, copas nacionais e torneios continentais disponíveis no banco de dados, respeitando participantes, classificações e calendários.
- No Brasil, considere Brasileirão, Copa do Brasil e Libertadores. Na Europa, considere as ligas disponíveis, copas nacionais e Champions League.
- Quando houver limitações de ligas ou equipes cadastradas, complete os torneios com equipes predefinidas, mantendo coerência com as vagas conquistadas e os resultados anteriores.
- Gere notícias sobre títulos, disputas acirradas, eliminações surpreendentes, recordes e campanhas relevantes.

A simulação deve funcionar mesmo sem partidas europeias visíveis para o usuário, mas os resultados precisam ser armazenados para manter a continuidade da carreira.

## 3. Orçamento, salários e saúde financeira

Cada clube deve possuir uma situação financeira própria, com orçamento inicial proporcional ao seu porte, receitas, despesas e capacidade de investimento.

- Considere reputação, torcida, receitas comerciais, premiações, desempenho esportivo e situação financeira para definir o poder econômico dos clubes.
- Os salários dos jogadores e da comissão técnica devem ser pagos com os recursos do clube, de acordo com os contratos.
- Registre receitas, despesas, salários, custos de transferências, premiações e investimentos em um histórico financeiro.
- Permita que o treinador injete suas próprias moedas no clube para aumentar o orçamento disponível para contratações, com registro da operação e atualização dos saldos pessoal e do clube.
- Diferencie o saldo pessoal do treinador do patrimônio financeiro da equipe.
- Caso o clube apresente risco financeiro elevado, reduza sua capacidade de contratação e aumente a pressão da diretoria. Se o treinador continuar administrando mal os recursos, poderá ser demitido.
- O clube nunca deve falir ou desaparecer. Deve existir um mecanismo de recuperação financeira, com restrições de gastos, vendas de jogadores e redução do orçamento.
- Evite salários, receitas e orçamentos infinitos ou desproporcionais à realidade dos clubes.

## 4. Mercado de transferências internacional

Implemente um mercado de transferências global, permitindo negociações entre clubes brasileiros, sul-americanos e europeus, independentemente da região em que o treinador esteja trabalhando.

- Se o treinador estiver no Brasil, deve poder enviar propostas por jogadores de clubes europeus e de outros países disponíveis no jogo.
- Se estiver na Europa, deve poder negociar jogadores de clubes brasileiros e sul-americanos, além de clubes europeus.
- Não restrinja as contratações à liga atual, à nacionalidade do treinador ou à região do clube controlado pelo usuário.
- Considere as janelas de transferência, a situação contratual do jogador, as regras aplicáveis e a disponibilidade financeira dos clubes envolvidos.
- Permita pesquisar jogadores de outros países, consultar suas informações, avaliar seu valor de mercado e iniciar negociações normalmente.
- A transferência internacional deve seguir as mesmas etapas de negociação entre clubes e negociação com o atleta utilizadas nas transferências nacionais.
- Considere diferenças de orçamento, prestígio, salários, interesse esportivo e disposição dos clubes em negociar.
- Após a conclusão, atualize o clube do jogador, o elenco, a escalação, o contrato, o orçamento e o histórico de transferências de forma consistente.

**Regra essencial:** um treinador que trabalha em um clube brasileiro pode contratar um jogador de um clube europeu, e um treinador que trabalha na Europa pode contratar um jogador de um clube sul-americano. O sistema deve permitir essas operações de forma funcional, não apenas exibir jogadores estrangeiros na pesquisa.

## 5. Negociação entre clubes

O processo de contratação deve começar pela negociação com o clube proprietário do jogador.

- O treinador escolhe um jogador e envia uma proposta ao clube proprietário.
- A proposta pode incluir valor fixo, bônus, parcelas e, se o sistema permitir, troca de jogadores.
- O clube pode aceitar, recusar ou apresentar uma contraproposta.
- A decisão deve considerar valor de mercado, idade, potencial, overall, duração do contrato, importância no elenco, desempenho recente, necessidade financeira, interesse em negociar e existência de outras propostas.
- Considere rivalidade entre clubes, poder financeiro do comprador, reputação das ligas e interesse esportivo do atleta.
- Enquanto a negociação estiver pendente, os dias devem avançar normalmente, com partidas e acontecimentos do calendário.
- Respeite as janelas de transferência e os prazos definidos para responder às propostas.

## 6. Negociação com o jogador

Após o acordo entre os clubes, inicie a negociação contratual com o atleta.

- Permita negociar salário, duração do contrato, bônus, luvas e papel no elenco, conforme os recursos existentes no jogo.
- O jogador deve avaliar o projeto esportivo, o prestígio do clube, a competição disputada, o salário oferecido, a titularidade prometida e sua situação atual.
- Considere também a preferência por determinadas ligas, a distância ou mudança de país, quando esses fatores fizerem parte do sistema de simulação.
- O atleta pode recusar a proposta ou apresentar contrapropostas.
- A transferência somente será concluída quando as duas etapas forem aprovadas e os recursos necessários estiverem disponíveis.
- Considere contratos expirados, pré-contratos e outras regras de transferência quando aplicáveis e compatíveis com o sistema.

Toda negociação deve ter estados claros, prazos, histórico de ofertas e feedback ao usuário. Uma proposta não pode permanecer pendente indefinidamente.

## 7. Transferências dos outros clubes

O mercado deve continuar ativo em todo o mundo do jogo, não apenas no clube controlado pelo usuário.

- Simule negociações entre os demais clubes brasileiros, sul-americanos e europeus durante cada janela.
- Considere as necessidades dos elencos, orçamento, qualidade dos jogadores, idade, posições carentes e estratégias de cada equipe.
- Os clubes devem contratar, vender, renovar contratos e liberar atletas de forma coerente com sua situação.
- Clubes menores podem vender seus destaques para equipes maiores, enquanto clubes ricos podem disputar jogadores valorizados.
- Grandes transferências devem gerar notícias com jogador, clube de origem, clube de destino e valor da negociação, quando disponível.
- Inclua movimentações internacionais mesmo que o usuário esteja treinando em outra região.
- Evite transferências duplicadas, jogadores em dois clubes simultaneamente e negociações incompatíveis com os contratos.

## 8. Propostas recebidas para vender jogadores

Os clubes adversários devem poder apresentar propostas pelos jogadores do usuário.

- O treinador poderá aceitar, recusar ou negociar uma contraproposta.
- Considere valor de mercado, importância tática, idade, potencial, contrato restante, interesse do atleta e situação financeira do clube comprador.
- O jogador também pode manifestar interesse em sair, especialmente por falta de oportunidades, salários incompatíveis, insatisfação com seu papel ou interesse de um clube mais competitivo.
- Quando houver insatisfação, o treinador deve receber avisos e ter oportunidades de resolver a situação com mais minutos em campo, mudança de função ou renovação contratual.
- Se o problema persistir, o atleta poderá solicitar transferência ou recusar a renovação.
- Não force vendas automaticamente: a decisão deve depender das regras contratuais e das circunstâncias da negociação.

## 9. Apresentação de grandes contratações

Quando uma contratação for considerada importante, apresente uma notícia ou tela especial de anúncio.

Considere o valor da transferência, o prestígio do jogador, seu overall, sua reputação e a relevância do clube contratante.

A apresentação deve exibir a carta base do jogador, nome, posição, overall, clube de origem, novo clube e valor da negociação, quando disponível. Utilize a identidade visual existente no jogo e não reintroduza cartas especiais, lendas ou destaques removidos anteriormente.

Contratações comuns devem seguir um fluxo mais simples para não tornar a navegação cansativa.

## 10. Imersão, notícias e passagem do tempo

Crie um sistema de notícias integrado à carreira, com acontecimentos relevantes do futebol brasileiro, sul-americano e europeu.

Inclua:
- Resultados e campeões das competições.
- Grandes contratações e vendas nacionais e internacionais.
- Propostas recebidas e negociações concluídas.
- Jogadores insatisfeitos ou que solicitam transferência.
- Situação financeira, pressão da diretoria e risco de demissão.
- Renovação e término de contratos.
- Desempenho individual, artilharia, recordes e premiações.

As notícias devem aparecer no momento adequado, com prioridade para acontecimentos relacionados ao clube do usuário. Evite repetições e informações contraditórias.

O avanço dos dias deve atualizar partidas, competições, negociações, contratos, finanças e acontecimentos do mercado. Não exija que o usuário abra cada campeonato para que ele continue evoluindo.

## 11. Inteligência dos clubes e realismo

Crie uma lógica de decisão para os clubes controlados pela simulação.

Cada clube deve considerar:
- Perfil financeiro e capacidade de investimento.
- Qualidade, idade e profundidade do elenco.
- Necessidades por posição.
- Objetivos da temporada e pressão da diretoria.
- Reputação, desempenho e potencial dos atletas.
- Estilo de jogo e necessidades táticas.
- Contratos, salários e satisfação dos jogadores.
- Atratividade de jogar em determinada liga e capacidade de competir internacionalmente.

As decisões devem apresentar variação e imprevisibilidade. Nem todo clube deve aceitar uma proposta alta, nem todo jogador deve aceitar o maior salário, e nem todas as equipes devem realizar transferências em todas as janelas.

## 12. Isolamento e persistência por usuário

Cada usuário deve possuir um universo de carreira independente, incluindo clubes, elencos, calendários, resultados, transferências, finanças, contratos, notícias e histórico.

- Os campeonatos brasileiros e europeus devem avançar no contexto da carreira individual.
- Os resultados e as transferências de um usuário nunca podem modificar os dados de outro.
- Utilize identificadores e relacionamentos consistentes para separar cada carreira, mesmo quando houver dados compartilhados de clubes e jogadores.
- Salve o estado da simulação para que o usuário possa sair e retornar sem perder o progresso.
- Evite duplicar partidas, transferências, salários ou notícias quando a simulação for retomada.

## 13. Regras de implementação e validação

Antes de desenvolver, analise o projeto atual, identifique os modelos, tabelas, serviços, controladores, rotas e telas existentes e planeje a integração dos novos sistemas.

Não crie funcionalidades isoladas que não conversem entre si. Utilize uma arquitetura modular, com serviços específicos para calendário, competições, mercado de transferências, contratos, finanças, notícias e carreira do treinador.

Implemente validações para datas, saldos, contratos, disponibilidade dos jogadores, janelas de transferência e concorrência de negociações. Utilize transações de banco de dados nas operações financeiras e transferências, garantindo consistência mesmo em caso de erro.

Preserve os sistemas já existentes, incluindo cartas base, escalações, partidas, táticas, recompensas e histórico. Não reintroduza funcionalidades removidas anteriormente.

**Prioridade:** desenvolva uma simulação de carreira consistente, na qual todas as decisões tenham consequências e o mundo do futebol continue evoluindo ao longo das temporadas.

Ao finalizar, teste o ciclo completo: início da carreira, avanço do calendário, encerramento de competições, geração de notícias, propostas de emprego, contratação e venda de jogadores entre países e continentes, negociação salarial, pagamento de salários, investimentos pessoais, insatisfação de atletas, demissões e retomada da carreira após sair do jogo.