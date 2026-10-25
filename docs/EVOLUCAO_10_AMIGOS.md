# Etapa 10 — Amigos e convites

Tela **Amigos** (card "Amigos" na tela inicial — antes "Convites", travado — e atalho no Perfil).

## Adicionar por username
* Digita o username e convida. A busca é **exata** e não diferencia maiúsculas/minúsculas (mesma regra do username
  único da carreira). Busca parcial não funciona de propósito: ninguém consegue listar nomes de outros jogadores, e a
  resposta só diz se o convite foi enviado — nunca e-mail, id ou outros dados.
* Bloqueado: convidar a si mesmo, convite duplicado, amizade duplicada (índice único do par, nas duas direções).
* Se a outra pessoa já tinha te convidado, enviar o convite **vira amizade** na hora.
* Remetente e destinatário ficam registrados; tudo persiste no banco (sair e entrar mantém amigos e convites).
* Anti-spam configurável: até 20 convites por hora, 50 pendentes, 200 amigos (`friends_config`).

## Convites e estados na tela
Convite enviado ("aguardando", com Cancelar) · convite recebido (aceitar/recusar) · convite aceito / amigo adicionado
· convite recusado (quem convidou vê "recusou seu convite" por 7 dias e pode convidar de novo) · usuário inexistente ·
solicitação já existente ("Vocês já são amigos" / "Você já enviou um convite"). Desfazer amizade no perfil do amigo.

**Tempo real:** a tabela `friendships` está na publicação do Supabase Realtime (cada usuário só recebe as próprias
linhas pela RLS); a tela também se atualiza a cada 30 s e ao voltar para o app, como garantia.

## Perfil do amigo
Abre ao tocar no amigo. **Somente leitura**, só para amigos ("Só amigos podem ver este perfil" para os demais), com o
que o dono deixou público (Etapa 9): foto, nome, nível, nacionalidade, visual equipado, carta em destaque, insígnias
conquistadas e — se ele permitir — clube, estatísticas, títulos e coleção. Não existe nenhuma função que altere dados
de outro jogador: todas as funções de perfil agem só sobre a carreira de quem chama.

## Testes
`supabase/evolution/tests/friends_tests.sql` (F1–F6) — **todos passaram**: convite por username (maiúsculas/espaços),
duplicado, a si mesmo, inexistente e busca parcial recusados, convite mútuo vira amizade; recusa visível para quem
convidou, reenviar e aceitar; só o destinatário responde, cancelar some para ele; perfil só para amigos e respeitando
a privacidade; desfazer e convidar de novo; limite por hora; o app não grava amizades e cada um só vê as próprias.

Navegador: lista de amigos, perfil do amigo (moldura, fundo e carta em destaque dele), todos os estados de convite,
aceitar, cancelar, tema claro em 360 px. Defeito achado no teste e corrigido: o botão Convidar espremia o campo do
username.
