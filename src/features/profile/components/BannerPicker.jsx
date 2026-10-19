import { BANNERS, bannerStyle } from '../data/banners'
import { CheckIcon, ImageIcon } from './ProfileIcons'
import Sheet from './Sheet'

export default function BannerPicker({ selectedId, onSelect, onClose }) {
  return (
    <Sheet title="Estilo do banner" onClose={onClose}>
      <p className="pf-hint">Toque em uma cor para aplicar. Você vê o resultado no topo do perfil.</p>

      <div className="pf-swatches" role="radiogroup" aria-label="Cores de banner">
        {BANNERS.map((b) => {
          const on = b.id === selectedId
          return (
            <button
              key={b.id}
              type="button"
              role="radio"
              aria-checked={on}
              className={`pf-swatch ${on ? 'is-on' : ''}`}
              onClick={() => onSelect(b.id)}
            >
              <span className="pf-swatch-art" style={bannerStyle(b)}>
                {on && (
                  <span className="pf-swatch-check">
                    <CheckIcon size={14} />
                  </span>
                )}
              </span>
              <span className="pf-swatch-name">{b.name}</span>
            </button>
          )
        })}
      </div>

      <div className="pf-soon">
        <ImageIcon size={18} />
        <span>
          <strong>Banners com imagem</strong>
          Em breve: estádios, torcidas e muito mais.
        </span>
      </div>

      <button type="button" className="pf-btn primary block" onClick={onClose}>
        Concluir
      </button>
    </Sheet>
  )
}
