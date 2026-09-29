import { useState } from 'react'
import AvatarBust from '../components/AvatarBust'
import {
  SKIN_TONES,
  HAIR_STYLES,
  HAIR_COLORS,
  EYE_COLORS,
  BEARD_OPTIONS,
} from '../data/characterOptions'

const CATEGORIES = [
  { id: 'skin', label: 'Pele' },
  { id: 'hair', label: 'Cabelo' },
  { id: 'hairColor', label: 'Cor do cabelo' },
  { id: 'eyeColor', label: 'Olhos' },
  { id: 'beard', label: 'Barba' },
]

export default function CharacterStep({ value, onChange, onNext }) {
  const [category, setCategory] = useState('skin')
  const appearance = value.appearance

  function updateAppearance(patch) {
    onChange({ appearance: { ...appearance, ...patch } })
  }

  return (
    <div className="step-screen">
      <div className="step-heading">
        <h1 className="heading">Crie seu personagem</h1>
        <p>Monte a aparência do seu jogador — dá para adicionar acessórios da loja depois.</p>
      </div>

      <div className="step-body character-step-body">
        <div className="character-preview">
          <AvatarBust {...appearance} />
        </div>

        <div className="category-tabs">
          {CATEGORIES.map((cat) => (
            <button
              type="button"
              key={cat.id}
              className={`category-tab ${category === cat.id ? 'is-active' : ''}`}
              onClick={() => setCategory(cat.id)}
            >
              {cat.label}
            </button>
          ))}
        </div>

        {category === 'skin' && (
          <div className="swatch-row">
            {SKIN_TONES.map((tone) => (
              <button
                type="button"
                key={tone.id}
                className={`swatch ${appearance.skin === tone.hex ? 'is-selected' : ''}`}
                style={{ background: tone.hex }}
                aria-label={tone.label}
                onClick={() => updateAppearance({ skin: tone.hex })}
              />
            ))}
          </div>
        )}

        {category === 'hair' && (
          <div className="option-row">
            {HAIR_STYLES.map((style) => (
              <button
                type="button"
                key={style.id}
                className={`option-chip ${appearance.hair === style.id ? 'is-selected' : ''}`}
                onClick={() => updateAppearance({ hair: style.id })}
              >
                {style.label}
              </button>
            ))}
          </div>
        )}

        {category === 'hairColor' && (
          <div className="swatch-row">
            {HAIR_COLORS.map((color) => (
              <button
                type="button"
                key={color.id}
                className={`swatch ${appearance.hairColor === color.hex ? 'is-selected' : ''}`}
                style={{ background: color.hex }}
                aria-label={color.label}
                onClick={() => updateAppearance({ hairColor: color.hex })}
                disabled={appearance.hair === 'bald'}
              />
            ))}
          </div>
        )}

        {category === 'eyeColor' && (
          <div className="swatch-row">
            {EYE_COLORS.map((color) => (
              <button
                type="button"
                key={color.id}
                className={`swatch ${appearance.eyeColor === color.hex ? 'is-selected' : ''}`}
                style={{ background: color.hex }}
                aria-label={color.label}
                onClick={() => updateAppearance({ eyeColor: color.hex })}
              />
            ))}
          </div>
        )}

        {category === 'beard' && (
          <div className="option-row">
            {BEARD_OPTIONS.map((opt) => (
              <button
                type="button"
                key={String(opt.id)}
                className={`option-chip ${appearance.beard === opt.id ? 'is-selected' : ''}`}
                onClick={() => updateAppearance({ beard: opt.id })}
              >
                {opt.label}
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="step-footer">
        <button type="button" className="btn-primary" onClick={onNext}>
          Próximo
        </button>
      </div>
    </div>
  )
}
