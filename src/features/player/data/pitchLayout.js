// Coordenadas em porcentagem (x: esquerda->direita, y: topo->base) dentro
// do campo. y=0 é o ataque (gol adversário), y=100 é o gol do seu time.
// Os ids batem com os de data/positions.js.
export const PITCH_LAYOUT = [
  { id: 'ATA', x: 50, y: 10 },
  { id: 'PE', x: 16, y: 24 },
  { id: 'PD', x: 84, y: 24 },
  { id: 'MEI', x: 68, y: 42 },
  { id: 'MC', x: 32, y: 42 },
  { id: 'VOL', x: 50, y: 54 },
  { id: 'LE', x: 18, y: 64 },
  { id: 'LD', x: 82, y: 64 },
  { id: 'ZAG', x: 50, y: 74 },
  { id: 'GOL', x: 50, y: 90 },
]
