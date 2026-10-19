import { useEffect } from 'react'
import { CloseIcon } from './ProfileIcons'

// Painel que sobe da base da tela (padrão de jogos mobile).
export default function Sheet({ title, onClose, children }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose()
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  return (
    <div className="pf-sheet-layer">
      <button type="button" className="pf-sheet-backdrop" aria-label="Fechar" onClick={onClose} />
      <div className="pf-sheet" role="dialog" aria-modal="true" aria-label={title}>
        <span className="pf-sheet-grip" aria-hidden="true" />
        <header className="pf-sheet-head">
          <h3>{title}</h3>
          <button type="button" className="pf-icon-btn" onClick={onClose} aria-label="Fechar">
            <CloseIcon size={16} />
          </button>
        </header>
        <div className="pf-sheet-body">{children}</div>
      </div>
    </div>
  )
}
