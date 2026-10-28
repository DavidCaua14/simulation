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
