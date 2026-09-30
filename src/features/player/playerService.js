// Camada de dados do jogador/carreira — agora gravando de verdade no
// Supabase (tabela public.careers, ver supabase/schema.sql), não mais em
// localStorage. Todas as funções são assíncronas por causa disso.
import { supabase } from '../../lib/supabaseClient'
import { MIN_AGE, MAX_AGE } from './data/gameConstants'

function mapRowToCareer(row) {
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
    },
  }
}

// Regra de negócio: 1 carreira ativa por vez por usuário (também reforçada
// no banco por um índice único — ver schema.sql).
export async function hasActiveCareer(userId) {
  const { data, error } = await supabase
    .from('careers')
    .select('id')
    .eq('user_id', userId)
    .eq('status', 'active')
    .limit(1)

  if (error) {
    console.error('[hasActiveCareer]', error)
    return false
  }
  return data.length > 0
}

export async function isNicknameTaken(nickname) {
  if (!nickname) return false
  // RPC (função no banco) porque a checagem precisa "enxergar" carreiras de
  // QUALQUER usuário, não só as do usuário logado (RLS bloquearia um select
  // direto na tabela) — ver a função is_nickname_taken no schema.sql.
  const { data, error } = await supabase.rpc('is_nickname_taken', {
    check_nickname: nickname.trim(),
  })

  if (error) {
    console.error('[isNicknameTaken]', error)
    // Não trava o usuário por causa de um erro de rede pontual — a unicidade
    // ainda é garantida de verdade pelo índice único no insert.
    return false
  }
  return Boolean(data)
}

export async function createPlayer({ userId, nickname, photoId, country, age }) {
  if (!userId) {
    throw new Error('Você precisa estar logado para criar um personagem.')
  }

  const ageNumber = Number(age)
  if (!Number.isInteger(ageNumber) || ageNumber < MIN_AGE || ageNumber > MAX_AGE) {
    throw new Error(`A idade deve ser entre ${MIN_AGE} e ${MAX_AGE} anos.`)
  }

  const { data, error } = await supabase
    .from('careers')
    .insert({
      user_id: userId,
      nickname: nickname.trim(),
      photo_id: photoId,
      country,
      age: ageNumber,
    })
    .select()
    .single()

  if (error) {
    if (error.code === '23505') {
      // unique_violation: ou o nickname já existe, ou já há uma carreira
      // ativa para esse usuário (os dois índices únicos do schema.sql).
      if (error.message?.includes('nickname')) {
        throw new Error('Esse username já está em uso. Escolha outro.')
      }
      throw new Error('Você já tem uma carreira ativa.')
    }
    console.error('[createPlayer]', error)
    throw new Error('Não foi possível criar o personagem. Tente novamente.')
  }

  return mapRowToCareer(data)
}
