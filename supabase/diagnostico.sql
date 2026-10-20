-- DIAGNÓSTICO (só leitura) — rode no SQL Editor, bloco por bloco.

-- 1) Os agendamentos existem e estão ativos?
select jobid, jobname, schedule, active from cron.job order by jobid;

-- 2) Últimas execuções dos jobs (succeeded/failed)
select j.jobname, d.status, d.return_message, d.start_time
from cron.job_run_details d join cron.job j using (jobid)
order by d.start_time desc limit 20;

-- 3) O QUE a Edge Function respondeu às chamadas do cron (401 = segredo errado / JWT; 200 = ok)
select id, status_code, left(content::text, 200) as resposta, created
from net._http_response order by created desc limit 15;

-- 4) Jogos esperando resultado há mais de 105 min
select id, home_team, away_team, kickoff_at, status
from matches
where status in ('scheduled','live') and kickoff_at < now() - interval '105 minutes'
order by kickoff_at;

-- 5) Bilhetes pendentes e a situação dos jogos deles
select tk.id as ticket, tk.status as ticket_status, m.home_team, m.away_team, m.status as match_status, m.home_score, m.away_score
from tickets tk join ticket_picks p on p.ticket_id = tk.id join matches m on m.id = p.match_id
where tk.status = 'pending' order by m.kickoff_at;
