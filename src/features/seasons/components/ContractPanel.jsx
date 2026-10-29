import { useState } from 'react'
import { FileSignature, Tag, UserMinus } from 'lucide-react'
import MoodBadge from './MoodBadge'
import { dateLabel, money, requestId, worldRpc } from '../services/careerWorldApi'
import { isSessionError } from '../../../lib/sessionRecovery'

const ROLES = { key: 'Peça-chave', starter: 'Titular', rotation: 'Rotação', prospect: 'Promessa' }
const monthsLeft = (until, today) => (until && today ? Math.max(0, Math.ceil((Date.parse(until) - Date.parse(today)) / (30 * 86400000))) : null)

// Satisfação e contrato do atleta do SEU elenco: renovar (até 5 anos), colocar na lista de transferências ou rescindir.
export default function ContractPanel({ player: p, today, maxYears = 5, notify, onChanged }) {
  const [busy, setBusy] = useState(false)
  const [renewal, setRenewal] = useState(null) // { id, salary, years, signing, role }
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
  const openRenewal = () =>
    run(async () => {
      const r = await worldRpc('career_contract_renew', { p_player: p.id, p_request: requestId() })
      setRenewal({ id: r.id, salary: Math.ceil((p.monthly_salary || 100) * 1.08), years: 2, signing: 0, role: p.promised_role || 'rotation' })
    })
  const sendRenewal = (e) => {
    e.preventDefault()
    run(async () => {
      await worldRpc('career_player_offer', { p_id: renewal.id, p_salary: +renewal.salary, p_years: +renewal.years, p_signing: +renewal.signing, p_role: renewal.role, p_appearance: 0, p_goal: 0, p_request: requestId() })
      setRenewal(null)
      notify?.('Proposta de renovação enviada. O atleta responde nos próximos dias (Mundo → Negociações).', 'ok')
      onChanged?.()
    })
  }
  // Papel combinado com o atleta: quem promete "Titular" e não escala deixa o jogador insatisfeito.
  const changeRole = (role) =>
    run(async () => {
      await worldRpc('career_player_role', { p_player: p.id, p_role: role })
      notify?.(`Papel combinado: ${ROLES[role]}. A satisfação passa a considerar o novo papel.`, 'ok')
      onChanged?.()
    })
  const toggleList = () =>
    run(async () => {
      await worldRpc('career_player_list', { p_player: p.id, p_listed: !p.transfer_listed })
      notify?.(p.transfer_listed ? 'Atleta retirado da lista de transferências.' : 'Atleta na lista de transferências: clubes interessados enviam propostas.', 'ok')
      onChanged?.()
    })
  const release = () =>
    run(async () => {
      const r = await worldRpc('career_player_release', { p_player: p.id, p_request: requestId() })
      notify?.(`Contrato rescindido por ${money(r.cost)} moedas. O atleta está livre no mercado.`, 'ok')
      onChanged?.({ closed: true })
    })

  return (
    <section className="ps-deal" aria-label="Satisfação e contrato">
      <h4>Satisfação e contrato</h4>
      <MoodBadge morale={p.morale} size={16} withLabel />
      {p.transfer_requested && <p><b>Pediu para ser negociado.</b> Insatisfeito, ele rende menos em campo até a situação mudar: dê mais minutos, combine outro papel ou negocie a saída.</p>}
      {p.precontract && <p><b>Já assinou pré-contrato com outro clube</b> e sai de graça quando o vínculo terminar.</p>}
      <dl>
        <div><dt>Contrato até</dt><dd>{dateLabel(p.contract_expires)}{left != null && left <= 6 ? ` · ${left} mês(es)` : ''}</dd></div>
        <div><dt>Salário mensal</dt><dd>{money(p.monthly_salary)}</dd></div>
        <div>
          <dt>Papel prometido</dt>
          <dd>
            <select className="ps-role" aria-label="Papel prometido" value={p.promised_role || 'rotation'} disabled={busy || renewal} onChange={(e) => changeRole(e.target.value)}>
              {Object.entries(ROLES).map(([id, label]) => <option key={id} value={id}>{label}</option>)}
            </select>
          </dd>
        </div>
        <div><dt>Situação</dt><dd>{p.transfer_listed ? 'Na lista de transferências' : 'No elenco'}</dd></div>
      </dl>
      {left != null && left <= 6 && !p.precontract && <p>Nos seis meses finais outros clubes podem oferecer pré-contrato. Sem renovação, ele sai de graça.</p>}

      {renewal ? (
        <form className="ps-renew" onSubmit={sendRenewal}>
          <label className="cw-field">Salário mensal<input type="number" inputMode="numeric" min={1} max={10000000} required value={renewal.salary} onChange={(e) => setRenewal((r) => ({ ...r, salary: e.target.value }))} /></label>
          <label className="cw-field">Anos de contrato (até {maxYears})<input type="number" inputMode="numeric" min={1} max={maxYears} required value={renewal.years} onChange={(e) => setRenewal((r) => ({ ...r, years: e.target.value }))} /></label>
          <label className="cw-field">Luvas<input type="number" inputMode="numeric" min={0} max={10000000} required value={renewal.signing} onChange={(e) => setRenewal((r) => ({ ...r, signing: e.target.value }))} /></label>
          <label className="cw-field">Papel no elenco<select value={renewal.role} onChange={(e) => setRenewal((r) => ({ ...r, role: e.target.value }))}>{Object.entries(ROLES).map(([id, label]) => <option key={id} value={id}>{label}</option>)}</select></label>
          <div className="ps-deal-actions">
            <button type="button" className="gx-btn-ghost" disabled={busy} onClick={() => setRenewal(null)}>Cancelar</button>
            <button type="submit" className="gx-btn" disabled={busy}>Enviar</button>
          </div>
        </form>
      ) : confirmRelease ? (
        <div className="ps-deal-actions">
          <p>Rescindir custa cerca de <b>{money(releaseCost)}</b> moedas (até seis salários) e o atleta fica livre no mercado.</p>
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
    </section>
  )
}
