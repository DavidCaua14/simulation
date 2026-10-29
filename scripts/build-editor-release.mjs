import { readFileSync, writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
// Gera um script de colar no SQL Editor a partir de uma migração: UM ÚNICO comando (bloco DO) com a instalação,
// a conferência das impressões digitais dos dados de usuários e a verificação. Trecho parcial não roda; completo é tudo ou nada.
// Uso: node scripts/build-editor-release.mjs <migração> <saída> <função exigida> <função instalada> "<título>" "<mensagem de pré-requisito>"
const [migration, output, requires, installed, title, requiresMsg] = process.argv.slice(2)
const root = resolve(import.meta.dirname, '..')
const body = readFileSync(resolve(root, 'supabase/evolution', migration), 'utf8')
  .trim()
  .replace(/^(--.*\n)*begin;\s*/i, '')
  .replace(/\s*commit;\s*$/i, '')
  .replace(/^notify pgrst,'reload schema';$/m, "perform pg_notify('pgrst','reload schema');")
if (/\$install\$/.test(body)) throw new Error('A migração não pode conter a marca $install$')
const fingerprint = `select jsonb_build_object(
   'careers',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.careers c),
   'results',(select md5(coalesce(string_agg(to_jsonb(f)::text,'' order by id),'')) from public.season_fixtures f where status='played'),
   'live',(select md5(coalesce(string_agg(to_jsonb(m)::text,'' order by fixture_id),'')) from public.mgr_matches m where status='live'),
   'squads',(select md5(coalesce(string_agg(to_jsonb(p)::text,'' order by career_id,player_id),'')) from public.mgr_players p),
   'contracts',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by id),'')) from public.cw_contracts c),
   'clubs',(select md5(coalesce(string_agg(to_jsonb(c)::text,'' order by career_id,club_id),'')) from public.cw_clubs c),
   'negotiations',(select md5(coalesce(string_agg(to_jsonb(n)::text,'' order by id),'')) from public.cw_negotiations n),
   'messages',(select md5(coalesce(string_agg(concat_ws('|',id,career_id,kind,title,body,club_id,read,day_no),'' order by id),'')) from public.mgr_messages),
   'morale',(select md5(coalesce(string_agg(concat_ws('|',career_id,player_id,morale,transfer_requested,promised_role),'' order by career_id,player_id),'')) from public.cw_players))`
const out = `-- Gerado por scripts/build-editor-release.mjs a partir de ${migration}: ${title}.
-- ${requiresMsg}. Cole o arquivo INTEIRO no SQL Editor e execute.
-- É um único comando: ou instala tudo, ou nada muda. Pode ser executado de novo. A manutenção não é alterada.
-- Ao final compara as impressões digitais de carreiras, resultados, partidas ao vivo, elencos, contratos, caixas, negociações, mensagens
-- e satisfação; se alguma mudar, o comando é desfeito por inteiro.
do $install$
declare antes jsonb;depois jsonb;mudou text;
begin
 perform set_config('statement_timeout','120s',true);
 perform set_config('lock_timeout','10s',true);
 perform pg_advisory_xact_lock(hashtext('${migration}'));
 if to_regprocedure('${requires}') is null then raise exception '${requiresMsg}; nada foi alterado';end if;
 ${fingerprint} into antes;

-- ===================== evolução 34 =====================
${body}

 ${fingerprint} into depois;
 select string_agg(k,', ') into mudou from jsonb_object_keys(antes) k where antes->k is distinct from depois->k;
 if mudou is not null then raise exception 'Abortado: dados de usuários mudariam (%); nada foi alterado',mudou;end if;
 if to_regprocedure('${installed}') is null then raise exception 'Instalação incompleta; nada foi alterado';end if;
 raise notice 'Instalação concluída: ${title}; dados dos usuários preservados.';
end $install$;
select case when to_regprocedure('${installed}') is not null then 'Instalação concluída: ${title}; dados dos usuários preservados.' else 'Não instalado' end as resultado;
`
writeFileSync(resolve(root, output), out)
console.log(output)
