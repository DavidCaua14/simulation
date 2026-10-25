import { useEffect } from 'react'
import { X } from 'lucide-react'

// Folha que sobe de baixo (padrão do modo): título, botão fechar e corpo com rolagem.
export default function Sheet({ kicker, title, onClose, children, footer, tall = false, className = '' }) {
  useEffect(() => {
    const onKey = (e) => e.key === 'Escape' && onClose?.()
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="sn-sheet-wrap" onClick={onClose}>
      <div className={`sn-sheet ${tall ? 'is-tall' : ''} ${className}`} role="dialog" aria-modal="true" aria-label={title} onClick={(e) => e.stopPropagation()}>
        <header>
          <div>
            {kicker && <small>{kicker}</small>}
            <strong className="heading">{title}</strong>
          </div>
          <button type="button" className="sn-x" onClick={onClose} aria-label="Fechar">
            <X size={18} />
          </button>
        </header>
        <div className="sn-sheet-body">{children}</div>
        {footer && <footer className="sn-sheet-foot">{footer}</footer>}
      </div>
    </div>
  )
}
