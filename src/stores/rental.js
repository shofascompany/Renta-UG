import { defineStore } from 'pinia'
import { supabase, must } from '@/lib/supabase'
import { api } from '@/lib/api'
import { useAuthStore } from './auth'

// Sender line for a landlord's message, shown under the "Renta UG" title
export function landlordSenderLine() {
  const auth = useAuthStore()
  const name = auth.profile?.full_name?.trim()
  return name ? `From ${name} (Landlord)` : 'From your landlord'
}

// All app data, loaded from Supabase. Row level security decides what each user sees:
// the owner gets everything, a tenant only gets their own records.

// Names always start each word with a capital: "john mukasa" → "John Mukasa"
export const titleCase = (s) => (s ?? '').trim().replace(/(^|[\s\-'(])([a-zà-ÿ])/g, (_, a, b) => a + b.toUpperCase())

const today = () => new Date().toLocaleDateString('en-CA') // YYYY-MM-DD, local time
const NEEDS_DB_UPDATE = 'This needs a database update: run database/update_existing.sql in Supabase.'

const map = {
  properties: (r) => ({
    id: r.id,
    landlordId: r.landlord_id,
    name: r.name,
    location: r.location,
    type: r.type,
    bedrooms: r.bedrooms,
    bathrooms: r.bathrooms,
    rent: Number(r.rent),
    rentalId: r.rental_id ?? null, // room in a rental business (null = a standalone house)
    createdAt: r.created_at,
  }),
  // A rental business with several rooms (each room is a property)
  rentals: (r) => ({
    id: r.id,
    landlordId: r.landlord_id,
    name: r.name,
    location: r.location,
    type: r.type,
    createdAt: r.created_at,
  }),
  tenants: (r) => ({
    id: r.id,
    landlordId: r.landlord_id,
    userId: r.user_id,
    propertyId: r.property_id,
    name: r.full_name,
    email: r.email,
    phone: r.phone,
    leaseStart: r.lease_start,
    leaseEnd: r.lease_end,
    connectCode: r.connect_code ?? null,
    connectCodeExpiresAt: r.connect_code_expires_at ?? null,
    lastPropertyId: r.last_property_id ?? null,
    endedAt: r.ended_at ?? null,
    personId: r.person_id ?? r.id, // same person across stays
    managedByLandlord: r.managed_by_landlord === true, // no smartphone: the landlord manages them
    createdAt: r.created_at,
  }),
  // Cash handed to the landlord, waiting for / after confirmation
  cash_payments: (r) => ({
    id: r.id,
    tenantId: r.tenant_id,
    landlordId: r.landlord_id,
    amount: Number(r.amount),
    paidOn: r.paid_on,
    note: r.note,
    submittedBy: r.submitted_by,
    submittedRole: r.submitted_role, // tenant | landlord
    status: r.status, // pending | confirmed | rejected
    confirmedAmount: r.confirmed_amount == null ? null : Number(r.confirmed_amount),
    reviewedRole: r.reviewed_role,
    reviewedAt: r.reviewed_at,
    rejectReason: r.reject_reason,
    createdAt: r.created_at,
  }),
  payments: (r) => ({
    id: r.id,
    landlordId: r.landlord_id,
    tenantId: r.tenant_id,
    propertyId: r.property_id,
    period: r.period,
    amount: Number(r.amount),
    amountPaid: Number(r.amount_paid ?? (r.status === 'paid' ? r.amount : 0)),
    balance: r.status === 'paid' ? 0 : Number(r.amount) - Number(r.amount_paid ?? 0), // still owed
    dueDate: r.due_date,
    paidAt: r.paid_at,
    method: r.method,
    reference: r.reference,
    // "overdue" is derived, not stored
    status: r.status === 'paid' ? 'paid' : r.due_date < today() ? 'overdue' : 'pending',
  }),
  notifications: (r) => ({
    id: r.id,
    tenantId: r.tenant_id,
    landlordId: r.landlord_id,
    type: r.type,
    title: r.title,
    body: r.body,
    read: r.read,
    tenantHidden: r.tenant_hidden === true, // deleted by the tenant (landlord still sees it)
    createdAt: r.created_at,
  }),
  // Tenant asks to leave their room (approved by their landlord or the main admin)
  move_out_requests: (r) => ({
    id: r.id,
    tenantId: r.tenant_id,
    landlordId: r.landlord_id,
    propertyId: r.property_id,
    userId: r.user_id,
    rating: r.rating,
    review: r.review,
    reason: r.reason,
    details: r.details,
    status: r.status, // pending | approved | declined | cancelled
    decidedRole: r.decided_role,
    decidedAt: r.decided_at,
    decisionNote: r.decision_note,
    createdAt: r.created_at,
  }),
  // Every amount received (cash or mobile money)
  payment_receipts: (r) => ({
    id: r.id,
    paymentId: r.payment_id,
    tenantId: r.tenant_id,
    landlordId: r.landlord_id,
    amount: Number(r.amount),
    method: r.method,
    reference: r.reference,
    note: r.note,
    receivedAt: r.received_at,
  }),
  // Inbox for landlords and the main admin
  staff_notifications: (r) => ({
    id: r.id,
    type: r.type,
    title: r.title,
    body: r.body,
    url: r.url,
    read: r.read,
    createdAt: r.created_at,
  }),
}

const TABLES = Object.keys(map)
const byNewest = (field) => (a, b) => new Date(b[field]) - new Date(a[field])
let channel = null

export const useRentalStore = defineStore('rental', {
  state: () => ({
    properties: [],
    rentals: [],
    tenants: [],
    payments: [],
    notifications: [],
    payment_receipts: [],
    staff_notifications: [], // landlord / main admin inbox
    cash_payments: [],
    move_out_requests: [],
    landlords: [], // main admin only
    audit: [], // main admin only: activity log
    owner: null, // tenant: their landlord's contact details
    loaded: false,
    error: '',
  }),

  getters: {
    propertyById: (s) => (id) => s.properties.find((p) => p.id === id),
    rentalById: (s) => (id) => s.rentals.find((r) => r.id === id),
    // Rooms of a rental, in natural order (Room 2 before Room 10)
    roomsOf: (s) => (rentalId) =>
      s.properties
        .filter((p) => p.rentalId === rentalId)
        .sort((a, b) => a.name.localeCompare(b.name, undefined, { numeric: true })),
    // "Room 3 · Kira Rentals" for rooms, the plain name for houses
    placeName: (s) => (id) => {
      const p = s.properties.find((x) => x.id === id)
      if (!p) return '—'
      const r = p.rentalId && s.rentals.find((x) => x.id === p.rentalId)
      return r ? `${p.name} · ${r.name}` : p.name
    },
    tenantById: (s) => (id) => s.tenants.find((t) => t.id === id),
    tenantForUser: (s) => (userId) => s.tenants.find((t) => t.userId === userId),
    tenantForProperty: (s) => (propertyId) => s.tenants.find((t) => t.propertyId === propertyId),
    currentTenants: (s) => s.tenants.filter((t) => t.propertyId),
    formerTenants: (s) =>
      s.tenants.filter((t) => !t.propertyId).sort((a, b) => (b.endedAt ?? '').localeCompare(a.endedAt ?? '')),

    // One entry per PERSON who has at least one ended stay; their stays newest first.
    // status 'active' = renting again right now.
    tenantRecords(s) {
      const byPerson = new Map()
      for (const t of s.tenants) {
        if (!byPerson.has(t.personId)) byPerson.set(t.personId, [])
        byPerson.get(t.personId).push(t)
      }
      const stayDate = (t) => t.endedAt ?? t.leaseStart ?? t.createdAt ?? ''
      return [...byPerson.values()]
        .filter((stays) => stays.some((t) => !t.propertyId))
        .map((stays) => {
          // current stay first, then most recent
          stays.sort((a, b) => Number(Boolean(b.propertyId)) - Number(Boolean(a.propertyId)) || stayDate(b).localeCompare(stayDate(a)))
          const current = stays.find((t) => t.propertyId) ?? null
          const latest = current ?? stays[0]
          return {
            personId: latest.personId,
            name: latest.name,
            email: latest.email,
            phone: latest.phone,
            status: current ? 'active' : 'former',
            current,
            latestEnded: stays.find((t) => !t.propertyId),
            stays,
          }
        })
        .sort((a, b) => stayDate(b.latestEnded).localeCompare(stayDate(a.latestEnded)))
    },

    paymentsForTenant: (s) => (tenantId) =>
      s.payments.filter((p) => p.tenantId === tenantId).sort((a, b) => b.period.localeCompare(a.period)),
    duesForTenant: (s) => (tenantId) =>
      s.payments.filter((p) => p.tenantId === tenantId && p.status !== 'paid').sort((a, b) => a.dueDate.localeCompare(b.dueDate)),
    cashForTenant: (s) => (tenantId) => s.cash_payments.filter((c) => c.tenantId === tenantId).sort(byNewest('createdAt')),
    pendingMoveOuts: (s) => s.move_out_requests.filter((r) => r.status === 'pending').sort(byNewest('createdAt')),
    // Tenant: their latest request to leave
    myMoveOut: (s) => (userId) => s.move_out_requests.filter((r) => r.userId === userId).sort(byNewest('createdAt'))[0] ?? null,
    pendingCash: (s) => s.cash_payments.filter((c) => c.status === 'pending').sort(byNewest('createdAt')),
    notificationsForTenant: (s) => (tenantId) =>
      s.notifications.filter((n) => n.tenantId === tenantId).sort(byNewest('createdAt')),

    stats(s) {
      const occupied = new Set(s.tenants.map((t) => t.propertyId).filter(Boolean))
      const month = today().slice(0, 7)
      const thisMonth = s.payments.filter((p) => p.period === month)
      return {
        properties: s.properties.length,
        occupied: s.properties.filter((p) => occupied.has(p.id)).length,
        vacant: s.properties.filter((p) => !occupied.has(p.id)).length,
        collected: thisMonth.reduce((sum, p) => sum + p.amountPaid, 0),
        expected: thisMonth.reduce((sum, p) => sum + p.amount, 0),
        outstanding: s.payments.reduce((sum, p) => sum + p.balance, 0),
        overdue: s.payments.filter((p) => p.status === 'overdue').length,
      }
    },
  },

  actions: {
    // ── Loading ──────────────────────────────────────────────
    async load() {
      this.error = ''
      const auth = useAuthStore()
      try {
        // Newer, optional tables (receipts, inbox) must never stop the app from loading
        const OPTIONAL = new Set(['payment_receipts', 'staff_notifications', 'cash_payments', 'rentals', 'move_out_requests'])
        const loadTable = (t) =>
          OPTIONAL.has(t)
            ? this.reload(t).catch((e) => console.warn(`[renta] ${t} unavailable (database update not run yet?): ${e.message}`))
            : this.reload(t)
        await Promise.all([
          ...TABLES.map(loadTable),
          auth.isSuperadmin && this.loadLandlords(),
          auth.isSuperadmin && this.loadAudit().catch((e) => console.warn(`[renta] activity log unavailable: ${e.message}`)),
        ])
        if (auth.isTenant) await this.loadOwner()
        this.loaded = true
      } catch (e) {
        this.error = e.message
      }
    },

    async reload(table) {
      const rows = must(await supabase.from(table).select('*').order('created_at', { ascending: false }))
      this[table] = rows.map(map[table])
    },

    // Tenant: contact details of the landlord they're connected to.
    async loadOwner() {
      const landlordId = this.tenantForUser(useAuthStore().user?.id)?.landlordId
      this.owner = landlordId
        ? must(await supabase.from('profiles').select('full_name, email, phone').eq('id', landlordId).maybeSingle())
        : null
    },

    // ── Main admin ───────────────────────────────────────────
    async loadLandlords() {
      const rows = must(
        await supabase.from('profiles').select('*').eq('role', 'landlord').order('created_at', { ascending: false }),
      )
      this.landlords = rows.map((r) => ({
        id: r.id,
        name: r.full_name,
        email: r.email,
        phone: r.phone,
        active: r.active,
        createdAt: r.created_at,
      }))
    },

    async createLandlord({ name, email, phone }) {
      await api('/api/admin/landlords', { name: titleCase(name), email, phone })
      await this.loadLandlords()
    },

    // Tenant accounts that aren't renting anything right now (deletable by the main admin)
    async loadInactiveTenantAccounts() {
      const rows = must(
        await supabase.from('profiles').select('id, email, full_name, created_at').eq('role', 'tenant').order('created_at', { ascending: false }),
      )
      const renting = new Set(this.tenants.filter((t) => t.userId && t.propertyId).map((t) => t.userId))
      return rows
        .filter((r) => !renting.has(r.id))
        .map((r) => ({
          id: r.id,
          email: r.email,
          name: r.full_name,
          createdAt: r.created_at,
          formerTenant: this.tenants.some((t) => t.userId === r.id),
        }))
    },

    // Main admin: permanently delete an inactive account (suspended landlord or tenant without a rental)
    async deleteUser(id) {
      await api(`/api/admin/users/${id}`, {}, 'DELETE')
      await this.load()
    },

    // changes: { name?, phone?, resetPassword?, active? }
    async updateLandlord(id, changes) {
      await api(`/api/admin/landlords/${id}`, changes, 'PATCH')
      await this.loadLandlords()
    },

    // ── Main admin console: every change is checked + logged by the database ──
    async loadAudit() {
      const rows = must(await supabase.from('admin_audit').select('*').order('created_at', { ascending: false }).limit(300))
      this.audit = rows.map((r) => ({
        id: r.id,
        action: r.action,
        targetType: r.target_type,
        targetId: r.target_id,
        summary: r.summary,
        createdAt: r.created_at,
      }))
    },
    async adminRpc(fn, args, reload = []) {
      const { data, error } = await supabase.rpc(fn, args)
      if (error) {
        if (/could not find the function|does not exist/i.test(error.message)) throw new Error(NEEDS_DB_UPDATE)
        throw new Error(error.message)
      }
      await Promise.all([...reload.map((t) => this.reload(t).catch(() => {})), this.loadAudit().catch(() => {})])
      return data
    },
    // Logs something done through the server (register / suspend / delete a landlord…)
    adminNote(action, type, id, summary) {
      return this.adminRpc('admin_note', { p_action: action, p_type: type, p_id: id ?? null, p_summary: summary }).catch(() => {})
    },
    adminUpdateProperty(id, { name, location, rent }) {
      return this.adminRpc('admin_update_property', { p_id: id, p_name: titleCase(name), p_location: location ?? '', p_rent: Math.round(Number(rent) || 0) }, ['properties'])
    },
    adminDeleteProperty(id) {
      return this.adminRpc('admin_delete_property', { p_id: id }, ['properties'])
    },
    adminUpdateTenant(id, { name, phone, email }) {
      return this.adminRpc('admin_update_tenant', { p_id: id, p_name: titleCase(name), p_phone: phone ?? '', p_email: email ?? '' }, ['tenants'])
    },
    adminEndTenancy(id, reason) {
      return this.adminRpc('admin_end_tenancy', { p_id: id, p_reason: reason ?? '' }, ['tenants', 'move_out_requests', 'notifications'])
    },
    // Archive everything, then delete every landlord + tenant (the server checks it's the main admin)
    async clearPlatform({ confirm, note }) {
      const res = await api('/api/admin/clear', { confirm, note })
      await this.load()
      return res
    },
    // Archives: list (without the big data), and one archive's full copy
    async loadArchives() {
      const { data, error } = await supabase.from('platform_archives').select('id, note, counts, created_at').order('created_at', { ascending: false })
      if (error) throw new Error(/does not exist|schema cache/i.test(error.message) ? NEEDS_DB_UPDATE : error.message)
      return data.map((r) => ({ id: r.id, note: r.note, counts: r.counts ?? {}, createdAt: r.created_at }))
    },
    async loadArchive(id) {
      return must(await supabase.from('platform_archives').select('*').eq('id', id).maybeSingle())
    },
    adminBroadcast({ audience, landlordId, message }) {
      return this.adminRpc('admin_broadcast', { p_audience: audience, p_landlord: landlordId || null, p_message: message.trim() }, ['notifications'])
    },

    subscribe() {
      if (channel) return
      channel = supabase.channel('renta-live')
      for (const table of ['notifications', 'payments', 'tenants', 'staff_notifications', 'cash_payments', 'properties', 'rentals', 'move_out_requests']) {
        channel.on('postgres_changes', { event: '*', schema: 'public', table }, () => {
          this.reload(table).catch(() => {})
          if (table === 'payments') this.reload('payment_receipts').catch(() => {}) // receipts change with payments
        })
      }
      if (useAuthStore().isSuperadmin) {
        channel.on('postgres_changes', { event: '*', schema: 'public', table: 'admin_audit' }, () => this.loadAudit().catch(() => {}))
      }
      channel.subscribe()
    },

    clear() {
      if (channel) supabase.removeChannel(channel)
      channel = null
      this.$reset()
    },

    // ── Tenant actions ───────────────────────────────────────
    // Marked read straight away on screen; put back if the database refuses.
    async markNotificationRead(id) {
      const n = this.notifications.find((x) => x.id === id)
      if (!n || n.read) return
      n.read = true
      const { error } = await supabase.from('notifications').update({ read: true }).eq('id', id)
      if (error) {
        n.read = false
        throw error
      }
    },

    // Tenant opened the app: rent status notification (the database sends at most one a day).
    async checkRentStatus() {
      try {
        const { error } = await supabase.rpc('check_rent_status')
        if (error) throw error
        await this.reload('notifications')
      } catch (e) {
        console.warn('[renta] rent status check skipped:', e.message)
      }
    },

    // Tenant deletes a notification: hidden for them only.
    async hideNotification(id) {
      const { error } = await supabase.from('notifications').update({ tenant_hidden: true, read: true }).eq('id', id)
      if (error) {
        throw new Error(
          /tenant_hidden/.test(error.message)
            ? 'Deleting needs a database update: run database/update_existing.sql in Supabase.'
            : error.message,
        )
      }
      this.notifications = this.notifications.filter((x) => x.id !== id)
    },

    async markAllRead(tenantId) {
      must(await supabase.from('notifications').update({ read: true }).eq('tenant_id', tenantId).eq('read', false))
      this.notifications.filter((n) => n.tenantId === tenantId).forEach((n) => (n.read = true))
    },


    // ── Owner actions ────────────────────────────────────────
    async addProperty(data) {
      const row = must(
        await supabase.from('properties').insert({ ...data, name: titleCase(data.name), location: titleCase(data.location) }).select().single(),
      )
      this.properties.unshift(map.properties(row))
    },

    async deleteProperty(id) {
      must(await supabase.from('properties').delete().eq('id', id))
      await this.load()
    },

    // Rename a house / room or change its rent: changes { name?, rent?, type?, bedrooms?, bathrooms?, location? }
    async updateProperty(id, changes) {
      if (changes.name) changes = { ...changes, name: titleCase(changes.name) }
      if (changes.location) changes = { ...changes, location: titleCase(changes.location) }
      const row = must(await supabase.from('properties').update(changes).eq('id', id).select().single())
      const p = this.properties.find((x) => x.id === id)
      if (p) Object.assign(p, map.properties(row))
    },

    // ── Rentals (a business with several rooms) ──
    // rooms: [{ name, rent }] — each becomes a property linked to the rental
    async addRental({ name, location, type, rooms }) {
      if (!rooms?.length) throw new Error('Add at least one room.')
      const { data, error } = await supabase
        .from('rentals')
        .insert({ name: titleCase(name), location: titleCase(location), type })
        .select()
        .single()
      if (error) throw new Error(/rentals|schema cache/.test(error.message) ? NEEDS_DB_UPDATE : error.message)
      const rental = map.rentals(data)
      try {
        await this.addRooms(rental.id, rooms, { location, type })
      } catch (e) {
        await supabase.from('rentals').delete().eq('id', rental.id) // don't leave an empty rental behind
        throw e
      }
      this.rentals.unshift(rental)
      return rental
    },

    async addRooms(rentalId, rooms, defaults = null) {
      const r = defaults ?? this.rentalById(rentalId)
      const rows = must(
        await supabase
          .from('properties')
          .insert(
            rooms.map((x) => ({
              rental_id: rentalId,
              name: titleCase(x.name),
              rent: Math.round(Number(x.rent) || 0),
              location: titleCase(r?.location) || '—',
              type: r?.type || 'Rooms',
              bedrooms: 1,
              bathrooms: 1,
            })),
          )
          .select(),
      )
      this.properties.push(...rows.map(map.properties))
    },

    async updateRental(id, changes) {
      if (changes.name) changes = { ...changes, name: titleCase(changes.name) }
      if (changes.location) changes = { ...changes, location: titleCase(changes.location) }
      const row = must(await supabase.from('rentals').update(changes).eq('id', id).select().single())
      const r = this.rentals.find((x) => x.id === id)
      if (r) Object.assign(r, map.rentals(row))
      // keep the rooms' location in step with the rental
      if (changes.location !== undefined) {
        must(await supabase.from('properties').update({ location: changes.location }).eq('rental_id', id))
        this.properties.filter((p) => p.rentalId === id).forEach((p) => (p.location = changes.location))
      }
    },

    // Same rent for every room
    async setRentalRent(id, rent) {
      must(await supabase.from('properties').update({ rent: Math.round(Number(rent)) }).eq('rental_id', id))
      this.properties.filter((p) => p.rentalId === id).forEach((p) => (p.rent = Math.round(Number(rent))))
    },

    async deleteRental(id) {
      if (this.roomsOf(id).some((p) => this.tenantForProperty(p.id))) {
        throw new Error('Some rooms still have tenants. End those tenancies first.')
      }
      must(await supabase.from('rentals').delete().eq('id', id))
      await this.load()
    },

    async addTenant({ name, email, phone, propertyId, leaseStart, leaseEnd, managedByLandlord = false }) {
      const row = must(
        await supabase
          .from('tenants')
          .insert({
            full_name: titleCase(name),
            email: email?.trim().toLowerCase() || null,
            phone: phone || null,
            property_id: propertyId || null,
            lease_start: leaseStart || null,
            lease_end: leaseEnd || null,
            ...(managedByLandlord ? { managed_by_landlord: true } : {}),
          })
          .select()
          .single(),
      )
      const tenant = map.tenants(row)
      this.tenants.unshift(tenant)
      return tenant
    },

    // Owner: new 6-character code (valid 20 min) the tenant enters to connect their account.
    async newConnectCode(tenantId) {
      const { code, expires_at } = must(await supabase.rpc('new_connect_code', { p_tenant_id: tenantId }))
      const t = this.tenants.find((x) => x.id === tenantId)
      if (t) Object.assign(t, { connectCode: code, connectCodeExpiresAt: expires_at })
      return { code, expiresAt: expires_at }
    },

    // Tenant: connect this account to the landlord's tenant record.
    async redeemConnectCode(code) {
      must(await supabase.rpc('redeem_connect_code', { p_code: code })) // the database also sends a welcome
      await this.load()
      await this.checkRentStatus()
    },

    // Moves the tenant to Records: frees the house, remembers it, keeps all their history.
    async endTenancy(tenantId) {
      const t = this.tenants.find((x) => x.id === tenantId)
      const row = must(
        await supabase
          .from('tenants')
          .update({ property_id: null, last_property_id: t?.propertyId ?? null, ended_at: new Date().toISOString() })
          .eq('id', tenantId)
          .select()
          .single(),
      )
      if (t) Object.assign(t, map.tenants(row))
    },

    // Brings a former tenant back as a NEW stay (fresh history). Old stays remain in Records.
    async readdTenant(formerId, { email, name, phone, propertyId, leaseStart, leaseEnd }) {
      const newId = must(
        await supabase.rpc('readd_tenant', {
          p_former_id: formerId,
          p_property_id: propertyId,
          p_full_name: titleCase(name),
          p_email: email ?? '',
          p_phone: phone ?? '',
          p_lease_start: leaseStart || null,
          p_lease_end: leaseEnd || null,
        }),
      )
      await this.reload('tenants')
      return this.tenantById(newId)
    },

    // tenantIds: array of tenant ids, or 'all'. Every notification is titled "Renta UG";
    // the stored title is the sender line, e.g. "From John Mukasa (Landlord)".
    async sendNotification({ tenantIds, body }) {
      const ids = tenantIds === 'all' ? this.tenants.filter((t) => t.propertyId).map((t) => t.id) : tenantIds
      if (!ids.length) throw new Error('No tenants to notify.')
      if (!body?.trim()) throw new Error('Write a message first.')
      const title = landlordSenderLine()
      const type = 'general'
      must(await supabase.from('notifications').insert(ids.map((tenant_id) => ({ tenant_id, type, title, body }))))
      await this.reload('notifications')
    },

    // Landlord records cash. The database applies it to the oldest unpaid rent first and confirms
    // to the tenant only when a month's rent is fully paid. Returns { applied, balance_after, parts }.
    async recordCashPayment({ tenantId, amount, receivedAt, note }) {
      const result = must(
        await supabase.rpc('record_cash_payment', {
          p_tenant_id: tenantId,
          p_amount: Math.round(Number(amount)),
          p_received_at: receivedAt ? new Date(`${receivedAt}T12:00:00`).toISOString() : new Date().toISOString(),
          p_note: note || null,
        }),
      )
      await Promise.all([this.reload('payments'), this.reload('payment_receipts'), this.reload('notifications')])
      return result
    },

    // Landlord: tenant without a smartphone, managed by the landlord (or back to using the app)
    async setManagedByLandlord(tenantId, managed) {
      const { error } = await supabase.from('tenants').update({ managed_by_landlord: managed }).eq('id', tenantId)
      if (error) throw new Error(/managed_by_landlord/.test(error.message) ? NEEDS_DB_UPDATE : error.message)
      const t = this.tenants.find((x) => x.id === tenantId)
      if (t) t.managedByLandlord = managed
    },

    // Landlord: tenant got a smartphone → create their login. They sign in with their phone number
    // (no connection code); on first sign-in they add an email and choose a password.
    async giveAppAccess(tenantId) {
      const res = await api(`/api/landlord/tenants/${tenantId}/app-access`, {})
      await this.reload('tenants')
      return res
    },

    // ── Cash payments (confirmed by the landlord or the main admin before they count) ──
    // Tenant: tenantId null = their own. Landlord: any of their tenants.
    async submitCash({ tenantId = null, amount, paidOn, note }) {
      const { data, error } = await supabase.rpc('submit_cash_payment', {
        p_tenant_id: tenantId,
        p_amount: Math.round(Number(amount)),
        p_paid_on: paidOn || null,
        p_note: note || null,
      })
      if (error) throw new Error(/submit_cash_payment|schema cache/.test(error.message) ? NEEDS_DB_UPDATE : error.message)
      await Promise.all([this.reload('cash_payments'), this.reload('notifications').catch(() => {})])
      return data
    },

    async confirmCash(id, amount) {
      const result = must(await supabase.rpc('confirm_cash_payment', { p_id: id, p_amount: amount ? Math.round(Number(amount)) : null }))
      await Promise.all(['cash_payments', 'payments', 'payment_receipts', 'notifications'].map((t) => this.reload(t).catch(() => {})))
      return result
    },

    async rejectCash(id, reason) {
      must(await supabase.rpc('reject_cash_payment', { p_id: id, p_reason: reason || null }))
      await Promise.all(['cash_payments', 'notifications'].map((t) => this.reload(t).catch(() => {})))
    },

    // ── Move-out requests ──
    async requestMoveOut({ rating, review, reason, details }) {
      const { error } = await supabase.rpc('request_move_out', { p_rating: rating || null, p_review: review || null, p_reason: reason, p_details: details || null })
      if (error) throw new Error(/request_move_out|schema cache/.test(error.message) ? NEEDS_DB_UPDATE : error.message)
      await this.reload('move_out_requests')
    },
    async cancelMoveOut() {
      must(await supabase.rpc('cancel_move_out'))
      await this.reload('move_out_requests')
    },
    // After the goodbye: unlink this account from the old stay, so it starts fresh next sign-in
    async finishMoveOut() {
      const { error } = await supabase.rpc('finish_move_out')
      if (error) console.warn('[renta] finish_move_out:', error.message)
    },
    async decideMoveOut(id, approve, note) {
      must(await supabase.rpc('decide_move_out', { p_id: id, p_approve: approve, p_note: note || null }))
      await Promise.all(['move_out_requests', 'tenants', 'notifications'].map((t) => this.reload(t).catch(() => {})))
    },

    // ── Staff inbox (landlords + main admin) ──
    async markStaffRead(id) {
      must(await supabase.from('staff_notifications').update({ read: true }).eq('id', id))
      const n = this.staff_notifications.find((x) => x.id === id)
      if (n) n.read = true
    },

    async markAllStaffRead() {
      const ids = this.staff_notifications.filter((n) => !n.read).map((n) => n.id)
      if (!ids.length) return
      must(await supabase.from('staff_notifications').update({ read: true }).in('id', ids))
      this.staff_notifications.forEach((n) => (n.read = true))
    },
  },
})
