<script setup>
import { computed } from 'vue'
import { useRoute } from 'vue-router'
import { ArrowLeft } from '@lucide/vue'
import { SITE } from '@/lib/site'
import Logo from '@/components/Logo.vue'

// Public pages the app stores ask for: Privacy policy, Terms, and how to delete an account.
// They open without signing in. Edit the text below to change what people see.
const route = useRoute()
const contact = SITE.supportEmail
const askUs = contact ? `email ${contact}` : 'contact the Renta UG team'

const pages = {
  privacy: {
    title: 'Privacy policy',
    intro: `This explains what ${SITE.name} collects, why, and the choices you have.`,
    sections: [
      { h: 'What we collect', p: ['Your name, email address and phone number when you sign up or when your landlord adds you.', 'Your rental details: the house or room you rent, rent amounts, payments, receipts and notices.', 'Your mobile money number and network (MTN or Airtel) when you choose to pay. We never see or store your mobile money PIN.', 'A device name and time when you sign in, so we can tell you about a new sign-in. If you turn on notifications, your phone’s notification address.'] },
      { h: 'Why we use it', p: ['To run the app: show your rent, take and confirm payments, send receipts and reminders, and let landlords manage their homes.', 'We do not sell your information and we do not show adverts.'] },
      { h: 'Who can see it', p: ['Tenants see their own information. A landlord sees the tenants and payments of their own houses only.', 'Payments are processed by our payment partner, Relworx, together with MTN and Airtel. They receive the number, amount and reference needed to complete the payment.', 'Emails with your sign-up code are sent through our email provider.', 'Your data is stored with Supabase, protected by access rules so people can only reach what belongs to them.'] },
      { h: 'How long we keep it', p: ['While your account is open. Payment records may be kept longer where a landlord or the law needs them. When you delete your account, your personal details are removed.'] },
      { h: 'Your choices', p: ['You can change your name and phone number in Settings, turn notifications on or off, and ask us to delete your account (see the Delete account page).'] },
      { h: 'Contact', p: [contact ? `Questions? Email ${contact}.` : 'Questions? Contact the Renta UG team through your landlord or the details on our website.'] },
    ],
  },
  terms: {
    title: 'Terms of use',
    intro: `By creating an account or using ${SITE.name} you agree to these terms.`,
    sections: [
      { h: 'The service', p: [`${SITE.name} helps landlords manage rental homes and helps tenants pay rent, receive notices and keep payment records.`] },
      { h: 'Your account', p: ['Give correct details and keep your password private. You are responsible for what is done with your account.', 'Tenants connect to a home with a code from their landlord. Landlord accounts are set up by the Renta UG team.'] },
      { h: 'Rent and payments', p: ['Rent amounts and due dates are set by your landlord, not by Renta UG.', 'Mobile money payments are confirmed by the network before your rent is updated. You can pay part of a month’s rent (at least 60%); your rental month starts when you pay.', 'Disagreements about rent, refunds or cash payments are between you and your landlord.'] },
      { h: 'Fair use', p: ['Do not misuse the app, try to reach other people’s information, or record payments that did not happen. We may suspend accounts that do.'] },
      { h: 'Changes', p: ['We may improve the app and update these terms. Continuing to use the app means you accept the updated terms.'] },
    ],
  },
  'delete-account': {
    title: 'Delete your account',
    intro: 'You can ask us to delete your Renta UG account and personal data at any time.',
    sections: [
      { h: 'How to ask', p: [`Send a request to ${askUs} from the email address or phone number linked to your account. Say “Delete my account” and include your full name.`, 'We confirm it is you, then delete the account, normally within 30 days.'] },
      { h: 'What is deleted', p: ['Your sign-in, name, email, phone number, notification settings and connection to your home.'] },
      { h: 'What may be kept', p: ['Payment and rent records that your landlord needs for their accounts, or that the law requires, are kept without linking them to your personal profile where possible.'] },
      { h: 'Tenants and landlords', p: ['If you rent a home, your landlord keeps the record of rent paid. If you are a landlord, tell us if you want your tenants’ records removed too.'] },
    ],
  },
}
const page = computed(() => pages[route.meta.page] ?? pages.privacy)
</script>

<template>
  <div class="min-h-dvh bg-white">
    <header class="border-b border-slate-200/70">
      <div class="mx-auto flex h-16 max-w-3xl items-center justify-between px-4 sm:px-6">
        <Logo />
        <RouterLink to="/" class="inline-flex items-center gap-1.5 text-sm font-medium text-slate-600 hover:text-slate-900"><ArrowLeft class="size-4" /> Home</RouterLink>
      </div>
    </header>
    <main class="mx-auto max-w-3xl px-4 py-10 sm:px-6 sm:py-14">
      <h1 class="text-3xl font-extrabold tracking-tight text-slate-900 sm:text-4xl">{{ page.title }}</h1>
      <p class="mt-2 text-sm text-slate-500">Updated {{ SITE.updated }}</p>
      <p class="mt-5 leading-relaxed text-slate-700">{{ page.intro }}</p>
      <section v-for="s in page.sections" :key="s.h" class="mt-8">
        <h2 class="text-lg font-bold text-slate-900">{{ s.h }}</h2>
        <p v-for="(t, i) in s.p" :key="i" class="mt-2 leading-relaxed text-slate-600">{{ t }}</p>
      </section>
      <nav class="mt-12 flex flex-wrap gap-x-5 gap-y-2 border-t border-slate-200 pt-6 text-sm text-slate-500">
        <RouterLink to="/privacy" class="hover:text-slate-900">Privacy</RouterLink>
        <RouterLink to="/terms" class="hover:text-slate-900">Terms</RouterLink>
        <RouterLink to="/delete-account" class="hover:text-slate-900">Delete account</RouterLink>
      </nav>
    </main>
  </div>
</template>
