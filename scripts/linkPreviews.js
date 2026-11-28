// What WhatsApp, Facebook, X and others show when a Renta link is shared. They don't run the app's code, they only
// read the page's <head>, so after each build every public page gets its own copy of index.html with its own words
// and picture (dist/join.html, dist/login.html…). The app inside is the same.
// The title is the app's name and nothing else, on every page and in every preview: "Renta UG".
import { readFileSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

export const SITE_URL = 'https://rentaug.netlify.app'
export const TITLE = 'Renta UG'
const RENTA = { image: 'share-renta.jpg', alt: 'Renta UG: pay and manage rent with ease' }
const INVITE = { image: 'share-invite-2.jpg', alt: 'Renta UG: your rent account is ready' }

export const PAGES = {
  '': { description: 'Pay rent with MTN or Airtel, see your rental time and keep every receipt. For tenants and landlords in Uganda.', ...RENTA },
  i: { description: 'Your landlord has opened a rent account for you. Open the link, then sign in with the number in the message.', private: true, ...INVITE },
  join: { description: 'Install the app and sign in to your rent account.', private: true, ...RENTA },
  login: { description: 'Pay your rent, see your rental time and manage your properties.', ...RENTA },
  signup: { description: 'Join your landlord on Renta UG and pay your rent in a few taps.', ...RENTA },
  'forgot-password': { description: 'Enter your email and we will send you a secure link.', private: true, ...RENTA },
  'reset-password': { description: 'This secure link works once and expires after an hour.', private: true, ...RENTA },
  privacy: { description: 'How Renta UG collects, uses and protects your information.', ...RENTA },
  terms: { description: 'The terms for using Renta UG.', ...RENTA },
  'delete-account': { description: 'How to delete your Renta UG account and data.', ...RENTA },
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')

// Puts one page's words and picture into the built index.html
export function withPreview(html, path, page) {
  const url = `${SITE_URL}/${path}`
  const image = `${SITE_URL}/${page.image}`
  const tags = [
    `<title>${TITLE}</title>`,
    `<meta name="description" content="${esc(page.description)}" />`,
    page.private && '<meta name="robots" content="noindex" />',
    '<meta property="og:type" content="website" />',
    '<meta property="og:site_name" content="Renta UG" />',
    '<meta property="og:locale" content="en_GB" />',
    `<meta property="og:url" content="${url}" />`,
    `<meta property="og:title" content="${TITLE}" />`,
    `<meta property="og:description" content="${esc(page.description)}" />`,
    `<meta property="og:image" content="${image}" />`,
    `<meta property="og:image:secure_url" content="${image}" />`,
    '<meta property="og:image:type" content="image/jpeg" />',
    '<meta property="og:image:width" content="1200" />',
    '<meta property="og:image:height" content="630" />',
    `<meta property="og:image:alt" content="${esc(page.alt)}" />`,
    '<meta name="twitter:card" content="summary_large_image" />',
    `<meta name="twitter:title" content="${TITLE}" />`,
    `<meta name="twitter:description" content="${esc(page.description)}" />`,
    `<meta name="twitter:image" content="${image}" />`,
  ].filter(Boolean)
  const clean = html
    .replace(/\s*<title>[\s\S]*?<\/title>/, '')
    .replace(/\s*<meta\s+(?:name="(?:description|robots|twitter:[^"]*)"|property="og:[^"]*")[^>]*>/g, '')
  return clean.replace('</head>', () => `  ${tags.join('\n    ')}\n  </head>`)
}

export function linkPreviews() {
  let outDir = 'dist'
  return {
    name: 'renta-link-previews',
    apply: 'build',
    configResolved: (config) => {
      outDir = join(config.root, config.build.outDir)
    },
    closeBundle() {
      const html = readFileSync(join(outDir, 'index.html'), 'utf8')
      for (const [path, page] of Object.entries(PAGES)) {
        writeFileSync(join(outDir, `${path || 'index'}.html`), withPreview(html, path, page))
      }
    },
  }
}
