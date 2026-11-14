<script setup>
import { FileText } from '@lucide/vue'
import SettingsSubpage from '@/components/SettingsSubpage.vue'

// Terms & conditions shown in Settings. Edit the text below to change what users see.
const updated = '13 November 2026'

const sections = [
  {
    title: '1. About Renta UG',
    body: [
      'Renta UG is an app that helps landlords manage their rental houses and helps tenants pay rent, receive notices and keep their payment records in one place.',
      'By creating an account or using the app, you agree to these terms. If you do not agree, please do not use Renta UG.',
    ],
  },
  {
    title: '2. Your account',
    body: [
      'You must give correct details (name, email and phone number) and keep them up to date in Settings → Account details.',
      'Keep your password private. You are responsible for anything done with your account. If you think someone else has used it, change your password straight away.',
      'Tenants connect to a rental using a code from their landlord. Landlord accounts are created by Renta UG.',
    ],
  },
  {
    title: '3. Rent and payments',
    body: [
      'Rent amounts, due dates and rent charges are set by your landlord. Renta UG does not set or change rent.',
      'Mobile money payments (MTN Mobile Money and Airtel Money) are processed by the payment provider. A payment is recorded only after it has been confirmed by the provider.',
      'When you recharge (pay in advance), the money first clears any unpaid rent, then pays the months ahead in order.',
      'Keep the confirmation message from your mobile money provider. Contact your landlord about refunds or any disagreement about rent.',
    ],
  },
  {
    title: '4. Notifications',
    body: [
      'Renta UG sends notifications about rent, payments, reminders and sign-ins to your account. You can turn phone notifications on or off in Settings → Notifications.',
      'Deleting a notification removes it from your list only. Your landlord keeps their own record of notices they sent.',
    ],
  },
  {
    title: '5. Your information',
    body: [
      'We store the details needed to run the service: your name, email, phone number, rental details, payments and notifications.',
      'Your landlord can see your details, your rent charges and your payments for the house you rent from them. Your sign-in alerts are private to you.',
      'We do not sell your information. It is shared only with the payment provider to process payments, or when required by law.',
    ],
  },
  {
    title: '6. Acceptable use',
    body: [
      'Do not use Renta UG for anything unlawful, to send false information, or to try to access accounts or data that are not yours.',
      'We may suspend accounts that break these terms.',
    ],
  },
  {
    title: '7. Limits of the service',
    body: [
      'We work to keep Renta UG available and accurate, but the app may sometimes be unavailable, for example during maintenance or network problems.',
      'Renta UG is a tool between landlords and tenants. The tenancy agreement itself is between you and your landlord.',
    ],
  },
  {
    title: '8. Changes to these terms',
    body: [
      'We may update these terms from time to time. The date at the top shows the latest version. Continuing to use the app after a change means you accept the updated terms.',
    ],
  },
]
</script>

<template>
  <SettingsSubpage title="Terms & conditions" :subtitle="`Last updated ${updated}`" :icon="FileText">
    <div class="card divide-y divide-slate-100">
      <section v-for="s in sections" :key="s.title" class="px-5 py-5 sm:px-6">
        <h2 class="text-sm font-semibold text-slate-900">{{ s.title }}</h2>
        <p v-for="(p, i) in s.body" :key="i" class="mt-2 text-sm leading-relaxed text-slate-600">{{ p }}</p>
      </section>
    </div>
    <p class="px-1 text-xs text-slate-400">Questions about these terms? Contact your landlord or Renta UG.</p>
  </SettingsSubpage>
</template>
