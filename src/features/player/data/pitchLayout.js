// Coordenadas em porcentagem (x: esquerda->direita, y: topo->base) dentro
// do campo. y=0 é o ataque (gol adversário), y=100 é o gol do seu time.
// 11 pontos ao todo (time completo): GOL, LD, ZAG, ZAG, LE, VOL, MC, MEI,
// PE, PD, ATA. Os dois pontos de ZAG apontam para o mesmo positionId — o
// jogador escolhe a função (Zagueiro), o campo só mostra os dois lados da
// linha de defesa.
export const PITCH_LAYOUT = [
  { spotId: 'ata', positionId: 'ATA', x: 50, y: 10 },
  { spotId: 'pe', positionId: 'PE', x: 16, y: 24 },
  { spotId: 'pd', positionId: 'PD', x: 84, y: 24 },
  { spotId: 'mei', positionId: 'MEI', x: 50, y: 34 },
  { spotId: 'mc', positionId: 'MC', x: 50, y: 46 },
  { spotId: 'vol', positionId: 'VOL', x: 50, y: 58 },
  { spotId: 'le', positionId: 'LE', x: 16, y: 70 },
  { spotId: 'ld', positionId: 'LD', x: 84, y: 70 },
  { spotId: 'zag-e', positionId: 'ZAG', x: 36, y: 80 },
  { spotId: 'zag-d', positionId: 'ZAG', x: 64, y: 80 },
  { spotId: 'gol', positionId: 'GOL', x: 50, y: 92 },
]
