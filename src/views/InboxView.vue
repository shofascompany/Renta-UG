<script setup>
import { computed } from 'vue'
import { CheckCheck, Inbox, Wallet } from '@lucide/vue'
import { useRentalStore } from '@/stores/rental'
import { useAuthStore } from '@/stores/auth'
import { timeAgo } from '@/utils/format'
import PageHeader from '@/components/PageHeader.vue'
import EmptyState from '@/components/EmptyState.vue'
import PushPrompt from '@/components/PushPrompt.vue'

// Inbox for landlords and the main admin, e.g. "Payment received" when an online payment is verified.
const rental = useRentalStore()
const auth = useAuthStore()
const items = computed(() => [...rental.staff_notifications].sort((a, b) => b.createdAt.localeCompare(a.createdAt)))
const unread = computed(() => items.value.filter((n) => !n.read).length)
</script>

<template>
  <PageHeader
    title="Inbox"
    :subtitle="auth.isSuperadmin ? 'Confirmations of payments received across all landlords.' : 'Confirmations of payments your tenants made online.'"
  >
    <button class="btn-secondary" :disabled="!unread" @click="rental.markAllStaffRead()">
      <CheckCheck class="size-4" /> Mark all as read
    </button>
  </PageHeader>

  <PushPrompt class="mb-6" always />

  <section class="card overflow-hidden">
    <ul v-if="items.length" class="divide-y divide-slate-100">
      <li
        v-for="n in items"
        :key="n.id"
        class="flex gap-3 px-5 py-4 transition-colors"
        :class="n.read ? '' : 'cursor-pointer bg-brand-50/40 hover:bg-brand-50/70'"
        @click="!n.read && rental.markStaffRead(n.id)"
      >
        <div class="flex size-9 shrink-0 items-center justify-center rounded-full bg-emerald-50">
          <Wallet class="size-4 text-emerald-600" />
        </div>
        <div class="min-w-0 flex-1">
          <div class="flex items-start justify-between gap-3">
            <p class="text-sm font-medium text-slate-900">{{ n.title }}</p>
            <span class="shrink-0 text-xs text-slate-400">{{ timeAgo(n.createdAt) }}</span>
          </div>
          <p class="mt-0.5 text-sm text-slate-600">{{ n.body }}</p>
        </div>
        <span v-if="!n.read" class="mt-1.5 size-2 shrink-0 rounded-full bg-brand-600" aria-label="Unread" />
      </li>
    </ul>
    <EmptyState v-else :icon="Inbox" title="No messages yet" text="When a tenant pays online and it's verified, you'll get a confirmation here." />
  </section>
</template>
