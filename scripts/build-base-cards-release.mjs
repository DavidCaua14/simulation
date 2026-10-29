import { readFile, writeFile, mkdir } from 'node:fs/promises'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { createHash } from 'node:crypto'
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')
const files = ['21_base_cards.sql', '22_base_card_functions.sql', '23_base_card_migration.sql']
let sql = '-- Cartas base: backup + preflight obrigatórios. Pacote transacional gerado.\nbegin;\nset local lock_timeout=\'5s\';\nset local statement_timeout=\'90s\';\n'
for (const name of files) {
  const source = await readFile(path.join(root, 'supabase/evolution', name), 'utf8')
  sql += `\n-- FILE: ${name}\n` + source.split('\n').filter((line) => !/^\s*(begin|commit);\s*$/i.test(line)).join('\n') + '\n'
}
sql += "set constraints all immediate;\nnotify pgrst,'reload schema';\ncommit;\n"
const target = path.resolve(process.argv[2] || path.join(root, 'supabase/releases/cartas_base.sql'))
await mkdir(path.dirname(target), { recursive: true })
await writeFile(target, sql)
console.log(target, createHash('sha256').update(sql).digest('hex'))
