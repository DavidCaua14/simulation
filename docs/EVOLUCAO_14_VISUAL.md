# Etapa 14 — Reformulação e consistência visual

Só frontend (nenhuma mudança no banco). Testado no navegador com o app inteiro (360, 390 e 414 px; temas claro e escuro),
sem rolagem horizontal e sem erros no console.

## Padrão das telas

* **Topo:** o botão de tema claro/escuro saiu do topo de todas as telas (`AppShell`). A escolha continua em
  **Perfil → Conta** e no menu do avatar na Home. O lado direito do topo fica livre (prop `right`) e o título
  continua centralizado.
* **Peças compartilhadas** (`src/components/ui/feedback.jsx`, estilo em `styles/game-ui.css`), usadas em todas as telas
  novas e nas antigas que tinham texto solto:
  * `EmptyState`: estado vazio com ícone num escudo, título, explicação e ação (mercado, amigos, eventos, extrato,
    coleção, palpites, bilhetes).
  * `Skeleton`: carregamento no formato do conteúdo (lista, grade de cartas, painel) no lugar de "Carregando…".
  * `Notice`: aviso de sucesso/erro/informação com ícone e botão de fechar.
  * `RarityBadge`: selo de raridade com a cor oficial do tier (mercado, comparação, compra no mercado).
  * `ConfirmSheet`: confirmação de operações importantes — desfazer amizade, cancelar anúncio, descartar cartas
    (sempre que for mais de uma, ou uma Lenda/Épica), cancelar evento (admin). Compras, vendas, pacotes e cosméticos
    já tinham confirmação; pedir demissão também.
  * `RewardReveal`: o "momento especial" de recompensa conquistada (raios, troféu em escudo, itens aparecendo um a
    um). Usado no resgate de eventos e da sequência diária. Junto com a abertura de caixas, é o único lugar com efeito
    expressivo; as demais animações são curtas (entrada de listas, aviso) e respeitam "reduzir movimento".
  * `.gx-subtitle`: subtítulo de seção com a mesma barrinha dourada do `.gx-title`.

## Por tela

* **Loja:** cabeçalho de vitrine com escudo da raridade, contagem regressiva e "N novas para a coleção"; selo
  **Nova** nas cartas que você ainda não tem (sensação de descoberta); grade aparece com entrada escalonada; abas não
  "pulam" enquanto a loja carrega; avisos de erro no mesmo desenho do resto do app.
* **Mercado:** cada anúncio mostra raridade e, quando a mesma carta tem mais de uma oferta, **"menor preço"** ou
  **"+X% que o menor"**. Botão de comparar em cada carta → barra "Comparar" → tela lado a lado (nota, raridade,
  posição, clube, país, preço, **moedas por ponto de nota**, vendedor, prazo) com o melhor valor de cada linha em verde e
  compra direta. A confirmação de compra mostra quantas outras ofertas existem e a mais barata. Estados vazios com ação
  ("Anunciar uma carta", "Limpar filtros").
* **Perfil:** linhas de campo e o escudo do clube ao fundo do cabeçalho; avatar sem foto mostra a inicial do treinador
  na cor do tema equipado; "Carta em destaque" vazia vira um convite com silhueta de carta.
* **Eventos:** faixa **"Recompensa pronta"** e brilho suave só no evento que tem algo para resgatar; recompensas num
  quadro dourado; "Começa dd/mm" nos agendados; subtítulos com contagem; resgate abre o `RewardReveal`.
* **Home:** faixa de Eventos logo abaixo do ranking — "N recompensas prontas" (prioridade) ou o evento especial em
  andamento/próximo, com tempo real restante.
* **Campeonatos:** seletor de torneios numa linha só (desliza quando há 5, na Inglaterra) sem cortar nomes; título
  "INÍCIO" não perde mais o acento; botão "Próximo jogo · não gasta energia" sem quebrar em três linhas (antes dizia
  "sem energia", que parecia falta de energia).
* **Amigos:** botão de convite compacto em telas estreitas (o campo de username não fica espremido), lista com entrada
  suave, estados vazios e confirmação para desfazer amizade.
* **Caixas:** origem "Evento" e "Sequência diária" nas caixas recebidas dessas fontes.
