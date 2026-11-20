// Fichas dos estádios do modo pixel (só dados, sem three.js: a tela do clube usa esta lista para a escolha).
// Ficha:
//  name, capacity (texto), sky (cor do céu), apron (cor da pista/entorno do gramado)
//  grass: { pattern: 'stripes' | 'diagonal' | 'checker' | 'circles' | 'plain', colors: [clara, escura] }
//  tiers: anéis da arquibancada, de baixo para cima: [{ rows, seats: [cor, cor2?], stripe: 'rows' | 'blocks' | null }]
//  sides: lados com arquibancada ('back' = oposto à câmera, 'left', 'right')
//  roof: 'none' | 'back' | 'full' (cobertura) · roofColor
//  press: tribuna de imprensa no meio do lado de trás · lights: torres de refletores nos cantos
//  surround: 'city' | 'sea' | 'trees' | 'hills' | 'none' (o que aparece atrás do estádio)
//  crowd: ocupação da torcida (0 a 1)
// Os ids também ficam no banco (on_arenas, fase 45 do Online): estádio novo precisa entrar nos dois lugares.
export const STADIUMS = [
  {
    id: 'arena',
    name: 'Arena Central',
    capacity: '62 mil',
    sky: '#7fb7ea',
    apron: '#2b3445',
    grass: { pattern: 'stripes', colors: ['#3fbf6a', '#36a95c'] },
    tiers: [
      { rows: 12, seats: ['#c8202f', '#a31826'], stripe: 'rows' },
      { rows: 10, seats: ['#d63041', '#ffffff'], stripe: 'blocks' },
    ],
    sides: ['back', 'left', 'right'],
    roof: 'full',
    roofColor: '#e9edf3',
    press: true,
    lights: false,
    surround: 'city',
    crowd: 0.92,
  },
  {
    id: 'concreto',
    name: 'Estádio do Povo',
    capacity: '38 mil',
    sky: '#a9c7d8',
    apron: '#7a6a58',
    grass: { pattern: 'checker', colors: ['#46a85a', '#3d9650'] },
    tiers: [{ rows: 18, seats: ['#9aa1a8', '#8a9097'], stripe: 'rows' }],
    sides: ['back', 'left', 'right'],
    roof: 'back',
    roofColor: '#5b6470',
    press: true,
    lights: true,
    surround: 'city',
    crowd: 0.78,
  },
  {
    id: 'interior',
    name: 'Campo do Interior',
    capacity: '9 mil',
    sky: '#8fd0f2',
    apron: '#5f8f3c',
    grass: { pattern: 'plain', colors: ['#5cb83c', '#52a836'] },
    tiers: [{ rows: 7, seats: ['#1d5fb8', '#f2f2f2'], stripe: 'blocks' }],
    sides: ['back'],
    roof: 'none',
    roofColor: '#c9c9c9',
    press: false,
    lights: true,
    surround: 'trees',
    crowd: 0.55,
  },
  {
    id: 'praia',
    name: 'Estádio da Orla',
    capacity: '27 mil',
    sky: '#8ad3ff',
    apron: '#d9c48f',
    grass: { pattern: 'diagonal', colors: ['#38c79a', '#2fb08a'] },
    tiers: [{ rows: 11, seats: ['#f5a623', '#1b9ad6'], stripe: 'blocks' }],
    sides: ['back', 'left'],
    roof: 'none',
    roofColor: '#ffffff',
    press: false,
    lights: true,
    surround: 'sea',
    crowd: 0.7,
  },
  {
    id: 'neon',
    name: 'Arena Neon',
    capacity: '45 mil',
    sky: '#1a1035',
    apron: '#2a1748',
    grass: { pattern: 'diagonal', colors: ['#3ad6c4', '#2ab3b0'] },
    tiers: [
      { rows: 10, seats: ['#7c3aed', '#6d28d9'], stripe: 'rows' },
      { rows: 10, seats: ['#a855f7', '#e879f9'], stripe: 'blocks' },
    ],
    sides: ['back', 'left', 'right'],
    roof: 'full',
    roofColor: '#3b2a63',
    press: true,
    lights: false,
    surround: 'none',
    crowd: 0.95,
  },
  {
    id: 'circulos',
    name: 'Estádio Municipal',
    capacity: '21 mil',
    sky: '#9fd8ef',
    apron: '#a83a32',
    grass: { pattern: 'circles', colors: ['#3ea055', '#348c49'] },
    tiers: [{ rows: 13, seats: ['#e11d48', '#be123c'], stripe: 'rows' }],
    sides: ['back', 'left', 'right'],
    roof: 'back',
    roofColor: '#f1f5f9',
    press: true,
    lights: true,
    surround: 'hills',
    crowd: 0.66,
  },
]

export const stadiumById = (id) => STADIUMS.find((s) => s.id === id) || STADIUMS[0]

// estádio fixo de cada clube (pelo nome/id): o mesmo clube sempre joga no mesmo estádio
export function stadiumFor(key) {
  let h = 0
  for (const c of String(key || '')) h = (h * 31 + c.charCodeAt(0)) >>> 0
  return STADIUMS[h % STADIUMS.length]
}
