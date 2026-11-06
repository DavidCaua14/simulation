import { useCallback, useEffect, useRef, useState } from 'react'
import { RotateCcw, Search, SlidersHorizontal, Star } from 'lucide-react'
import ClubCrest from '../../club/components/ClubCrest'
import { getClubById } from '../../club/data/clubs'
import { isSessionError } from '../../../lib/sessionRecovery'
import { requestLoan, listForLoan } from '../../clubdev/clubDevApi'
import MoneyKeypad from '../components/MoneyKeypad'
import PlayerProfile from './PlayerProfile'
import { confirmTransfer, contractOffer, dateLabel, listPlayer, marketSearch, negotiations, renewOffer, respondNegotiation, searchPlayers, shortlist, toggleShortlist, transferOffer, wageDemand, weekly } from '../services/careerWorldApi'
import { clubMoney, clubMoneyShort } from '../utils/clubMoney'
import PositionFilter from '../components/PositionFilter'
import './transfers.css'

const AREAS = [
  ['search', 'Busca'],
  ['shortlist', 'Pré-seleção'],
  ['deals', 'Negociações'],
  ['selling', 'Venda'],
]
const STATES = {
  seller_review: 'Proposta pelo seu atleta', club_pending: 'Clube analisando', club_counter: 'Clube pede mais', player_pending: 'Atleta analisando',
  player_counter: 'Negocie o contrato', player_accepted: 'Aceitou · confirme', agreed: 'Registrando', precontract: 'Registrando', completed: 'Concluída', rejected: 'Recusada',
  expired: 'Expirada', cancelled: 'Cancelada', failed_funds: 'Sem verba',
}
const CLOSED = new Set(['completed', 'rejected', 'expired', 'cancelled', 'failed_funds'])

// Filtros do mercado (estilo FM/CM): faixas prontas em fichas, sem listas de países.
const SKILL = [
  ['', 'Qualquer', null, null],
  ['80', '80+', 80, null],
  ['75', '75–79', 75, 79],
  ['70', '70–74', 70, 74],
  ['60', '60–69', 60, 69],
  ['0', 'Até 59', null, 59],
]
const AGES = [
  ['', 'Qualquer', null, null],
  ['u21', 'Até 21', null, 21],
  ['22', '22–25', 22, 25],
  ['26', '26–30', 26, 30],
  ['31', '31+', 31, null],
]
const VALUES = [null, 5000, 15000, 40000, 100000]
const STATUS = [
  ['', 'Todos'],
  ['affordable', 'Cabe no orçamento'],
  ['listed', 'À venda'],
  ['expiring', 'Fim de contrato'],
  ['free', 'Sem clube'],
]
const SORTS = [
  ['overall', 'Habilidade'],
  ['potential', 'Potencial'],
  ['value', 'Menor valor'],
  ['age', 'Mais jovem'],
]
const EMPTY = { p_query: '', p_position: '', skill: '', age: '', p_max_value: null, p_status: '', p_sort: 'overall', p_page: 0 }
const toArgs = (f) => {
  const sk = SKILL.find((x) => x[0] === f.skill) || SKILL[0]
  const ag = AGES.find((x) => x[0] === f.age) || AGES[0]
  return { p_query: f.p_query, p_position: f.p_position, p_min_overall: sk[2], p_max_overall: sk[3], p_min_age: ag[2], p_max_age: ag[3], p_max_value: f.p_max_value, p_status: f.p_status, p_sort: f.p_sort, p_page: f.p_page }
}
const activeCount = (f) => [f.skill, f.age, f.p_max_value, f.p_status, f.p_sort !== 'overall' ? 1 : null].filter(Boolean).length

function ChipRow({ label, options, value, onChange }) {
  return (
    <div className="tr-frow">
      <small>{label}</small>
      <div className="tr-fchips" role="radiogroup" aria-label={label}>
        {options.map(([v, text]) => (
          <button key={String(v)} type="button" role="radio" aria-checked={value === v} className={value === v ? 'is-on' : ''} onClick={() => onChange(v)}>
            {text}
          </button>
        ))}
      </div>
    </div>
  )
}
const clubName = (id) => getClubById(id)?.name || (id ? id : 'Sem clube')

function YearsPicker({ value, onChange, max = 5 }) {
  return (
    <div className="kp-years" role="radiogroup" aria-label="Duração do contrato">
      {Array.from({ length: max }, (_, i) => i + 1).map((y) => (
        <button key={y} type="button" role="radio" aria-checked={value === y} className={value === y ? 'is-on' : ''} onClick={() => onChange(y)}>
          {y} {y === 1 ? 'ano' : 'anos'}
        </button>
      ))}
    </div>
  )
}

// TRANSFERÊNCIAS (CM17): busca de atletas, pré-seleção, negociações e lista de venda.
// Oferta só de valor (teclado); contrato com salário semanal e anos; renovação igual.
export default function TransfersPanel({ hub, onRefresh, notify, onTeam, initialArea = 'search' }) {
  const w = hub.world
  const own = hub.coach.club_id
  const [area, setArea] = useState(AREAS.some(([id]) => id === initialArea) ? initialArea : 'search')
  const [rows, setRows] = useState([])
  const [deals, setDeals] = useState([])
  const [listed, setListed] = useState([])
  const [shortIds, setShortIds] = useState(new Set())
  const [filters, setFilters] = useState(EMPTY)
  const [showFilters, setShowFilters] = useState(false)
  const [busy, setBusy] = useState(false)
  const [profile, setProfile] = useState(null)
  const [pad, setPad] = useState(null) // { kind: 'fee'|'contract'|'renew'|'counter'|'sell', ... }
  const [padError, setPadError] = useState(null)
  const [years, setYears] = useState(3)
  const seq = useRef(0)

  const load = useCallback(async () => {
    const key = ++seq.current
    try {
      const [list, d, s] = await Promise.all([
        area === 'search' ? marketSearch(toArgs(filters)) : area === 'selling' ? searchPlayers({ p_query: '', p_country: '', p_position: '', p_region: '', p_club: 'mine', p_max_value: null, p_page: 0 }) : Promise.resolve(null),
        negotiations(),
        shortlist().catch(() => []),
      ])
      if (key !== seq.current) return
      if (area === 'search') setRows(list || [])
      if (area === 'selling') setListed((list || []).filter((p) => p.transfer_listed))
      if (area === 'shortlist') setRows(s || [])
      setDeals(d || [])
      setShortIds(new Set((s || []).map((p) => p.id)))
    } catch (e) {
      if (!isSessionError(e)) notify?.(e.message, 'alert')
    }
  }, [area, filters, notify])
  useEffect(() => {
    const t = setTimeout(load, 200)
    return () => clearTimeout(t)
  }, [load, w?.today])

  async function run(fn, okText) {
    if (busy) return false
    setBusy(true)
    setPadError(null)
    try {
      await fn()
      if (okText) notify?.(okText, 'ok')
      await onRefresh?.()
      await load()
      return true
    } catch (e) {
      if (isSessionError(e)) return false
      if (pad) setPadError(e.message)
      else notify?.(e.message, 'alert')
      return false
    } finally {
      setBusy(false)
    }
  }
  const closePad = () => {
    setPad(null)
    setPadError(null)
  }
  const openContract = async (target) => {
    try {
      const dm = await wageDemand(target.player_id || target.id)
      setYears(3)
      setPad({ ...target, demand: dm?.weekly_demand, maxYears: dm?.max_years || 5 })
    } catch (e) {
      if (!isSessionError(e)) notify?.(e.message, 'alert')
    }
  }
  const setF = (patch) => setFilters((f) => ({ ...f, ...patch, p_page: 0 }))
  const myDeal = (p) => deals.find((n) => n.player_id === p.id && !CLOSED.has(n.status))

  // Ações do perfil
  const offerFor = (p) => {
    const open = myDeal(p)
    if (open?.status === 'player_counter') return openContract({ kind: 'contract', negotiation: open.id, player_id: p.id, name: p.name })
    if (!p.club_id) {
      return run(async () => {
        const r = await transferOffer(p.id, 0)
        const id = r?.id || r?.negotiation_id
        await openContract({ kind: 'contract', negotiation: id, player_id: p.id, name: p.name })
      })
    }
    setPad({ kind: 'fee', player: p })
  }

  const table = (list, opts = {}) => (
    <table className="sn-table tr-table">
      <thead>
        <tr>
          <th className="left">Jogador</th>
          <th className="left tr-col-club">Clube</th>
          <th>Pos</th>
          <th>Idade</th>
          <th>Hab.</th>
          <th>{opts.wage ? 'Salário' : 'Valor'}</th>
        </tr>
      </thead>
      <tbody>
        {list.map((p) => (
          <tr key={p.id} className="is-link" onClick={() => setProfile(p)}>
            <td className="left">
              <span className="tr-name">
                {shortIds.has(p.id) && <Star size={12} fill="currentColor" />}
                {p.short_name || p.name}
              </span>
              <small className="tr-sub">{clubName(p.club_id)}</small>
            </td>
            <td className="left tr-col-club">
              <span className="tr-club">
                <ClubCrest clubId={p.club_id} size={18} />
                <span>{clubName(p.club_id)}</span>
              </span>
            </td>
            <td>{p.position}</td>
            <td>{p.age ?? '—'}</td>
            <td>
              <b className="tr-ovr">{p.overall}</b>
            </td>
            <td className="tr-val">{opts.wage ? `${clubMoneyShort(weekly(p.monthly_salary))}/sem` : clubMoneyShort(p.value)}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )

  const openDeals = deals.filter((n) => !CLOSED.has(n.status))
  // Só conta o que depende de você: contraproposta do clube, contrato a negociar, aceite a confirmar ou proposta pelo seu atleta.
  const pending = openDeals.filter((n) => (n.seller_club === own ? n.status === 'seller_review' : ['club_counter', 'player_counter', 'player_accepted'].includes(n.status))).length
  const doneDeals = deals.filter((n) => CLOSED.has(n.status))

  return (
    <div className="tr">
      <h2 className="cm-screen-title">Transferências</h2>
      {w?.club && (
        <div className="cw-budget">
          <span>
            <small>Orçam. de transferência</small>
            <b>{clubMoneyShort(w.club.available)}</b>
          </span>
          <span>
            <small>Orçam. salarial (semana)</small>
            <b>{clubMoneyShort(weekly(w.club.wage_budget ?? w.club.payroll))}</b>
          </span>
        </div>
      )}
      <p className={`tr-window ${w?.club?.window_open ? 'is-open' : ''}`}>
        {w?.club?.window_open ? 'Janela de transferências aberta' : `Janela fechada · próxima abertura ${dateLabel(w?.club?.next_window)}. Renovações continuam liberadas.`}
      </p>

      <div className="sn-seg tr-tabs" role="tablist">
        {AREAS.map(([id, label]) => (
          <button key={id} type="button" role="tab" aria-selected={area === id} className={area === id ? 'is-on' : ''} onClick={() => setArea(id)}>
            {label}
            {id === 'deals' && pending > 0 && <em>{pending}</em>}
          </button>
        ))}
      </div>

      {area === 'search' && (
        <>
          <div className="cw-searchrow">
            <label className="cw-field cw-search">
              <Search size={16} aria-hidden="true" />
              <input type="search" placeholder="Buscar jogador" aria-label="Buscar atleta" maxLength={60} value={filters.p_query} onChange={(e) => setFilters((f) => ({ ...f, p_query: e.target.value, p_page: 0 }))} />
            </label>
            <button type="button" className="gx-btn-ghost" aria-expanded={showFilters} onClick={() => setShowFilters((v) => !v)}>
              <SlidersHorizontal size={15} /> Filtros
              {activeCount(filters) > 0 && <em className="tr-fcount">{activeCount(filters)}</em>}
            </button>
          </div>
          <PositionFilter value={filters.p_position} onChange={(v) => setF({ p_position: v })} />
          {showFilters && (
            <div className="tr-filters">
              <ChipRow label="Habilidade" options={SKILL} value={filters.skill} onChange={(v) => setF({ skill: v })} />
              <ChipRow label="Idade" options={AGES} value={filters.age} onChange={(v) => setF({ age: v })} />
              <ChipRow label="Valor até" options={VALUES.map((v) => [v, v == null ? 'Qualquer' : clubMoneyShort(v)])} value={filters.p_max_value} onChange={(v) => setF({ p_max_value: v })} />
              <ChipRow label="Situação" options={STATUS} value={filters.p_status} onChange={(v) => setF({ p_status: v })} />
              <ChipRow label="Ordenar por" options={SORTS} value={filters.p_sort} onChange={(v) => setF({ p_sort: v })} />
              <button type="button" className="gx-btn-ghost tr-freset" onClick={() => setFilters((f) => ({ ...EMPTY, p_query: f.p_query, p_position: f.p_position }))}>
                <RotateCcw size={14} /> Limpar filtros
              </button>
            </div>
          )}
          {rows.length ? table(rows) : <p className="sn-hint">Nenhum atleta encontrado.</p>}
          <div className="tr-pages">
            <button type="button" className="gx-btn-ghost" disabled={filters.p_page === 0} onClick={() => setFilters((f) => ({ ...f, p_page: f.p_page - 1 }))}>
              Anterior
            </button>
            <span>Página {filters.p_page + 1}</span>
            <button type="button" className="gx-btn-ghost" disabled={rows.length < 30} onClick={() => setFilters((f) => ({ ...f, p_page: f.p_page + 1 }))}>
              Próximo
            </button>
          </div>
        </>
      )}

      {area === 'shortlist' && (rows.length ? table(rows) : <p className="sn-hint">Sua pré-seleção está vazia. Abra um atleta na Busca e toque em "Adicionar à pré-seleção".</p>)}

      {area === 'deals' && (
        <div className="tr-deals">
          {openDeals.length === 0 && <p className="sn-hint">Nenhuma negociação em andamento.</p>}
          {[...openDeals, ...doneDeals.slice(0, 10)].map((n) => {
            const selling = n.seller_club === own
            const other = selling ? n.buyer_club : n.seller_club
            return (
              <article key={n.id} className={`tr-deal s-${n.status}`}>
                <header>
                  <ClubCrest clubId={other} size={30} />
                  <span>
                    <b>{n.player_name}</b>
                    <small>
                      {clubName(n.seller_club)} → {clubName(n.buyer_club)}
                    </small>
                  </span>
                  <span className="tr-deal-fee">
                    <b>{clubMoneyShort(n.fee)}</b>
                    <small>{dateLabel(n.expires_on)}</small>
                  </span>
                </header>
                <em className="cw-deal-state">{STATES[n.status] || n.status}</em>
                {n.response && <p>{n.response}</p>}
                <div className="tr-deal-actions">
                  {n.status === 'club_counter' && !selling && (
                    <>
                      <button type="button" className="gx-btn" disabled={busy} onClick={() => run(() => respondNegotiation(n.id, 'accept', n.fee), 'Valor aceito. Agora negocie o contrato com o atleta.')}>
                        Pagar {clubMoneyShort(n.fee)}
                      </button>
                      <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setPad({ kind: 'counter', deal: n })}>
                        Melhorar oferta
                      </button>
                    </>
                  )}
                  {n.status === 'player_counter' && !selling && (
                    <button type="button" className="gx-btn" disabled={busy} onClick={() => openContract({ kind: n.initiator === 'renewal' ? 'renew' : 'contract', negotiation: n.id, player_id: n.player_id, name: n.player_name })}>
                      Negociar contrato
                    </button>
                  )}
                  {n.status === 'player_accepted' && !selling && (
                    <>
                      <button type="button" className="gx-btn" disabled={busy} onClick={() => run(() => confirmTransfer(n.id, true), n.initiator === 'renewal' ? 'Renovação confirmada.' : 'Negócio confirmado. O atleta será registrado.')}>
                        Confirmar
                      </button>
                      <button type="button" className="gx-btn-ghost is-danger" disabled={busy} onClick={() => run(() => confirmTransfer(n.id, false), 'Você desistiu do negócio.')}>
                        Desistir
                      </button>
                    </>
                  )}
                  {n.status === 'seller_review' && selling && (
                    <>
                      <button type="button" className="gx-btn" disabled={busy || !w?.club?.window_open} onClick={() => run(() => respondNegotiation(n.id, 'accept', n.fee), 'Venda aceita.')}>
                        Aceitar {clubMoneyShort(n.fee)}
                      </button>
                      <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setPad({ kind: 'sell', deal: n })}>
                        Pedir mais
                      </button>
                    </>
                  )}
                  {!CLOSED.has(n.status) && ['seller_review', 'club_counter', 'player_counter', 'club_pending', 'player_pending'].includes(n.status) && (
                    <button type="button" className="gx-btn-ghost is-danger" disabled={busy} onClick={() => run(() => respondNegotiation(n.id, 'reject', n.fee), 'Negociação encerrada.')}>
                      {selling ? 'Recusar' : 'Desistir'}
                    </button>
                  )}
                </div>
              </article>
            )
          })}
        </div>
      )}

      {area === 'selling' && (
        <>
          <p className="sn-hint">Atletas na lista de transferências recebem propostas de outros clubes. As propostas aparecem em Negociações.</p>
          {listed.length ? table(listed, { wage: true }) : <p className="sn-hint">Nenhum atleta seu na lista. Abra um atleta do Elenco e toque em "Lista de transferência".</p>}
        </>
      )}

      {profile && (
        <PlayerProfile
          player={profile}
          own={own}
          busy={busy}
          shortlisted={shortIds.has(profile.id)}
          onClose={() => setProfile(null)}
          onOffer={() => offerFor(profile)}
          onLoan={() => run(() => requestLoan(profile.id, 1, 'rotation'), 'Pedido de empréstimo enviado. O clube responde em breve.')}
          onShortlist={() => run(() => toggleShortlist(profile.id), shortIds.has(profile.id) ? 'Removido da pré-seleção.' : 'Adicionado à pré-seleção.')}
          onRenew={() => openContract({ kind: 'renew', player_id: profile.id, name: profile.name })}
          onList={() => run(() => listPlayer(profile.id, !profile.transfer_listed), profile.transfer_listed ? 'Atleta retirado da lista.' : 'Atleta na lista de transferências.').then((ok) => ok && setProfile((p) => ({ ...p, transfer_listed: !p.transfer_listed })))}
          onLoanList={() => run(() => listForLoan(profile.id, true), 'Atleta disponível para empréstimo.')}
          onSquad={onTeam && profile.club_id === own ? () => onTeam(profile.id) : null}
        />
      )}

      {pad?.kind === 'fee' && (
        <MoneyKeypad
          title="Fazer oferta de transferência"
          subtitle={pad.player.name}
          info={[
            ['Idade', pad.player.age ?? '—'],
            ['Grl', pad.player.overall],
            ['Posição', pad.player.position],
            ['Valor', clubMoneyShort(pad.player.value)],
            ['Fundos de transf.', clubMoneyShort(w?.club?.available)],
          ]}
          label="Oferta de transferência"
          initial={pad.player.value}
          busy={busy}
          error={padError}
          confirmText="Enviar oferta"
          onClose={closePad}
          onConfirm={(fee) => run(() => transferOffer(pad.player.id, fee), 'Oferta enviada. O clube responde em breve (e-mail).').then((ok) => ok && (closePad(), setProfile(null)))}
        />
      )}
      {(pad?.kind === 'counter' || pad?.kind === 'sell') && (
        <MoneyKeypad
          title={pad.kind === 'sell' ? 'Pedir mais pela venda' : 'Melhorar oferta'}
          subtitle={pad.deal.player_name}
          info={[
            ['Valor atual', clubMoneyShort(pad.deal.fee)],
            ['Avaliação', clubMoneyShort(pad.deal.valuation)],
          ]}
          label={pad.kind === 'sell' ? 'Valor pedido' : 'Nova oferta'}
          initial={pad.deal.fee}
          busy={busy}
          error={padError}
          onClose={closePad}
          onConfirm={(fee) => run(() => respondNegotiation(pad.deal.id, 'counter', fee), 'Proposta enviada.').then((ok) => ok && closePad())}
        />
      )}
      {(pad?.kind === 'contract' || pad?.kind === 'renew') && (
        <MoneyKeypad
          title={pad.kind === 'renew' ? 'Renovar contrato' : 'Negociar contrato'}
          subtitle={pad.name}
          info={[
            ['Pedida do atleta', pad.demand ? `${clubMoney(pad.demand)}/sem` : '—'],
            ['Orçam. salarial', clubMoneyShort(weekly(w?.club?.wage_budget ?? w?.club?.payroll))],
          ]}
          label="Salário por semana"
          initial={pad.demand || 0}
          busy={busy}
          error={padError}
          confirmText="Oferecer"
          extra={<YearsPicker value={years} onChange={setYears} max={pad.maxYears || 5} />}
          onClose={closePad}
          onConfirm={(wage) =>
            run(
              () => (pad.kind === 'renew' && !pad.negotiation ? renewOffer(pad.player_id, wage, years) : contractOffer(pad.negotiation, wage, years)),
              'Proposta enviada. O atleta responde em breve (e-mail).',
            ).then((ok) => ok && (closePad(), setProfile(null)))
          }
        />
      )}
    </div>
  )
}
