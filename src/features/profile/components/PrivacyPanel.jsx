import { useState } from 'react'
import { setPrivacy } from '../services/profileApi'
import { EyeIcon, LockIcon } from './ProfileIcons'

const OPTIONS = [
  { key: 'show_career', label: 'Clube atual', hint: 'O clube que você treina agora.' },
  { key: 'show_stats', label: 'Estatísticas', hint: 'Partidas, vitórias, gols e reputação.' },
  { key: 'show_titles', label: 'Títulos', hint: 'Suas taças, com ano e clube.' },
  { key: 'show_collection', label: 'Coleção', hint: 'Quantas cartas você tem por raridade.' },
]

// O que OUTROS jogadores veem. Nome, foto, nível, insígnias conquistadas, carta em destaque e visual são sempre públicos.
export default function PrivacyPanel({ privacy = {}, onChanged }) {
  const [busy, setBusy] = useState(null)
  const [error, setError] = useState('')
  async function toggle(key) {
    setBusy(key)
    setError('')
    try {
      await setPrivacy({ [key]: !(privacy[key] ?? true) })
      onChanged?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setBusy(null)
    }
  }
  return (
    <section className="pf-panel" aria-labelledby="pf-privacy-title">
      <header className="pf-panel-head"><h2 id="pf-privacy-title">O que os outros veem</h2></header>
      <p className="pf-hint">Nome, foto, nível, insígnias conquistadas, carta em destaque e visual aparecem sempre no seu perfil público.</p>
      {OPTIONS.map((o) => {
        const on = privacy[o.key] ?? true
        return (
          <button key={o.key} type="button" role="switch" aria-checked={on} className={`pf-visibility ${on ? 'is-on' : ''}`} disabled={busy === o.key} onClick={() => toggle(o.key)}>
            {on ? <EyeIcon size={16} /> : <LockIcon size={16} />}
            <span><strong>{o.label}</strong>{o.hint}</span>
            <i className="pf-switch" aria-hidden="true" />
          </button>
        )
      })}
      {error && <p className="pf-error">{error}</p>}
    </section>
  )
}
