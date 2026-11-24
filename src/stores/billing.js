import { defineStore, acceptHMRUpdate } from 'pinia'
import { supabase, must } from '@/lib/supabase'
import { useAuthStore } from './auth'

// Landlord subscriptions to Renta UG (monthly or yearly). See database/45_landlord_subscriptions.sql.
//   Landlord: their status, Renta UG's prices + receiving numbers, their own payments; submit / cancel.
//   Main admin: every payment, confirm / reject, add free days, prices and numbers.

const NEEDS_DB_UPDATE = 'This needs a database update: run database/update_existing.sql in Supabase.'
const kampalaToday = () => new Date().toLocaleDateString('en-CA', { timeZone: 'Africa/Kampala' })
export const daysBetween = (from, to) => Math.round((new Date(`${to}T00:00:00Z`) - new Date(`${from}T00:00:00Z`)) / 86_400_000)

const mapPayment = (r) => ({
  id: r.id,
  landlordId: r.landlord_id,
  tier: r.tier ?? 'small',
  plan: r.plan,
  months: r.months,
  amount: Number(r.amount),
  network: r.network,
  senderPhone: r.sender_phone,
  senderName: r.sender_name,
  reference: r.reference,
  paidOn: r.paid_on,
  status: r.status,
  periodStart: r.period_start,
  periodEnd: r.period_end,
  reviewedAt: r.reviewed_at,
  rejectReason: r.reject_reason,
  note: r.note ?? null,
  createdAt: r.created_at,
})
// How a subscription payment was made, for lists: "MTN", "Airtel", "Cash"
export const paidWith = (network) => ({ mtn: 'MTN', airtel: 'Airtel', cash: 'Cash' })[network] ?? network ?? ''
// Prices per scale: small (few houses / rooms) and big (many). Falls back to the single prices of
// database/45 if 46 hasn't been run yet.
const mapSettings = (r) => ({
  prices: {
    small: { monthly: Number(r?.small_monthly ?? r?.monthly_price ?? 55000), yearly: Number(r?.small_yearly ?? r?.yearly_price ?? 650000) },
    big: { monthly: Number(r?.big_monthly ?? 105000), yearly: Number(r?.big_yearly ?? 1200000) },
  },
  smallMaxUnits: Number(r?.small_max_units ?? 10),
  accounts: [
    r?.mtn_phone && { network: 'mtn', phone: r.mtn_phone, accountName: r.mtn_name ?? 'RENTA UG' },
    r?.airtel_phone && { network: 'airtel', phone: r.airtel_phone, accountName: r.airtel_name ?? 'RENTA UG' },
  ].filter(Boolean),
  raw: r ?? {},
})

// One subscription's status from its "last day covered" and plan. There is no free trial: a landlord
// can't use the app until their first payment is confirmed by the main admin (state 'none').
// exempt = the permanent free landlord account: always active, never pays.
export function subscriptionStatus(until, plan, { tier = null, exempt = false } = {}) {
  const today = kampalaToday()
  if (exempt) return { state: 'free', until: null, daysLeft: Infinity, plan: null, tier: null, active: true, exempt: true }
  if (!until) return { state: 'none', until: null, daysLeft: 0, plan, tier, active: false }
  const daysLeft = daysBetween(today, until) // 0 = last day is today
  const active = daysLeft >= 0
  const state = !active ? 'expired' : daysLeft <= 7 ? 'ending' : 'active'
  return { state, until, daysLeft, plan, tier, active }
}

let channel = null

export const useBillingStore = defineStore('billing', {
  state: () => ({
    settings: mapSettings(null),
    payments: [], // landlord: their own; main admin: everyone's
    loaded: false,
    unavailable: false, // database update not run yet
  }),

  getters: {
    // The signed-in landlord's subscription
    mine() {
      const p = useAuthStore().profile
      return subscriptionStatus(p?.subscription_until, p?.subscription_plan, { tier: p?.subscription_tier ?? null, exempt: p?.subscription_exempt === true })
    },
    pending: (s) => s.payments.filter((p) => p.status === 'pending'),
    price: (s) => (tier, plan) => s.settings.prices[tier]?.[plan] ?? 0,
    // Yearly vs 12 × monthly, per scale
    yearlySaving: (s) => (tier) => Math.max(0, s.settings.prices[tier].monthly * 12 - s.settings.prices[tier].yearly),
    yearlySavingPct: (s) => (tier) => {
      const p = s.settings.prices[tier]
      return p.monthly ? Math.max(0, Math.round((1 - p.yearly / (p.monthly * 12)) * 100)) : 0
    },
    // The scale that fits a number of houses + rooms
    recommendedTier: (s) => (units) => (units > s.settings.smallMaxUnits ? 'big' : 'small'),
    // How many houses + rooms the signed-in landlord's package allows (null = no limit)
    unitLimit() {
      const m = this.mine
      if (this.unavailable || m.exempt || !m.active || !m.plan) return null
      return m.tier === 'small' ? this.settings.smallMaxUnits : null
    },
  },

  actions: {
    async load() {
      const auth = useAuthStore()
      if (!auth.isLandlord && !auth.isSuperadmin) return
      // Speed: the landlord's lock / unlock comes from their profile (already loaded). Show the last
      // prices + payments saved on this device at once, so pages never wait on this request.
      const key = `renta:data:billing:${auth.user?.id}`
      if (!this.loaded) {
        try {
          const saved = JSON.parse(localStorage.getItem(key) || 'null')
          if (saved) Object.assign(this, { settings: saved.settings, payments: saved.payments, unavailable: saved.unavailable, loaded: true })
        } catch {
          /* storage blocked */
        }
      }
      const remember = () => {
        try {
          localStorage.setItem(key, JSON.stringify({ settings: this.settings, payments: this.payments, unavailable: this.unavailable }))
        } catch {
          /* storage full or blocked */
        }
      }
      let s, p
      try {
        ;[s, p] = await Promise.all([
          supabase.from('billing_settings').select('*').eq('id', 1).maybeSingle(),
          supabase.from('subscription_payments').select('*').order('created_at', { ascending: false }).limit(500),
        ])
      } catch (e) {
        this.loaded = true // never leave the landlord on a loading screen
        throw e
      }
      if (s.error || p.error) {
        this.unavailable = /does not exist|schema cache|billing_settings|subscription_payments/i.test((s.error ?? p.error).message)
        this.loaded = true
        remember()
        return
      }
      this.unavailable = false
      this.settings = mapSettings(s.data)
      this.payments = p.data.map(mapPayment)
      this.loaded = true
      remember()
    },

    // The subscription lives on the profile: read it again after a change
    async refreshProfile() {
      const auth = useAuthStore()
      if (!auth.user?.id) return
      const row = must(await supabase.from('profiles').select('*').eq('id', auth.user.id).maybeSingle())
      if (row) auth.profile = row
    },

    subscribe() {
      if (channel) return
      channel = supabase.channel('renta-billing')
      channel.on('postgres_changes', { event: '*', schema: 'public', table: 'subscription_payments' }, async () => {
        await this.load().catch(() => {})
        if (useAuthStore().isLandlord) await this.refreshProfile().catch(() => {})
      })
      channel.on('postgres_changes', { event: '*', schema: 'public', table: 'billing_settings' }, () => this.load().catch(() => {}))
      channel.subscribe()
    },
    clear() {
      if (channel) supabase.removeChannel(channel)
      channel = null
      this.$reset()
    },

    async rpc(fn, args) {
      const { data, error } = await supabase.rpc(fn, args)
      if (error) throw new Error(/could not find the function|does not exist/i.test(error.message) ? NEEDS_DB_UPDATE : error.message)
      await this.load()
      return data
    },

    // ── Landlord ──
    submitPayment({ tier, plan, network, senderPhone, senderName, paidOn }) {
      return this.rpc('submit_subscription_payment', {
        p_tier: tier, p_plan: plan, p_network: network, p_sender_phone: senderPhone ?? null,
        p_sender_name: senderName.trim().replace(/\s+/g, ' '), p_paid_on: paidOn || null,
      })
    },
    cancelPayment(id) {
      return this.rpc('cancel_subscription_payment', { p_id: id })
    },
    // First sign-in: how many houses + rooms they will register (picks the package)
    async setPlannedUnits(units) {
      const { error } = await supabase.rpc('set_planned_units', { p_units: Math.round(Number(units) || 0) })
      if (error) throw new Error(/could not find the function|does not exist/i.test(error.message) ? NEEDS_DB_UPDATE : error.message)
      await this.refreshProfile()
    },

    // Main admin: a landlord paid their subscription in cash → recorded as paid, subscription extended now
    recordCash(landlordId, { tier, plan, paidOn, note }) {
      return this.rpc('admin_record_subscription_cash', {
        p_landlord: landlordId, p_tier: tier, p_plan: plan, p_paid_on: paidOn || null, p_note: note ?? '',
      })
    },

    // ── Main admin ──
    confirmPayment(id) {
      return this.rpc('admin_confirm_subscription_payment', { p_id: id })
    },
    rejectPayment(id, reason) {
      return this.rpc('admin_reject_subscription_payment', { p_id: id, p_reason: reason ?? '' })
    },
    grantDays(landlordId, days, note) {
      return this.rpc('admin_grant_subscription', { p_landlord: landlordId, p_days: Math.round(Number(days) || 0), p_note: note ?? '' })
    },
    saveSettings({ smallMonthly, smallYearly, bigMonthly, bigYearly, smallMaxUnits, mtnPhone, mtnName, airtelPhone, airtelName }) {
      const n = (v) => Math.round(Number(String(v ?? '').replace(/[^\d]/g, '')) || 0)
      return this.rpc('admin_save_billing_settings', {
        p_small_monthly: n(smallMonthly), p_small_yearly: n(smallYearly),
        p_big_monthly: n(bigMonthly), p_big_yearly: n(bigYearly),
        p_small_max_units: n(smallMaxUnits),
        p_trial_days: 0, // no free trial
        p_mtn_phone: mtnPhone ?? '', p_mtn_name: mtnName ?? '',
        p_airtel_phone: airtelPhone ?? '', p_airtel_name: airtelName ?? '',
      })
    },
  },
})

// Dev only: swap in store changes on save, so pages never call getters the open copy doesn't have
if (import.meta.hot) import.meta.hot.accept(acceptHMRUpdate(useBillingStore, import.meta.hot))
