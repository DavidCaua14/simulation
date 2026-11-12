// Mini-games de treino: nome, grupo de atributos que evolui e índice do grupo em on_players.g / xp.
export const GAMES = {
  penalty: { title: 'Pênaltis', group: 'Ataque', gi: 2, solo: true },
  aim: { title: 'Finalização', group: 'Ataque', gi: 2 },
  passing: { title: 'Troca de passes', group: 'Passe', gi: 1 },
  tackle: { title: 'Desarme', group: 'Defesa', gi: 0 },
  reaction: { title: 'Reflexo', group: 'Defesa', gi: 0 },
  dribble: { title: 'Drible', group: 'Físico', gi: 3 },
  timing: { title: 'Explosão', group: 'Físico', gi: 3 },
}
