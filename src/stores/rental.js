import { defineStore } from 'pinia'
import { supabase, must } from '@/lib/supabase'
import { api } from '@/lib/api'
import { useAuthStore } from './auth'

// All app data, loaded from Supabase. Row level security decides what each user sees:
// the owner gets everything, a tenant only gets their own records.

const today = () => new Date().toLocaleDateString('en-CA') // YYYY-MM-DD, local time

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
    type: r.type,
    title: r.title,
    body: r.body,
    read: r.read,
    createdAt: r.created_at,
  }),
  // Every amount received (cash or mobile money)
  payment_receipts: (r) => ({
    id: r.id,
    paymentId: r.payment_id,
    tenantId: r.tenant_id,
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
    tenants: [],
    payments: [],
    notifications: [],
    payment_receipts: [],
    staff_notifications: [], // landlord / main admin inbox
    landlords: [], // main admin only
    owner: null, // tenant: their landlord's contact details
    loaded: false,
    error: '',
  }),

  getters: {
    propertyById: (s) => (id) => s.properties.find((p) => p.id === id),
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
        const OPTIONAL = new Set(['payment_receipts', 'staff_notifications'])
        const loadTable = (t) =>
          OPTIONAL.has(t)
            ? this.reload(t).catch((e) => console.warn(`[renta] ${t} unavailable (database update not run yet?): ${e.message}`))
            : this.reload(t)
        await Promise.all([...TABLES.map(loadTable), auth.isSuperadmin && this.loadLandlords()])
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
      await api('/api/admin/landlords', { name, email, phone })
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

    subscribe() {
      if (channel) return
      channel = supabase.channel('renta-live')
      for (const table of ['notifications', 'payments', 'tenants', 'staff_notifications']) {
        channel.on('postgres_changes', { event: '*', schema: 'public', table }, () => {
          this.reload(table).catch(() => {})
          if (table === 'payments') this.reload('payment_receipts').catch(() => {}) // receipts change with payments
        })
      }
      channel.subscribe()
    },

    clear() {
      if (channel) supabase.removeChannel(channel)
      channel = null
      this.$reset()
    },

    // ── Tenant actions ───────────────────────────────────────
    async markNotificationRead(id) {
      must(await supabase.from('notifications').update({ read: true }).eq('id', id))
      const n = this.notifications.find((x) => x.id === id)
      if (n) n.read = true
    },

    async markAllRead(tenantId) {
      must(await supabase.from('notifications').update({ read: true }).eq('tenant_id', tenantId).eq('read', false))
      this.notifications.filter((n) => n.tenantId === tenantId).forEach((n) => (n.read = true))
    },


    // ── Owner actions ────────────────────────────────────────
    async addProperty(data) {
      const row = must(await supabase.from('properties').insert(data).select().single())
      this.properties.unshift(map.properties(row))
    },

    async deleteProperty(id) {
      must(await supabase.from('properties').delete().eq('id', id))
      await this.load()
    },

    async addTenant({ name, email, phone, propertyId, leaseStart, leaseEnd }) {
      const row = must(
        await supabase
          .from('tenants')
          .insert({
            full_name: name,
            email: email?.trim().toLowerCase() || null,
            phone: phone || null,
            property_id: propertyId || null,
            lease_start: leaseStart || null,
            lease_end: leaseEnd || null,
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
      must(await supabase.rpc('redeem_connect_code', { p_code: code }))
      await this.load()
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
          p_full_name: name,
          p_email: email ?? '',
          p_phone: phone ?? '',
          p_lease_start: leaseStart || null,
          p_lease_end: leaseEnd || null,
        }),
      )
      await this.reload('tenants')
      return this.tenantById(newId)
    },

    // tenantIds: array of tenant ids, or 'all'
    async sendNotification({ tenantIds, type, title, body }) {
      const ids = tenantIds === 'all' ? this.tenants.filter((t) => t.propertyId).map((t) => t.id) : tenantIds
      if (!ids.length) throw new Error('No tenants to notify.')
      must(await supabase.from('notifications').insert(ids.map((tenant_id) => ({ tenant_id, type, title, body }))))
      await this.reload('notifications')
    },


    // Creates a pending rent charge for every tenant with a property (skips ones that already exist).
    async generateCharges(period, dueDate) {
      const rows = this.tenants
        .filter((t) => t.propertyId && this.propertyById(t.propertyId))
        .map((t) => ({
          tenant_id: t.id,
          property_id: t.propertyId,
          period,
          amount: this.propertyById(t.propertyId).rent,
          due_date: dueDate,
        }))
      if (!rows.length) throw new Error('No tenants with a property to charge.')

      const created = must(
        await supabase.from('payments').upsert(rows, { onConflict: 'tenant_id,period', ignoreDuplicates: true }).select(),
      )
      if (created.length) {
        const label = new Date(`${period}-01T00:00:00`).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' })
        must(
          await supabase.from('notifications').insert(
            created.map((p) => ({
              tenant_id: p.tenant_id,
              type: 'payment',
              title: `${label} rent is ready to pay`,
              body: `UGX ${Number(p.amount).toLocaleString()} is due on ${new Date(p.due_date).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' })}.`,
            })),
          ),
        )
      }
      await Promise.all([this.reload('payments'), this.reload('notifications')])
      return created.length
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
