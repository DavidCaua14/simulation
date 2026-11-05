// Runs 2026-11-reset.sql through the Supabase Management API.
// Usage: SUPABASE_ACCESS_TOKEN=... node supabase/maintenance/reset/run.mjs <dry|apply> [project-ref]
// "dry" executes everything and rolls back, printing the step log. "apply" commits.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const mode = process.argv[2];
const ref = process.argv[3] || 'nkdbixmfsochlprcvkxl';
if (!['dry', 'apply'].includes(mode)) throw new Error('mode must be dry or apply');
const token = process.env.SUPABASE_ACCESS_TOKEN;
if (!token) throw new Error('SUPABASE_ACCESS_TOKEN required');
const dir = path.dirname(fileURLToPath(import.meta.url));
const sql = fs.readFileSync(path.join(dir, '2026-11-reset.sql'), 'utf8').replace('__APPLY__', mode === 'apply' ? 'true' : 'false');
const t = Date.now();
const r = await fetch(`https://api.supabase.com/v1/projects/${ref}/database/query`, {
  method: 'POST',
  headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
  body: JSON.stringify({ query: sql }),
});
const text = await r.text();
const secs = Math.round((Date.now() - t) / 1000);
if (mode === 'dry') {
  const m = text.match(/DRY RUN OK (\[.*\])/);
  if (m) { console.log(`dry run ok in ${secs}s`); for (const s of JSON.parse(m[1].replace(/\\"/g, '"'))) console.log(JSON.stringify(s)); }
  else { console.log(`dry run FAILED in ${secs}s (HTTP ${r.status})`); console.log(text.slice(0, 2000)); process.exitCode = 1; }
} else {
  console.log(`apply HTTP ${r.status} in ${secs}s`);
  console.log(text.slice(0, 2000));
  if (!r.ok) process.exitCode = 1;
}
