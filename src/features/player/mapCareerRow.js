export function mapRowToCareer(row) {
  return {
    id: row.id,
    userId: row.user_id,
    status: row.status,
    createdAt: row.created_at,
    player: {
      nickname: row.nickname,
      photoId: row.photo_id,
      country: row.country,
      age: row.age,
      position: row.position,
      jerseyNumber: row.jersey_number,
      level: row.level,
      xp: row.xp,
      skills: row.skills,
      accessories: row.accessories,
      clubId: row.club_id,
      // Carteira do jogo (colunas criadas pela migração de palpites).
      coins: row.coins ?? 0,
      energy: row.energy ?? 0,
    },
  }
}
