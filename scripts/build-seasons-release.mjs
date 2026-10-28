#!/usr/bin/env node
// Produz um único SQL transacional para revisão/aplicação no SQL Editor.
import { readFile, writeFile, mkdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const files = ['15_season_integrity.sql', '16_match_simulation.sql', '17_season_draws.sql', '18_swiss_certificates.sql', '19_opponent_analysis.sql', '20_pending_calendar_repair.sql']
const target = path.resolve(process.argv[2] || '/workspace/scratch/seasons-v2.sql')
let sql = '-- RELEASE SEASONS V2: fazer backup e executar preflight_seasons.sql antes.\n-- Gerado; não edite este arquivo. Todas as alterações são atômicas.\nbegin;\n'
for (const name of files) {
  const source = await readFile(path.join(root, 'supabase/evolution', name), 'utf8')
  sql += `\n-- FILE: ${name}\n` + source.split('\n').filter((line) => !/^\s*(begin|commit);\s*$/i.test(line)).join('\n') + '\n'
}
sql += "\nset constraints all immediate;\nnotify pgrst,'reload schema';\ncommit;\n"
await mkdir(path.dirname(target), { recursive: true })
await writeFile(target, sql)
console.log(target)
console.log('SHA256', createHash('sha256').update(sql).digest('hex'))
