# Etapa 9 — Perfil do jogador e personalização

O perfil virou a página de identidade do jogador e passou a viver **no servidor**. Antes, a foto enviada, o banner e
a "vitrine" ficavam só no navegador (localStorage) — ninguém mais via, e a vitrine mostrava cartas de exemplo.
Na primeira visita depois da atualização, a foto enviada e o banner escolhido são migrados automaticamente (uma vez).

## O que aparece
* **Identidade:** avatar (foto enviada, foto do jogo ou a da criação), username, nacionalidade com bandeira, clube atual
  com escudo, nível e barra de XP, "no jogo desde", e o visual equipado (fundo, moldura, efeito, emblema e tema).
* **Carta em destaque:** escolhida da própria coleção.
* **Insígnias:** 18, com bronze/prata/ouro; as conquistadas em cor e as bloqueadas em cinza **com a regra de como
  conseguir** (só o dono vê as bloqueadas).
* **Carreira de treinador:** jogos, V/E/D, gols, temporadas. **Títulos:** competição, ano e clube.
* **Coleção:** cartas por raridade (real, do inventário).
* **O que os outros veem:** liga/desliga clube atual, estatísticas, títulos e coleção. Nome, foto, nível, insígnias
  conquistadas, carta em destaque e visual são sempre públicos (dados privados — e-mail, saldo, ids — nunca aparecem).
* **Som do jogo** (faixas e controles) e **Conta** (tema, sair) mantidos.

## Regras de negócio no servidor
* **Carta em destaque:** só uma carta que o jogador tem agora. Se ela for vendida, anunciada no mercado ou descartada
  até zerar, um gatilho tira o destaque na hora (e a montagem do perfil confere de novo).
* **Insígnias:** concedidas só pelo servidor, a partir de dados que só ele grava — títulos (`mgr_spells`), nível,
  partidas e temporadas (`mgr_coach`), **maior sequência de vitórias** (calculada das partidas jogadas), cartas
  diferentes conquistadas, Épica na coleção, venda no mercado e temporada de 2026 concluída. Ficam registradas com o
  valor que as liberou. O app não consegue gravar insígnias (testado).
* **Cosméticos** (Loja → **Visual**): 5 molduras, 4 fundos premium + os 8 fundos grátis que já existiam, 3 efeitos,
  5 emblemas e 4 temas — desenhos originais em CSS. Comprados com diamantes (livro de transações, idempotente, sem
  compra repetida). A compra dá a propriedade; equipar decide o que aparece. Só dá para equipar o que é seu e no espaço
  certo. São **puramente visuais**: não alteram cartas nem atletas — a loja diz isso em cada item.
* **Prévia antes da compra:** o item aparece aplicado no SEU perfil, e a lista mostra "é seu", "em uso" ou o preço.
* **Avatar:** só JPEG recortado pelo app (até ~90 KB) ou uma foto pronta do jogo; qualquer outra coisa é recusada.

## Testes
`supabase/evolution/tests/profile_tests.sql` (P1–P7) — **todos passaram**: perfil criado no servidor; carta em
destaque só própria e removida ao anunciar; insígnias concedidas pelo servidor (coleção, Épica e **5 vitórias seguidas**
de verdade), sem duplicar, e o app não grava insígnias; cosméticos (grátis, compra única e idempotente, equipar só o
que tem, espaço certo, desequipar); privacidade (o visitante não vê o que foi escondido, nem ids internos, nem
insígnias bloqueadas); avatar validado e migração única; permissões.

Navegador: migração do banner antigo, aviso de insígnia nova, escolha da carta em destaque, personalizar, privacidade,
temas claro e escuro, Loja → Visual (prévia, comprar e usar). Dois defeitos achados no teste e corrigidos: a carta em
destaque saía sem estilo (faltava importar o CSS das cartas) e as miniaturas da Loja ficavam invisíveis (o CSS da
identidade agora é um arquivo próprio, usado no Perfil, na Loja e no perfil de amigos).
