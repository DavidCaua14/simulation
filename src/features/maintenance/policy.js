export const MAINTENANCE_ADMIN_EMAIL = 'contatodavidcaua@gmail.com'
export const DEFAULT_MESSAGE = 'Estamos atualizando o jogo. Seu progresso e suas informações serão mantidos. Volte em breve!'

export function isMaintenanceAdmin(user) {
  return user?.email?.trim().toLowerCase() === MAINTENANCE_ADMIN_EMAIL
}

export function parseMaintenance(value) {
  if (typeof value?.enabled !== 'boolean') throw new Error('Configuração de manutenção inválida')
  return {
    enabled: value.enabled,
    message: typeof value.message === 'string' && value.message.trim() ? value.message : DEFAULT_MESSAGE,
  }
}
