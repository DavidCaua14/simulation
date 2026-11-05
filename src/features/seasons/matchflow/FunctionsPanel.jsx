import { useEffect, useMemo, useState } from 'react'
import { fetchClubDev, setSetPieces } from '../../clubdev/clubDevApi'
import { fetchSquad } from '../services/managerApi'
import { isSessionError } from '../../../lib/sessionRecovery'

const ROLES = [
  ['captain', 'Capitão'],
  ['penalty', 'Pênaltis'],
  ['freeKick', 'Faltas'],
  ['corner', 'Escanteios'],
]

// FUNÇÕES (como no CM17): capitão e batedores de pênalti, falta e escanteio.
// Só os titulares aparecem; quem bate é usado pelo motor nas bolas paradas.
export default function FunctionsPanel({ notify, onDone }) {
  const [squad, setSquad] = useState(null)
  const [sp, setSp] = useState({})
  const [saving, setSaving] = useState(false)
  const [error, setError] = useState('')

  useEffect(() => {
    let alive = true
    Promise.all([fetchSquad(), fetchClubDev().catch(() => null)])
      .then(([s, dev]) => {
        if (!alive) return
        setSquad(s)
        const cur = dev?.set_pieces || {}
        setSp({ captain: cur.captain || null, penalty: cur.penalty || null, freeKick: cur.free_kick || null, corner: cur.corner || null })
      })
      .catch((e) => alive && !isSessionError(e) && setError(e.message))
    return () => {
      alive = false
    }
  }, [])

  const starters = useMemo(() => {
    if (!squad) return []
    const ids = new Set(Object.values(squad.lineup?.slots || {}))
    return squad.players.filter((p) => ids.has(p.id)).sort((a, b) => b.overall - a.overall)
  }, [squad])

  async function save() {
    setSaving(true)
    try {
      await setSetPieces(sp)
      onDone()
    } catch (e) {
      notify?.(e.message, 'alert')
    } finally {
      setSaving(false)
    }
  }

  if (error) return <p className="sn-muted sn-center">{error}</p>
  if (!squad) return <div className="st-sk hero" />
  return (
    <div className="fn">
      <h2 className="cm-screen-title">Funções</h2>
      {ROLES.map(([key, label]) => (
        <label key={key} className="fn-row">
          <span>{label}</span>
          <select value={sp[key] || ''} onChange={(e) => setSp((s) => ({ ...s, [key]: e.target.value || null }))}>
            <option value="">Automático</option>
            {starters.map((p) => (
              <option key={p.id} value={p.id}>
                {p.short_name || p.name} · {p.position} · {p.overall}
              </option>
            ))}
          </select>
        </label>
      ))}
      <p className="sn-hint">Em "Automático" o auxiliar escolhe o melhor batedor em campo.</p>
      <div className="mf-actions">
        <button type="button" className="gx-btn-ghost" onClick={onDone} disabled={saving}>
          Voltar
        </button>
        <button type="button" className="gx-btn" onClick={save} disabled={saving}>
          {saving ? 'Salvando…' : 'Confirmar'}
        </button>
      </div>
    </div>
  )
}
