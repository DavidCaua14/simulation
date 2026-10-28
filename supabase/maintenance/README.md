# Manutenção temporária

Preservar o progresso é requisito: estes scripts não modificam dados, não revogam sessões, não executam migrations do jogo e não limpam armazenamento local.

## Ativar

1. Publique o commit da interface na Vercel (o push na main dispara o deploy).
2. Execute `01_enable.sql` no SQL Editor do projeto Supabase. O script recusa substituir outro hook preexistente. Execute `verify.sql` para validar a função; confirme também na Data API com as duas contas, pois o teste SQL não prova a aplicação do hook pelo PostgREST.
3. Em uma conta de testador, confirme que uma leitura REST/RPC recebe HTTP 503; na conta `contatodavidcaua@gmail.com`, confirme que continua acessível. Não faça atualizações no banco antes dessa confirmação.

A interface começa em manutenção e consulta `/maintenance.json` a cada 10 segundos, ao recuperar foco/conexão e ao voltar à aba. O jogo e seu áudio são desmontados durante o bloqueio. Não há logout nem limpeza de dados. A conta administrativa é liberada pelo email da sessão; o bloqueio efetivo da API usa o email do JWT validado. A regra não depende de `user_metadata`.

**Abas com a versão anterior:** não possuem o código necessário para mostrar a nova tela sem recarregar. O SQL bloqueia suas próximas requisições Data API, mas elas podem exibir erros da interface antiga até atualizar. O primeiro deploy não consegue injetar a tela nas abas antigas. Requisições já iniciadas podem terminar. A verificação automática vale para abas que já carregaram esta implementação.

O hook atua apenas na Data API do PostgREST (REST/RPC). Não bloqueia Auth, Storage, Realtime, conexões SQL, jobs ou Edge Functions. Chamadas com service_role continuam funcionando para preservar a operação de serviços. Não pausa o relógio das temporadas nem o processamento automático do jogo. Antes de modificar dados, é necessário avaliar esses processos e obter backup pelo painel do Supabase. Nenhum job foi alterado por este commit.

## Reabrir quando a atualização terminar

1. Execute `02_disable.sql` no SQL Editor; confirme o acesso REST/RPC de um testador.
2. Altere somente `enabled` para `false` em `public/maintenance.json`, mantendo o restante da configuração, e publique o commit. As abas da nova versão detectam a liberação automaticamente, sem apagar sessão ou progresso.

Mantenha `enabled: true` e o hook ativos durante as próximas etapas. Em falha de rede/configuração da manutenção, a nova interface bloqueia por precaução. Para reativar no futuro, publique `enabled: true` e execute `01_enable.sql` novamente.
