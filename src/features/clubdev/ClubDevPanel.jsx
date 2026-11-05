import { useCallback, useEffect, useMemo, useState } from 'react'
import { ArrowUpRight, Building2, Dumbbell, Eye, GraduationCap, Hammer, HandCoins, Repeat, Search, Star, TrendingDown, TrendingUp, UserPlus } from 'lucide-react'
import { clubMoney } from '../seasons/utils/clubMoney'
import { dateLabel, searchPlayers } from '../seasons/services/careerWorldApi'
import { getClubById } from '../club/data/clubs'
import { imageUrl } from '../match25d/kit'
import { POS_NAME, POS_ORDER } from '../seasons/utils/managerUtils'
import { ART, FACILITIES, FOCUS, INTENSITY, REPUTATION_STEPS, STAFF } from './clubDevData'
import { fetchClubDev, hireStaff, listForLoan, requestLoan, requestScout, respondLoan, setLearning, setSetPieces, setTraining, upgradeFacility } from './clubDevApi'
import './clubdev.css'

const SECTIONS = [
  { id: 'training', label: 'Treino', Icon: Dumbbell },
  { id: 'facilities', label: 'Estrutura', Icon: Building2 },
  { id: 'staff', label: 'Comissão', Icon: UserPlus },
  { id: 'youth', label: 'Base', Icon: GraduationCap },
  { id: 'loans', label: 'Empréstimos', Icon: Repeat },
  { id: 'scouting', label: 'Olheiros', Icon: Eye },
]

const range = (p) => (p?.potential_range ? `${p.potential_range[0]}–${p.potential_range[1]}` : p?.potential ?? '—')
const Stars = ({ n, max = 5 }) => (
  <span className="cd-stars" aria-label={`Nível ${n} de ${max}`}>
    {Array.from({ length: max }, (_, i) => (
      <Star key={i} size={13} fill={i < n ? 'currentColor' : 'none'} />
    ))}
  </span>
)

function Trend({ p }) {
  const v = Number(p?.dev || 0)
  if (!v) return <span className="cd-trend">—</span>
  return (
    <span className={`cd-trend ${v > 0 ? 'up' : 'down'}`}>
      {v > 0 ? <TrendingUp size={13} /> : <TrendingDown size={13} />} {v > 0 ? '+' : ''}
      {v.toFixed(1)}
    </span>
  )
}

// CLUBE: treino, estrutura, comissão técnica, base, empréstimos e observação (decisões validadas no servidor).
export default function ClubDevPanel({ players = [], notify, onChanged, initialSection = null }) {
  const [dev, setDev] = useState(null)
  const [error, setError] = useState('')
  const [section, setSection] = useState(initialSection || 'training')
  const [busy, setBusy] = useState(null)

  const load = useCallback(async () => {
    try {
      setDev(await fetchClubDev())
      setError('')
    } catch (e) {
      setError(e.message)
    }
  }, [])
  useEffect(() => {
    queueMicrotask(load)
  }, [load])

  const act = async (key, fn, okText) => {
    if (busy) return
    setBusy(key)
    try {
      const r = await fn()
      if (r && r.approved === false) notify?.(r.reason, 'alert')
      else if (okText) notify?.(typeof okText === 'function' ? okText(r) : okText, 'ok')
      await load()
      onChanged?.()
    } catch (e) {
      notify?.(e.message, 'alert')
    } finally {
      setBusy(null)
    }
  }

  if (error) return <p className="cd-note is-bad">{error}</p>
  if (!dev) return <p className="cd-note">Carregando o clube…</p>
  if (dev.unavailable)
    return (
      <div className="cd-unavailable">
        <img src={ART.obras_infraestrutura} alt="" />
        <p>Treino, estrutura, comissão técnica, base e empréstimos chegam com a próxima atualização do servidor. Seu progresso atual continua igual.</p>
      </div>
    )
  if (!dev.employed) return <p className="cd-note">Você precisa estar empregado em um clube para gerir a estrutura.</p>

  return (
    <div className="cd">
      <ReputationCard rep={dev.reputation} />
      <nav className="cd-tabs" aria-label="Gestão do clube">
        {SECTIONS.map(({ id, label, Icon }) => (
          <button key={id} type="button" className={section === id ? 'is-on' : ''} aria-pressed={section === id} onClick={() => setSection(id)}>
            <Icon size={16} />
            <span>{label}</span>
            {id === 'loans' && dev.loans?.some((l) => l.status === 'offered' && l.origin === 'ai_offer') && <em className="cd-dot" />}
          </button>
        ))}
      </nav>
      <div className="cd-body">
        {section === 'training' && <TrainingSection dev={dev} players={players} busy={busy} act={act} />}
        {section === 'facilities' && <FacilitiesSection dev={dev} busy={busy} act={act} />}
        {section === 'staff' && <StaffSection dev={dev} busy={busy} act={act} />}
        {section === 'youth' && <YouthSection dev={dev} players={players} />}
        {section === 'loans' && <LoansSection dev={dev} players={players} busy={busy} act={act} />}
        {section === 'scouting' && <ScoutSection dev={dev} busy={busy} act={act} />}
      </div>
    </div>
  )
}

function ReputationCard({ rep }) {
  if (!rep) return null
  const v = Number(rep.reputation || 0)
  const idx = REPUTATION_STEPS.reduce((acc, s, i) => (v >= s.at ? i : acc), 0)
  const next = REPUTATION_STEPS[idx + 1]
  return (
    <section className="cd-rep" aria-label="Reputação do treinador">
      <div>
        <small>Reputação</small>
        <b>{Math.round(v)}</b>
      </div>
      <div className="cd-rep-bar">
        <i style={{ width: `${Math.min(100, v)}%` }} />
        {REPUTATION_STEPS.slice(1).map((s) => (
          <span key={s.at} style={{ left: `${s.at}%` }} />
        ))}
      </div>
      <p>
        Hoje: <b>{REPUTATION_STEPS[idx].label}</b>.{' '}
        {next ? (
          <>
            Com <b>{next.at}</b>: {next.label.toLowerCase()}.
          </>
        ) : (
          'Você está no topo.'
        )}{' '}
        Credibilidade {Math.round(Number(rep.credibility || 0))}.
      </p>
    </section>
  )
}

function TrainingSection({ dev, players, busy, act }) {
  const t = dev.training || { focus: 'balanced', intensity: 'normal' }
  const sp = dev.set_pieces || {}
  const [learnFor, setLearnFor] = useState(null)
  const outfield = players.filter((p) => p.position !== 'GOL')
  const sorted = useMemo(() => [...players].sort((a, b) => Number(b.dev || 0) - Number(a.dev || 0)), [players])
  return (
    <>
      <section className="cd-card">
        <header>
          <h3>Foco da semana</h3>
          <small>O foco direciona a evolução mensal de todo o elenco. Jovens com minutos em campo evoluem mais.</small>
        </header>
        <div className="cd-chips">
          {FOCUS.map((f) => (
            <button key={f.id} type="button" className={t.focus === f.id ? 'is-on' : ''} disabled={Boolean(busy)} onClick={() => act('focus', () => setTraining(f.id, t.intensity), 'Plano de treino atualizado')}>
              <b>{f.label}</b>
              <small>{f.text}</small>
            </button>
          ))}
        </div>
        <div className="cd-seg" role="radiogroup" aria-label="Intensidade">
          {INTENSITY.map((i) => (
            <button key={i.id} type="button" role="radio" aria-checked={t.intensity === i.id} className={t.intensity === i.id ? 'is-on' : ''} disabled={Boolean(busy)} title={i.text}
              onClick={() => act('int', () => setTraining(t.focus, i.id), 'Intensidade atualizada')}>
              {i.label}
            </button>
          ))}
        </div>
      </section>

      <section className="cd-card">
        <header>
          <h3>Entrosamento com a formação</h3>
          <small>Cada jogo numa formação aumenta o entrosamento; formações esquecidas perdem um pouco por mês.</small>
        </header>
        <ul className="cd-bars">
          {(dev.familiarity || []).map((f) => (
            <li key={f.formation}>
              <span>{f.formation}</span>
              <i>
                <em style={{ width: `${f.value}%` }} className={f.value >= 85 ? 'ok' : f.value >= 65 ? 'mid' : 'low'} />
              </i>
              <b>{f.value}</b>
            </li>
          ))}
        </ul>
      </section>

      <section className="cd-card">
        <header>
          <h3>Cobradores</h3>
          <small>O cobrador de pênalti escolhido bate quando estiver em campo.</small>
        </header>
        <div className="cd-takers">
          {[
            ['penalty', 'Pênalti'],
            ['free_kick', 'Falta'],
            ['corner', 'Escanteio'],
          ].map(([k, label]) => (
            <label key={k}>
              <span>{label}</span>
              <select
                value={sp[k] || ''}
                disabled={Boolean(busy)}
                onChange={(e) => {
                  const next = { penalty: sp.penalty, freeKick: sp.free_kick, corner: sp.corner, [k === 'free_kick' ? 'freeKick' : k]: e.target.value || null }
                  act('sp', () => setSetPieces(next), 'Cobradores salvos')
                }}
              >
                <option value="">Automático (melhor finalizador)</option>
                {outfield.map((p) => (
                  <option key={p.id} value={p.id}>
                    {p.short_name || p.name} ({p.overall})
                  </option>
                ))}
              </select>
            </label>
          ))}
        </div>
      </section>

      <section className="cd-card">
        <header>
          <h3>Evolução do elenco</h3>
          <small>Potencial em faixa: o olheiro-chefe estreita a estimativa. Toque em um atleta para treinar uma nova posição.</small>
        </header>
        <ul className="cd-dev">
          {sorted.map((p) => (
            <li key={p.id}>
              <button type="button" onClick={() => setLearnFor(learnFor === p.id ? null : p.id)} aria-expanded={learnFor === p.id}>
                <span className="cd-pos">{p.position}</span>
                <span className="cd-name">
                  {p.short_name || p.name}
                  {p.regen && <em className="cd-tag">Base · fictício</em>}
                </span>
                <span className="cd-ovr">{p.overall}</span>
                <span className="cd-pot" title="Potencial estimado">
                  {range(p)}
                </span>
                <Trend p={p} />
              </button>
              {p.learning_pos && (
                <div className="cd-learn">
                  Aprendendo {POS_NAME[p.learning_pos] || p.learning_pos}
                  <i>
                    <em style={{ width: `${p.learning_progress || 0}%` }} />
                  </i>
                </div>
              )}
              {learnFor === p.id && (
                <div className="cd-learn-pick">
                  <span>Treinar posição:</span>
                  {POS_ORDER.filter((pos) => pos !== p.position && (pos === 'GOL') === (p.position === 'GOL') && !(p.learned || []).includes(pos) && !(p.secondary || []).includes(pos)).map((pos) => (
                    <button key={pos} type="button" className={p.learning_pos === pos ? 'is-on' : ''} disabled={Boolean(busy)}
                      onClick={() => act('learn', () => setLearning(p.id, p.learning_pos === pos ? null : pos), p.learning_pos === pos ? 'Treino de posição cancelado' : `Treino de ${POS_NAME[pos]} iniciado`)}>
                      {pos}
                    </button>
                  ))}
                  {(p.learned || []).length > 0 && <small>Já aprendeu: {p.learned.join(', ')}</small>}
                </div>
              )}
            </li>
          ))}
        </ul>
      </section>
    </>
  )
}

function FacilitiesSection({ dev, busy, act }) {
  return (
    <>
      <p className="cd-note">
        Orçamento livre {clubMoney(dev.budget)} · fundo de infraestrutura {clubMoney(dev.infrastructure)}. A diretoria usa o fundo primeiro e só aprova obras que o caixa sustenta.
      </p>
      <div className="cd-grid">
        {(dev.facilities || []).map((f) => {
          const meta = FACILITIES[f.kind]
          const src = f.kind === 'stadium' ? imageUrl('stadium') : meta.art(f.level)
          const building = Boolean(f.building_until)
          return (
            <article key={f.kind} className={`cd-fac ${building ? 'is-building' : ''}`}>
              <div className="cd-fac-art">
                <img src={src} alt="" loading="lazy" />
                {building && <img className="cd-fac-works" src={ART.obras_infraestrutura} alt="" />}
              </div>
              <div className="cd-fac-info">
                <h4>{meta.label}</h4>
                <Stars n={f.level} />
                <small>{meta.effect}</small>
                {building ? (
                  <p className="cd-build">
                    <Hammer size={14} /> Obra para o nível {f.target_level} até {dateLabel(f.building_until)}
                  </p>
                ) : f.level < 5 ? (
                  <>
                    <p className="cd-cost">
                      Nível {f.level + 1}: {clubMoney(f.next_cost)} · {f.next_months} meses
                    </p>
                    <button type="button" className="cd-btn" disabled={Boolean(busy)} onClick={() => act(`fac-${f.kind}`, () => upgradeFacility(f.kind), (r) => `Obra aprovada! Conclusão em ${dateLabel(r.building_until)}.`)}>
                      <ArrowUpRight size={15} /> Pedir obra à diretoria
                    </button>
                  </>
                ) : (
                  <p className="cd-cost">Nível máximo</p>
                )}
              </div>
            </article>
          )
        })}
      </div>
    </>
  )
}

function StaffSection({ dev, busy, act }) {
  return (
    <div className="cd-grid">
      {(dev.staff || []).map((s) => {
        const meta = STAFF[s.role]
        return (
          <article key={s.role} className="cd-staff">
            <img src={meta.art()} alt="" loading="lazy" />
            <div>
              <h4>{meta.label}</h4>
              <Stars n={s.level} />
              <small>{meta.effect}</small>
              <p className="cd-cost">{s.monthly_salary > 0 ? `${clubMoney(s.monthly_salary)}/mês` : 'Equipe original (sem custo extra)'}</p>
              {s.level < 5 && (
                <button type="button" className="cd-btn" disabled={Boolean(busy)} onClick={() => act(`staff-${s.role}`, () => hireStaff(s.role, s.level + 1), `${meta.label} nível ${s.level + 1} contratado`)}>
                  <UserPlus size={15} /> Contratar nível {s.level + 1} · {clubMoney(s.next_salary)}/mês
                </button>
              )}
              {s.level > s.initial_level && (
                <button type="button" className="cd-btn ghost" disabled={Boolean(busy)} onClick={() => act(`staff-${s.role}`, () => hireStaff(s.role, s.initial_level), 'Profissional dispensado; volta a equipe original')}>
                  Voltar à equipe original
                </button>
              )}
            </div>
          </article>
        )
      })}
    </div>
  )
}

function YouthSection({ dev, players }) {
  const youth = players.filter((p) => p.regen)
  const lvl = dev.facilities?.find((f) => f.kind === 'youth')?.level ?? 1
  return (
    <>
      <section className="cd-hero">
        <img src={ART.categorias_base} alt="" />
        <div>
          <h3>Categorias de base</h3>
          <p>
            No início de cada temporada a base revela {1 + (lvl >= 3) + (lvl >= 5)} jovem(ns). Estrutura e técnico da base melhores revelam mais potencial. Os jovens são
            fictícios, criados só nesta carreira, e aparecem marcados.
          </p>
        </div>
      </section>
      {youth.length === 0 ? (
        <p className="cd-note">Nenhum jovem revelado ainda nesta carreira.</p>
      ) : (
        <ul className="cd-dev">
          {youth.map((p) => (
            <li key={p.id}>
              <div className="cd-row">
                <span className="cd-pos">{p.position}</span>
                <span className="cd-name">
                  {p.short_name || p.name} <em className="cd-tag">{p.age} anos</em>
                </span>
                <span className="cd-ovr">{p.overall}</span>
                <span className="cd-pot">{range(p)}</span>
                <Trend p={p} />
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  )
}

function MiniSearch({ placeholder, render }) {
  const [q, setQ] = useState('')
  const [list, setList] = useState(null)
  const [loading, setLoading] = useState(false)
  const run = async (e) => {
    e?.preventDefault()
    setLoading(true)
    try {
      setList(await searchPlayers({ p_query: q.trim(), p_position: '', p_region: '', p_club: '', p_max_value: null, p_page: 0, p_country: '' }))
    } catch {
      setList([])
    } finally {
      setLoading(false)
    }
  }
  return (
    <div className="cd-search">
      <form onSubmit={run}>
        <Search size={16} />
        <input className="input" value={q} onChange={(e) => setQ(e.target.value)} placeholder={placeholder} aria-label={placeholder} />
        <button type="submit" className="cd-btn" disabled={loading}>
          Buscar
        </button>
      </form>
      {list && (list.length === 0 ? <p className="cd-note">Nenhum atleta encontrado.</p> : <ul className="cd-dev">{list.slice(0, 12).map(render)}</ul>)}
    </div>
  )
}

function LoansSection({ dev, players, busy, act }) {
  const [share, setShare] = useState(1)
  const [role, setRole] = useState('starter')
  const own = dev.club_id
  const offers = (dev.loans || []).filter((l) => l.status === 'offered' && l.parent_club === own)
  const active = (dev.loans || []).filter((l) => l.status === 'active')
  return (
    <>
      {!dev.window_open && <p className="cd-note is-warn">Janela de transferências fechada: empréstimos só começam com a janela aberta.</p>}
      {offers.length > 0 && (
        <section className="cd-card">
          <header>
            <h3>Propostas recebidas</h3>
          </header>
          <ul className="cd-dev">
            {offers.map((l) => (
              <li key={l.id}>
                <div className="cd-row">
                  <span className="cd-name">
                    {l.player} → {getClubById(l.borrower_club)?.name || l.borrower_club}
                  </span>
                  <small>
                    paga {Math.round(l.wage_share * 100)}% do salário · {l.role === 'starter' ? 'titular' : 'rodízio'} · até {dateLabel(l.ends_on)}
                  </small>
                  <button type="button" className="cd-btn" disabled={Boolean(busy)} onClick={() => act('loan', () => respondLoan(l.id, true), 'Empréstimo aceito')}>
                    Aceitar
                  </button>
                  <button type="button" className="cd-btn ghost" disabled={Boolean(busy)} onClick={() => act('loan', () => respondLoan(l.id, false), 'Proposta recusada')}>
                    Recusar
                  </button>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
      <section className="cd-card">
        <header>
          <h3>Empréstimos ativos</h3>
        </header>
        {active.length === 0 ? (
          <p className="cd-note">Nenhum atleta emprestado agora.</p>
        ) : (
          <ul className="cd-dev">
            {active.map((l) => (
              <li key={l.id}>
                <div className="cd-row">
                  <span className="cd-name">{l.player}</span>
                  <small>
                    {l.parent_club === own ? `em ${getClubById(l.borrower_club)?.name || l.borrower_club}` : `de ${getClubById(l.parent_club)?.name || l.parent_club}`} · volta em {dateLabel(l.ends_on)}
                  </small>
                </div>
              </li>
            ))}
          </ul>
        )}
      </section>
      <section className="cd-card">
        <header>
          <h3>Liberar para empréstimo</h3>
          <small>Atletas listados recebem propostas de outros clubes enquanto a janela estiver aberta.</small>
        </header>
        <ul className="cd-dev">
          {players
            .filter((p) => !p.on_loan)
            .sort((a, b) => a.overall - b.overall)
            .slice(0, 18)
            .map((p) => (
              <li key={p.id}>
                <label className="cd-row cd-toggle">
                  <span className="cd-pos">{p.position}</span>
                  <span className="cd-name">{p.short_name || p.name}</span>
                  <span className="cd-ovr">{p.overall}</span>
                  <input type="checkbox" checked={Boolean(p.loan_listed)} disabled={Boolean(busy)} onChange={(e) => act('list', () => listForLoan(p.id, e.target.checked), e.target.checked ? 'Atleta disponível para empréstimo' : 'Atleta retirado da lista')} />
                </label>
              </li>
            ))}
        </ul>
      </section>
      <section className="cd-card">
        <header>
          <h3>Pedir um atleta emprestado</h3>
          <small>Clubes só emprestam quem está fora dos 14 principais do elenco. Você define quanto do salário paga e o papel prometido.</small>
        </header>
        <div className="cd-loan-terms">
          <label>
            Salário pago por você
            <select value={share} onChange={(e) => setShare(Number(e.target.value))}>
              {[0.5, 0.75, 1].map((v) => (
                <option key={v} value={v}>
                  {v * 100}%
                </option>
              ))}
            </select>
          </label>
          <label>
            Papel prometido
            <select value={role} onChange={(e) => setRole(e.target.value)}>
              <option value="starter">Titular</option>
              <option value="rotation">Rodízio</option>
              <option value="prospect">Promessa</option>
            </select>
          </label>
        </div>
        <MiniSearch
          placeholder="Nome do atleta"
          render={(p) => (
            <li key={p.id}>
              <div className="cd-row">
                <span className="cd-pos">{p.position}</span>
                <span className="cd-name">
                  {p.short_name || p.name} <small>{getClubById(p.club_id)?.short || p.club_id || 'livre'}</small>
                </span>
                <span className="cd-ovr">{p.overall}</span>
                <button type="button" className="cd-btn" disabled={Boolean(busy) || p.club_id === own || !p.club_id} onClick={() => act('req', () => requestLoan(p.id, share, role), 'Empréstimo acertado! O atleta já está no elenco.')}>
                  <HandCoins size={15} /> Pedir
                </button>
              </div>
            </li>
          )}
        />
      </section>
    </>
  )
}

function ScoutSection({ dev, busy, act }) {
  const lvl = dev.staff?.find((s) => s.role === 'scout')?.level ?? 1
  return (
    <>
      <section className="cd-hero">
        <img src={ART.olheiros} alt="" />
        <div>
          <h3>Departamento de observação</h3>
          <p>
            Atletas de outros clubes aparecem com atributos aproximados e potencial em faixa. Um relatório revela os valores exatos em {Math.max(2, 14 - 2 * lvl)} dias. Até{' '}
            {1 + lvl} relatórios ao mesmo tempo.
          </p>
        </div>
      </section>
      {dev.scouting?.length > 0 && (
        <section className="cd-card">
          <header>
            <h3>Relatórios</h3>
          </header>
          <ul className="cd-dev">
            {dev.scouting.map((s) => (
              <li key={s.player_id}>
                <div className="cd-row">
                  <span className="cd-name">{s.player}</span>
                  <small>{s.ready ? 'Pronto' : `pronto em ${dateLabel(s.ready_on)}`}</small>
                </div>
              </li>
            ))}
          </ul>
        </section>
      )}
      <section className="cd-card">
        <header>
          <h3>Observar atleta</h3>
        </header>
        <MiniSearch
          placeholder="Nome do atleta"
          render={(p) => (
            <li key={p.id}>
              <div className="cd-row">
                <span className="cd-pos">{p.position}</span>
                <span className="cd-name">
                  {p.short_name || p.name} <small>{getClubById(p.club_id)?.short || p.club_id || 'livre'}</small>
                </span>
                <span className="cd-ovr">{p.overall}</span>
                <span className="cd-pot">{range(p)}</span>
                <button type="button" className="cd-btn" disabled={Boolean(busy) || p.scouted} onClick={() => act('scout', () => requestScout(p.id), (r) => `Relatório pedido; pronto em ${dateLabel(r.ready_on)}`)}>
                  <Eye size={15} /> {p.scouted ? 'Conhecido' : 'Observar'}
                </button>
              </div>
            </li>
          )}
        />
      </section>
    </>
  )
}
