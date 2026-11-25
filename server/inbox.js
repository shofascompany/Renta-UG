// Delete one message from a landlord's (or the main admin's) own inbox. Shared by Express and Netlify Functions.
import { HttpError } from './admin.js'

const UUID = /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i

export async function deleteInboxItem(db, user, body) {
  const id = String(body?.id ?? '')
  if (!UUID.test(id)) throw new HttpError(400, 'Notification not found.')
  // Only ever their own: the owner is part of the delete itself
  const { data, error } = await db.from('staff_notifications').delete().eq('id', id).eq('user_id', user.id).select('id')
  if (error) throw new HttpError(500, error.message)
  if (!data?.length) throw new HttpError(404, 'Notification not found.')
  return { ok: true }
}
