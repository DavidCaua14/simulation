#!/usr/bin/env node
// Testa o SQL do modo online em um PostgreSQL embutido e descartável (PGlite), sem acessar o Supabase.
// Uso: node scripts/test-online-db.mjs [--calibrate]
// --calibrate roda também 500 partidas do motor online e mostra médias e tempos (alguns minutos).
// O PGlite não é dependência do jogo. Instale em qualquer pasta e aponte PGLITE_DIR para ela:
//   npm install --prefix <pasta> @electric-sql/pglite
//   PGLITE_DIR=<pasta> node scripts/test-online-db.mjs
import { readFileSync, readdirSync } from 'node:fs'
import { createRequire } from 'node:module'
import { dirname, join, resolve } from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const ONLINE = join(ROOT, 'supabase', 'online')

async function loadPGlite() {
  const base = process.env.PGLITE_DIR ? resolve(process.env.PGLITE_DIR) : ROOT
  try {
    const entry = createRequire(join(base, 'package.json')).resolve('@electric-sql/pglite')
    return (await import(pathToFileURL(entry).href)).PGlite
  } catch {
    console.error('PGlite não encontrado. Veja as instruções no topo deste arquivo.')
    process.exit(2)
  }
}

const PGlite = await loadPGlite()
const db = new PGlite()
const files = [
  join(ONLINE, 'tests', 'support', 'stub.sql'),
  ...readdirSync(ONLINE).filter((f) => /^\d+_.*\.sql$/.test(f)).sort().map((f) => join(ONLINE, f)),
]
// Reaplica o esquema: precisa funcionar duas vezes seguidas.
files.push(...files.slice(1))
files.push(join(ONLINE, 'tests', 'online_tests.sql'))
const calibrate = process.argv.includes('--calibrate')

for (const file of files) {
  const started = Date.now()
  try {
    await db.exec(readFileSync(file, 'utf8'))
  } catch (e) {
    console.error(`FALHA em ${file}\n${e.message}`)
    process.exit(1)
  }
  console.log(`ok ${file.slice(ROOT.length + 1)} (${Date.now() - started} ms)`)
}
console.log('Todos os testes do modo online passaram.')
if (calibrate) {
  const started = Date.now()
  const res = await db.exec(readFileSync(join(ONLINE, 'tests', 'calibration.sql'), 'utf8'))
  console.table(res.at(-2).rows)
  console.log(`calibração em ${Math.round((Date.now() - started) / 1000)} s`)
}
