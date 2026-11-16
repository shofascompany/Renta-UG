// Public facts about the app, used on the landing site and the store pages.
export const SITE = {
  name: 'Renta UG',
  url: 'https://rentaug.netlify.app',
  // Shown on the Privacy and Delete-account pages when set (add VITE_SUPPORT_EMAIL in Netlify)
  supportEmail: import.meta.env.VITE_SUPPORT_EMAIL || '',
  updated: '15 November 2026',
}
