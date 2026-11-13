import { defineStore } from 'pinia'
import { supabase, must } from '@/lib/supabase'
import { api } from '@/lib/api'
import { refreshPushSubscription, disablePushForThisDevice } from '@/lib/push'
import { deviceName } from '@/lib/device'

// "New sign-in on <device> at <time>" (+ rent status for tenants). Never blocks signing in.
async function notifySignIn() {
  try {
    const { error } = await supabase.rpc('notify_sign_in', { p_device: await deviceName() })
    if (error) console.warn('[renta] sign-in notification skipped:', error.message)
  } catch {
    /* offline: skip */
  }
}

let initPromise = null

export const useAuthStore = defineStore('auth', {
  state: () => ({ session: null, profile: null, ready: false }),

  getters: {
    isAuthenticated: (s) => Boolean(s.session),
    role: (s) => s.profile?.role ?? 'tenant',
    isSuperadmin: (s) => s.profile?.role === 'superadmin',
    isLandlord: (s) => s.profile?.role === 'landlord',
    isTenant: (s) => !s.profile || s.profile.role === 'tenant',
    // Landlord still on the temporary password from the main admin
    needsPassword: (s) => s.profile?.role === 'landlord' && s.profile?.must_change_password === true,
    home: (s) =>
      ({ superadmin: '/admin2026/overview', landlord: '/landlord' })[s.profile?.role] ?? '/tenant',
    user: (s) =>
      s.session && {
        id: s.session.user.id,
        email: s.session.user.email,
        name: s.profile?.full_name || s.session.user.email,
        role: s.profile?.role ?? 'tenant',
      },
  },

  actions: {
    init() {
      initPromise ??= (async () => {
        const { data } = await supabase.auth.getSession()
        await this.setSession(data.session)
        supabase.auth.onAuthStateChange((_event, session) => {
          // Defer: calling Supabase inside this callback can deadlock the client
          setTimeout(() => this.setSession(session))
        })
        this.ready = true
      })()
      return initPromise
    },

    async setSession(session) {
      this.session = session
      if (!session) {
        this.profile = null
        return
      }
      if (this.profile?.id === session.user.id) return
      refreshPushSubscription() // this device's notifications now belong to this account
      try {
        this.profile = must(await supabase.from('profiles').select('*').eq('id', session.user.id).maybeSingle())
      } catch (e) {
        console.error('Could not load profile', e)
        this.profile = null
      }
    },

    // portal: 'admin' for /admin2026 (main admin only), 'app' for the normal login (landlords + tenants)
    async signIn(email, password, portal = 'app') {
      const result = await supabase.auth.signInWithPassword({ email, password })
      if (/banned/i.test(result.error?.message ?? '')) {
        throw new Error('This account has been suspended. Please contact Renta UG.')
      }
      const data = must(result)
      this.profile = null
      await this.setSession(data.session)

      const role = this.profile?.role
      const wrong =
        portal === 'admin' ? role !== 'superadmin' : role === 'superadmin'
      if (wrong) {
        await this.signOut()
        throw new Error(portal === 'admin' ? 'This is not an admin account.' : 'Invalid login credentials')
      }
      if (this.profile && this.profile.active === false) {
        await this.signOut()
        throw new Error('This account has been suspended. Please contact Renta UG.')
      }
      await notifySignIn()
    },

    // Returns true if the user is signed in immediately, false if they must confirm their email first.
    async signUp({ name, email, password }) {
      const data = must(
        await supabase.auth.signUp({
          email,
          password,
          options: { data: { full_name: name }, emailRedirectTo: window.location.origin },
        }),
      )
      if (data.session) await this.setSession(data.session)
      return Boolean(data.session)
    },

    // Landlord's first sign-in: email only (server-issued one-time token), no password.
    async firstLoginSignIn(email) {
      const { tokenHash } = await api('/api/auth/first-login', { email })
      const data = must(await supabase.auth.verifyOtp({ token_hash: tokenHash, type: 'email' }))
      this.profile = null
      await this.setSession(data.session)
      await notifySignIn()
    },

    // Sign-in page: what kind of account is this email?
    // 'first_login' | 'landlord' | 'tenant' | 'suspended' | 'not_found' | 'unknown' (couldn't check → normal sign-in)
    async emailStatus(email) {
      const { data, error } = await supabase.rpc('login_email_status', { p_email: email })
      if (!error && typeof data === 'string') return data
      if (error && !/login_email_status|function|schema cache/i.test(error.message)) return 'unknown' // e.g. offline
      // Database update not run yet: fall back to the Express server (local development)
      try {
        return (await api('/api/auth/status', { email })).firstLogin === true ? 'first_login' : 'unknown'
      } catch {
        return 'unknown'
      }
    },

    // First sign-in: choose their own password, then never ask again.
    async setOwnPassword(password) {
      const { error } = await supabase.auth.updateUser({ password })
      if (error) {
        throw new Error(
          /different from the old/i.test(error.message)
            ? 'Please choose a password different from the temporary one.'
            : error.message,
        )
      }
      must(await supabase.rpc('complete_password_setup'))
      this.profile = { ...this.profile, must_change_password: false }
    },

    // Settings → Account: users may change only their own name and phone (enforced by the database).
    async updateProfile({ name, phone }) {
      const changes = { full_name: name.trim(), phone: phone.trim() || null }
      must(await supabase.from('profiles').update(changes).eq('id', this.session.user.id))
      this.profile = { ...this.profile, ...changes }
    },

    // Settings → Change password: confirm the current password first, then set the new one.
    async changePassword(current, next) {
      const check = await supabase.auth.signInWithPassword({ email: this.session.user.email, password: current })
      if (check.error) {
        throw new Error(/invalid login/i.test(check.error.message) ? 'Your current password is not correct.' : check.error.message)
      }
      const { error } = await supabase.auth.updateUser({ password: next })
      if (error) {
        throw new Error(
          /different from the old/i.test(error.message) ? 'Your new password must be different from the current one.' : error.message,
        )
      }
    },

    async resetPassword(email) {
      must(await supabase.auth.resetPasswordForEmail(email, { redirectTo: window.location.origin }))
    },

    async signOut() {
      await disablePushForThisDevice()
      await supabase.auth.signOut()
      this.session = null
      this.profile = null
    },
  },
})
