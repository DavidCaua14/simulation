# Regressão de sessão

Na raiz do repositório:

```sh
node --test tests/sessionRecovery.test.mjs tests/maintenance.test.mjs
npm run build
```

Teste no navegador (requer Python com Playwright e `/usr/bin/chromium`):

```sh
npm run dev -- --host 127.0.0.1 --port 5173 --strictPort
# Em outro terminal, na raiz do repositório:
python tests/session_smoke.py
```

O teste lê somente a URL do projeto no `.env` para interceptar a API. Usa sessões fictícias e intercepta todas as chamadas ao Supabase: não consulta nem modifica dados reais. A manutenção permanece ativa; a sessão simulada usa o email administrativo para testar o fluxo do jogo.

Cenários: JWT rejeitado ao carregar carreira e ao iniciar uma partida; falha de servidor com nova tentativa; refresh token revogado; renovação válida; criação de personagem apenas após consulta bem-sucedida sem carreira. Confirma preservação de um valor no armazenamento local e ausência de repetição automática da mutação da partida.

# Temporadas v2

A validação isolada do banco e os testes do navegador estão descritos em [TEMPORADAS_V2.md](../docs/TEMPORADAS_V2.md). `tests/seasons_ui_smoke.py` exige respostas fictícias geradas pelo runner SQL e intercepta as chamadas ao Supabase.

# Carreira completa

Cobertura dos 13 tópicos, regras, execução das suítes e preparação da implantação: [CARREIRA_COMPLETA.md](../docs/CARREIRA_COMPLETA.md).

`test-seasons-db.py --career-world --world-cycle` instala em PostgreSQL descartável, valida isolamento/reaplicação e percorre o calendário com uma transação por RPC. Os testes de navegador usam API interceptada e não acessam dados reais.

# Jornada do treinador (simulação longa)

`python tests/career_world_journey.py <container> <banco>` (ou `PG_LOCAL=1` com `PGHOST`/`PGPORT`) num banco
descartável `simulation_validation_*` com as evoluções 24–34. Joga o calendário dia a dia com uma transação por
chamada, troca de liga duas vezes e verifica IA de mercado, janelas, satisfação, contratos, propostas e mensagens.

# Recompensas pendentes de períodos anteriores

Com Vite em `127.0.0.1:5173`, executar `python tests/pending_rewards_ui_smoke.py`. O teste intercepta todas as chamadas ao Supabase e verifica a navegação Home → resgate de recompensa antiga → Home sem aviso, atualização ao retornar à aba e ao vencer o prazo, e sequência diária válida. Usa sessões e recompensas fictícias, sem alterar dados reais.

A cobertura SQL de isolamento, prazo e resgate idempotente integra `scripts/test-seasons-db.py --scoped-runtime`. Detalhes em [RECOMPENSAS_PENDENTES.md](../docs/RECOMPENSAS_PENDENTES.md).

# Mercado e contratos

`test-seasons-db.py --scoped-runtime --skip-existing-tests` inclui a evolução 53 e os testes de cota por registro, salário, luvas, orçamento, retenção da IA e concorrência real. Para a interface, com Vite ativo: `python tests/career_world_ui_smoke.py <fixtures.json> --market-policy`. O teste usa API interceptada em 320 e 1280 pixels. Consulte [INTEGRIDADE_MERCADO.md](../docs/INTEGRIDADE_MERCADO.md) para as regras e garantias de preservação.

# Escala financeira dos clubes

A evolução 54 mantém os valores canônicos e apresenta reais completos nos formulários e extratos. `node --test tests/clubMoney.test.mjs` cobre a conversão e a separação da carteira pessoal. O runner `--scoped-runtime --skip-existing-tests` inclui prêmio no caixa do clube, contratação direta de atleta livre, partida ao vivo e doze fechamentos mensais de Sport e Flamengo. A interface pode ser testada com `python tests/career_world_ui_smoke.py <fixtures.json> --club-economy`, sem chamadas reais ao Supabase. Detalhes em [ECONOMIA_DOS_CLUBES.md](../docs/ECONOMIA_DOS_CLUBES.md).
