import { useEffect, useRef, useState } from 'react'
import { HandCoins } from 'lucide-react'
import { dateLabel, money, requestId, worldRpc } from '../services/careerWorldApi'
import { personalCoins } from '../utils/clubMoney'
import { isSessionError } from '../../../lib/sessionRecovery'
import './clubInvestment.css'

// A separate confirmation is always required; investing never submits a player offer.
export function InvestmentConfirmation({ amount, onClose, onInvested }) {
  const [quote, setQuote] = useState(null)
  const [error, setError] = useState('')
  const [busy, setBusy] = useState(false)
  const [revision, setRevision] = useState(0)
  const request = useRef(null)
  const executing = useRef(false)
  useEffect(() => {
    let active = true
    worldRpc('career_club_investment_preview', { p_amount: Number(amount) }).then(q => {
      if (active) { request.current = requestId(); setQuote(q); setError('') }
    }).catch(e => { if (active && !isSessionError(e)) setError(e.message) })
    return () => { active = false }
  }, [amount, revision])
  async function confirm() {
    if (!quote?.can_invest || executing.current) return
    executing.current = true; setBusy(true); setError('')
    try {
      const result = await worldRpc('career_club_investment_confirm', {
        p_amount: quote.amount, p_club: quote.club_id, p_expected_coins: quote.personal_before,
        p_expected_cash: quote.cash_before, p_expected_bonus: quote.board_bonus, p_request: request.current,
      })
      await onInvested?.(result)
      onClose()
    } catch (e) { if (!isSessionError(e)) setError(e.message) }
    finally { executing.current = false; setBusy(false) }
  }
  return <div className="ci-confirm" role="group" aria-label="Confirmar aporte">
    <h4>Revise seu aporte{quote?.club_name ? ` ao ${quote.club_name}` : ''}</h4>
    {!quote && !error && <p role="status">Calculando os valores atuais…</p>}
    {quote && <>
      <dl className="ci-values">
        <div><dt>Sua carteira</dt><dd>{personalCoins(quote.personal_before)} → {personalCoins(quote.personal_after)} moedas</dd></div>
        <div><dt>Seu aporte</dt><dd>{money(quote.amount)}</dd></div>
        <div><dt>Contribuição da diretoria</dt><dd>+ {money(quote.board_bonus)}</dd></div>
        <div><dt>Caixa do clube</dt><dd>{money(quote.cash_before)} → {money(quote.cash_after)}</dd></div>
      </dl>
      <p>O dinheiro permanece no clube se você sair. O aporte não garante o aceite do atleta e não envia a proposta.</p>
      {!quote.can_invest && <p className="ci-warning">Você não tem moedas suficientes para este aporte.</p>}
    </>}
    {error && <p className="ci-warning" role="alert">{error}</p>}
    <div className="ci-actions">
      <button type="button" className="gx-btn-ghost" disabled={busy} onClick={onClose}>Voltar à decisão</button>
      {error && <button type="button" className="sn-link" disabled={busy} onClick={() => { setQuote(null); setRevision(v => v + 1) }}>Atualizar valores</button>}
      <button type="button" className="gx-btn" disabled={busy || !quote?.can_invest} onClick={confirm}>
        {busy ? 'Transferindo…' : `Confirmar aporte de ${personalCoins(amount)} moedas`}
      </button>
    </div>
  </div>
}

export function FundingAdvice({ playerId, negotiationId = null, terms, onInvested, disabled = false }) {
  const [state, setState] = useState({ quote: null, error: '' })
  const [confirmation, setConfirmation] = useState(null)
  const [revision, setRevision] = useState(0)
  const serialized = JSON.stringify(terms)
  const identity = `${playerId}:${negotiationId}:${serialized}`
  useEffect(() => {
    let active = true
    const timer = setTimeout(() => {
      worldRpc('career_funding_quote', { p_player: playerId, p_negotiation: negotiationId, p_terms: JSON.parse(serialized) })
        .then(quote => { if (active) setState({ quote, error: '', identity }) })
        .catch(e => { if (active && !isSessionError(e)) setState({ quote: null, error: e.message, identity }) })
    }, 350)
    return () => { active = false; clearTimeout(timer) }
  }, [playerId, negotiationId, serialized, identity, revision])
  const q = state.identity === identity ? state.quote : null
  const error = state.identity === identity ? state.error : ''
  // Hide an old quote immediately when the edited conditions no longer match it.
  const [confirmedFor, setConfirmedFor] = useState(null)
  const openConfirmation = confirmation != null && confirmedFor === identity
  if (!q && !error) return <p className="sn-hint" role="status">Calculando o orçamento desta negociação…</p>
  return <div className="ci-advice" aria-label="Planejamento da negociação">
    {error ? <p className="sn-hint">Não foi possível calcular o planejamento: {error}</p>
      : q.blocked_reason ? <p className="ci-warning">{q.blocked_reason} Um aporte não remove essa exigência.</p>
      : <>
        <p><b>{q.gap > 0 ? `Faltam ${money(q.gap)} para sustentar estas condições.` : 'Estas condições cabem no orçamento atual.'}</b></p>
        <details><summary>Como calculamos</summary><dl className="ci-values">
          <div><dt>Taxa, luvas e bônus de transferência</dt><dd>{money(q.fee + q.signing_bonus + q.performance_bonus)}</dd></div>
          <div><dt>Reserva do acréscimo da folha</dt><dd>{money(q.salary_reserve)}</dd></div>
          <div><dt>Reserva da folha atual</dt><dd>{money(q.current_payroll_reserve)}</dd></div>
          <div><dt>Outros compromissos e dívidas</dt><dd>{money(q.reserved_other + q.debt)}</dd></div>
          <div><dt>Caixa atual</dt><dd>{money(q.club_cash)}</dd></div>
        </dl></details>
        <p className="sn-hint">Estimativa para as condições exibidas. Salário, luvas e projeto esportivo continuam sujeitos à avaliação do atleta.</p>
        {q.gap > 0 && <>
          <p>Aporte necessário: <b>{personalCoins(q.coins_needed)} moedas</b>{q.board_bonus > 0 && <> com mais {money(q.board_bonus)} da diretoria</>}.</p>
          {q.can_invest ? <button type="button" className="gx-btn-ghost" disabled={disabled} onClick={() => { setConfirmedFor(identity); setConfirmation(q.coins_needed) }}><HandCoins size={16} /> Planejar aporte</button>
            : <p className="sn-hint">{q.coins_needed > 1000000 ? 'Este planejamento exige mais de um aporte.' : `Você tem ${personalCoins(q.personal_coins)} moedas.`} Você pode rever a proposta ou reunir mais moedas pelo salário do treinador e pelas recompensas disponíveis.</p>}
        </>}
      </>}
    {openConfirmation && <InvestmentConfirmation key={`${identity}:${confirmation}`} amount={confirmation} onClose={() => setConfirmation(null)} onInvested={async r => { setState({quote:null,error:''}); setRevision(v => v + 1); await onInvested?.(r) }} />}
  </div>
}

export default function ClubInvestment({ coins, board, onInvested, disabled = false }) {
  const [amount, setAmount] = useState(100)
  const [confirmation, setConfirmation] = useState(null)
  const valid = Number.isInteger(Number(amount)) && amount >= 1 && amount <= Math.min(coins, 1000000)
  return <section className="ci-contribute" aria-label="Aporte ao clube">
    <h4><HandCoins size={18} /> Apoie o projeto do clube</h4>
    <p>Cada moeda financia {money(1)} no caixa. Seu aporte pode ajudar a manter o elenco e buscar reforços.</p>
    {board && <p className="ci-board">A diretoria complementa <b>20%</b> dos aportes, até {money(board.bonus_cap)} nesta temporada. Ainda disponível: <b>{money(board.bonus_remaining)}</b>. A contribuição acompanha os aportes até esse limite, inclusive se você sair e voltar ao clube.</p>}
    <label className="cw-field">Investir da sua carteira ({personalCoins(coins)} moedas)
      <input type="number" inputMode="numeric" min={1} max={Math.min(coins,1000000)} step={1} required value={amount} onChange={e => { setAmount(e.target.value); setConfirmation(null) }} />
    </label>
    <button type="button" className="gx-btn" disabled={disabled || !valid} onClick={() => setConfirmation(Number(amount))}>Revisar aporte</button>
    <p className="sn-hint">Você escolhe quando contribuir. O dinheiro permanece no clube se você sair.</p>
    {confirmation != null && <InvestmentConfirmation amount={confirmation} onClose={() => setConfirmation(null)} onInvested={onInvested} />}
  </section>
}

export function RenewalNotice({ expiresOn, today, demand, projectReason }) {
  const days = Math.ceil((Date.parse(`${expiresOn}T12:00:00Z`) - Date.parse(`${today}T12:00:00Z`)) / 86400000)
  if (!Number.isFinite(days) || days < 0 || days > 180) return null
  return <p className="ci-warning">Contrato até {dateLabel(expiresOn)}.{demand > 0 && ` Pretensão mensal para renovar: ${money(demand)}.`} {projectReason || 'Sem renovação aprovada, o atleta sai ao fim do vínculo.'}</p>
}
