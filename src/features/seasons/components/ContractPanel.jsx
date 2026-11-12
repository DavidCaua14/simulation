import MoneyKeypad from './MoneyKeypad'
import { useState } from 'react'
import { FileSignature, Tag, UserMinus } from 'lucide-react'
import { dateLabel, money, renewOffer, requestId, wageDemand, weekly, worldRpc } from '../services/careerWorldApi'
import { clubMoney, clubMoneyShort } from '../utils/clubMoney'
import { isSessionError } from '../../../lib/sessionRecovery'

const monthsLeft = (until, today) => (until && today ? Math.max(0, Math.ceil((Date.parse(until) - Date.parse(today)) / (30 * 86400000))) : null)

// Contrato do atleta do SEU elenco: renovar (até 5 anos), colocar na lista de transferências ou rescindir.
export default function ContractPanel({ player: p, today, maxYears = 5, notify, onChanged }) {
  const [busy, setBusy] = useState(false)
  const [renewal, setRenewal] = useState(null) // { demand, maxYears }
  const [years, setYears] = useState(2)
  const [padError, setPadError] = useState(null)
  const [confirmRelease, setConfirmRelease] = useState(false)
  if (p.contract_expires == null && p.morale == null) return null
  const left = monthsLeft(p.contract_expires, today)
  const releaseCost = p.monthly_salary ? p.monthly_salary * Math.max(1, Math.min(6, left ?? 6)) : null

  async function run(fn) {
    if (busy) return
    setBusy(true)
    try {
      await fn()
    } catch (e) {
      if (!isSessionError(e)) notify?.(e.message, 'alert')
    } finally {
      setBusy(false)
    }
  }
  // Renovação (CM17): salário semanal + anos. Abaixo da pedida o atleta recusa e diz quanto quer.
  const openRenewal = () =>
    run(async () => {
      const d = await wageDemand(p.id)
      setPadError(null)
      setYears(2)
      setRenewal({ demand: d?.weekly_demand, maxYears: d?.max_years || maxYears })
    })
  async function sendRenewal(wage) {
    if (busy) return
    setBusy(true)
    setPadError(null)
    try {
      await renewOffer(p.id, wage, years)
      setRenewal(null)
      notify?.('Proposta de renovação enviada. O atleta responde em breve (e-mail).', 'ok')
      onChanged?.()
    } catch (e) {
      if (!isSessionError(e)) setPadError(e.message)
    } finally {
      setBusy(false)
    }
  }
  const toggleList = () =>
    run(async () => {
      await worldRpc('career_player_list', { p_player: p.id, p_listed: !p.transfer_listed })
      notify?.(p.transfer_listed ? 'Atleta retirado da lista de transferências.' : 'Atleta na lista de transferências: clubes interessados enviam propostas.', 'ok')
      onChanged?.()
    })
  const release = () =>
    run(async () => {
      const r = await worldRpc('career_player_release', { p_player: p.id, p_request: requestId() })
      notify?.(`Contrato rescindido por ${money(r.cost)}. O atleta está livre no mercado.`, 'ok')
      onChanged?.({ closed: true })
    })

  return (
    <section className="ps-deal" aria-label="Contrato">
      <h4>Contrato</h4>
      <p className="sn-hint">Você pode negociar a renovação mesmo com a janela fechada. O atleta avalia salário e projeto esportivo e pode recusar. Sem renovação, o vínculo termina na data prevista.</p>
      {left != null && left > 6 && left <= 12 && !p.precontract && <p className="ps-ending">Contrato no último ano: renove antes dos seis meses finais, quando outros clubes podem levá-lo de graça.</p>}
      {p.precontract && <p><b>Já assinou pré-contrato com outro clube</b> e sai de graça quando o vínculo terminar.</p>}
      <dl>
        <div><dt>Contrato até</dt><dd>{dateLabel(p.contract_expires)}{left != null && left <= 6 ? ` · ${left} mês(es)` : ''}</dd></div>
        <div><dt>Salário semanal</dt><dd>{clubMoney(weekly(p.monthly_salary))}</dd></div>
        <div><dt>Situação</dt><dd>{p.transfer_listed ? 'Na lista de transferências' : 'No elenco'}</dd></div>
      </dl>
      {left != null && left <= 6 && !p.precontract && <p className="ps-ending">Nos seis meses finais outros clubes podem oferecer pré-contrato. Sem renovação, ele sai de graça.</p>}

      {confirmRelease ? (
        <div className="ps-deal-actions">
          <p>Rescindir custa cerca de <b>{money(releaseCost)}</b> (até seis salários) e o atleta fica livre no mercado.</p>
          <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setConfirmRelease(false)}>Voltar</button>
          <button type="button" className="gx-btn is-danger" disabled={busy} onClick={release}>Confirmar</button>
        </div>
      ) : (
        <div className="ps-deal-actions">
          <button type="button" className="gx-btn" disabled={busy || p.precontract} onClick={openRenewal}><FileSignature size={15} /> Renovar</button>
          <button type="button" className="gx-btn-ghost" disabled={busy} onClick={toggleList}><Tag size={15} /> {p.transfer_listed ? 'Tirar da venda' : 'Vender'}</button>
          <button type="button" className="gx-btn-ghost" disabled={busy || p.precontract} onClick={() => setConfirmRelease(true)}><UserMinus size={15} /> Rescindir</button>
        </div>
      )}
      {renewal && (
        <MoneyKeypad
          title="Renovar contrato"
          subtitle={p.name || p.short_name}
          info={[
            ['Salário atual', `${clubMoneyShort(weekly(p.monthly_salary))}/sem`],
            ['Pedida do atleta', renewal.demand ? `${clubMoneyShort(renewal.demand)}/sem` : '—'],
          ]}
          label="Salário por semana"
          initial={renewal.demand || weekly(p.monthly_salary)}
          busy={busy}
          error={padError}
          confirmText="Oferecer"
          extra={
            <div className="kp-years" role="radiogroup" aria-label="Duração">
              {Array.from({ length: renewal.maxYears }, (_, i) => i + 1).map((y) => (
                <button key={y} type="button" className={years === y ? 'is-on' : ''} onClick={() => setYears(y)}>
                  {y} {y === 1 ? 'ano' : 'anos'}
                </button>
              ))}
            </div>
          }
          onClose={() => setRenewal(null)}
          onConfirm={sendRenewal}
        />
      )}
    </section>
  )
}
