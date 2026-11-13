<script setup>
import { computed, ref } from 'vue'
import { BellOff, CheckCheck } from '@lucide/vue'
import { useTenant } from '@/composables/useTenant'
import PageHeader from '@/components/PageHeader.vue'
import NotificationItem from '@/components/NotificationItem.vue'
import EmptyState from '@/components/EmptyState.vue'
import PushPrompt from '@/components/PushPrompt.vue'

const { rental, id, notifications, unread } = useTenant()
const filter = ref('all')
const list = computed(() => (filter.value === 'unread' ? unread.value : notifications.value))
</script>

<template>
  <PageHeader title="Notifications" subtitle="Updates from your landlord about your home.">
    <button class="btn-secondary" :disabled="!unread.length" @click="rental.markAllRead(id)">
      <CheckCheck class="size-4" /> Mark all as read
    </button>
  </PageHeader>

  <PushPrompt class="mb-6" always />

  <div class="mb-4 inline-flex rounded-lg border border-slate-200 p-0.5 text-sm">
    <button
      v-for="f in ['all', 'unread']"
      :key="f"
      class="rounded-md px-3 py-1.5 font-medium capitalize transition-colors"
      :class="filter === f ? 'bg-slate-100 text-slate-900' : 'text-slate-500 hover:text-slate-700'"
      @click="filter = f"
    >
      {{ f }}<span v-if="f === 'unread' && unread.length"> ({{ unread.length }})</span>
    </button>
  </div>

  <section class="card overflow-hidden">
    <div v-if="list.length" class="divide-y divide-slate-100">
      <NotificationItem v-for="n in list" :key="n.id" :notification="n" @read="rental.markNotificationRead" />
    </div>
    <EmptyState v-else :icon="BellOff" title="You're all caught up" text="No notifications to show." />
  </section>
</template>
