// Answers to "Where did you hear about Renta UG?" (asked in the old welcome tour, which has been
// removed; the answers already given are still shown on the main admin's Statistics page).
// `only` limits a choice to one kind of account.
export const HEARD_SOURCES = [
  { id: 'another_landlord', label: 'Another landlord', only: 'landlord' },
  { id: 'my_landlord', label: 'My landlord', only: 'tenant' },
  { id: 'friend', label: 'Friend or family' },
  { id: 'whatsapp', label: 'WhatsApp' },
  { id: 'facebook', label: 'Facebook' },
  { id: 'tiktok', label: 'TikTok' },
  { id: 'instagram', label: 'Instagram' },
  { id: 'x', label: 'X (Twitter)' },
  { id: 'youtube', label: 'YouTube' },
  { id: 'google', label: 'Google search' },
  { id: 'radio', label: 'Radio' },
  { id: 'tv', label: 'TV' },
  { id: 'poster', label: 'Poster or flyer' },
  { id: 'event', label: 'Event or meeting' },
  { id: 'other', label: 'Somewhere else' },
]

export const heardLabel = (id) => HEARD_SOURCES.find((s) => s.id === id)?.label ?? id
