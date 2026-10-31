# Histórico de migrações e integração Supabase

O check `Supabase Preview` da main falhou com `Remote migration versions not found in local migrations directory`. O banco tinha 27 versões aplicadas e o repositório continha somente a evolução de runtime `20261031223935`. As 26 versões anteriores haviam sido executadas antes da adoção dessa pasta pelo projeto.

A correção registra checkpoints para essas 26 versões com os mesmos números e nomes do histórico remoto. Cada arquivo informa também o hash MD5 dos comandos originais, para rastreabilidade. Esses arquivos não contêm SQL executável nem dados de usuários. A migração de runtime permanece integral e sem alteração.

Os comandos antigos foram preservados em uma exportação privada para auditoria. Não foram republicados nem reaplicados: várias entradas dependiam de respostas HTTP temporárias já removidas e uma delas provisionava um proprietário específico. Um checkpoint não pretende reproduzir esses comandos.

## Segurança da sincronização

- Nenhuma migração remota é marcada como revertida ou removida.
- O esquema e o progresso de produção não são modificados por esta correção.
- O CLI compara as versões existentes e encontra as 27 já aplicadas, sem alterações pendentes para o projeto atual.
- Não executar `db reset`, `migration repair --status reverted` ou reaplicar as evoluções 1–44 em produção.
- Novas mudanças continuam em novos arquivos de migração, depois da última versão aplicada.

## Banco vazio e previews novos

Os checkpoints reconciliam o histórico do projeto existente; não são um baseline de instalação. O projeto também contém mudanças manuais históricas e importadores não reproduzíveis, portanto não usar somente essa pasta para reconstruir uma base vazia.

O roteiro local reproduzível do jogo continua em `scripts/test-seasons-db.py --scoped-runtime`, que instala os módulos de esquema, catálogos e evoluções na ordem correta e só aceita um PostgreSQL local descartável. A restauração de snapshots privados está descrita em `OTIMIZACAO_RUNTIME_POR_PAIS.md`. Previews de banco vazios exigem um baseline separado e revisado, incluindo catálogos e permissões, antes de serem habilitados; esta correção não cria recursos pagos de preview.

Referências: [histórico de migrações](https://supabase.com/docs/reference/cli/supabase-migration-fetch) e [migrações do banco](https://supabase.com/docs/guides/deployment/database-migrations).

## Verificação da correção

O erro foi reproduzido em um PostgreSQL 17 local isolado e sem rede externa, com as 27 versões remotas em uma tabela de histórico de teste e somente a migração de runtime no diretório local. O Supabase CLI 2.122.0 produziu o mesmo erro do GitHub.

Depois de incluir os 26 checkpoints, `supabase db push --dry-run --skip-vault` informou `Remote database is up to date`. O teste confirmou que os dados fictícios protegidos e o histórico aplicado permaneceram iguais. Nenhum comando de alteração foi enviado ao banco de produção para esta correção.

Ao verificar uma liberação no GitHub, consultar os **commit statuses** e os **check runs**. A Vercel publica um status; o Supabase Preview publica um check separado. Um deploy aprovado pela Vercel não significa que os demais checks passaram.
