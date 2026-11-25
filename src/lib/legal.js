// The legal texts: Privacy policy, Terms and conditions, and how to delete an account.
// ONE source for the public pages (/privacy, /terms, /delete-account) and Settings → Terms, so they always say the same.
// Tenants and landlords each have their OWN text: legalFor('terms', 'tenant') never contains anything that is only for
// landlords, and the other way round. Have a Ugandan lawyer review them before launch.
import { SITE } from './site.js'

const N = SITE.name
const contact = SITE.supportEmail
const reach = contact ? `by email at ${contact}` : 'through the contact details on our website'

export const AUDIENCES = { tenant: 'Tenants', landlord: 'Landlords' }
export const LEGAL_PAGES = ['privacy', 'terms', 'delete-account']

// Sections are numbered in the order they are listed; ref('key') is a section's number
function numbered(list) {
  const shown = list.filter(Boolean)
  const ref = (key) => shown.findIndex((s) => s.key === key) + 1
  return shown.map((s, i) => ({ h: `${i + 1}. ${s.h}`, p: (typeof s.p === 'function' ? s.p(ref) : s.p).filter(Boolean) }))
}

function privacy(L) {
  return {
    title: 'Privacy policy',
    intro: `This policy is for ${L ? 'landlords' : 'tenants'}. It explains what personal data ${N} collects, why, who it is shared with, how long it is kept and the rights you have. It is written to meet the Data Protection and Privacy Act, 2019 of Uganda and its Regulations. By using ${N} you confirm you have read it.`,
    sections: numbered([
      {
        h: 'Who we are',
        p: [
          `${N} ("we", "us") runs the ${N} app and website (${SITE.url}). For the information described here we are the data controller, except ${
            L
              ? 'for the information you enter about your tenants: for that information you are the data controller and we process it on your behalf.'
              : 'for the information your landlord enters about you: for that information your landlord is the data controller and we process it on their behalf.'
          }`,
          `You can contact us about privacy ${reach}.`,
        ],
      },
      {
        h: 'What we collect',
        p: [
          'Account details: name, email address, phone number and password (stored only in scrambled, hashed form).',
          L
            ? 'Your rental business: the properties and rooms you add, rent amounts, the tenants you register, rent months, payments you record or confirm, notices, requests to leave and ratings.'
            : 'Rental details: the house or room you rent, rent amounts, rent months, dates paid, amounts paid, payment method (cash, MTN Mobile Money or Airtel Money), the names registered on the line a payment was sent from, notices, your requests to leave and ratings.',
          L && 'Receiving details: the mobile money number(s) and the registered name you choose to show your tenants.',
          L && 'Subscription details: your package, the amounts and dates paid, and the network, number and names a payment was sent from.',
          'Technical details: the device and browser used to sign in (for sign-in alerts), the address your phone gives us if you turn on notifications, a random device code, the type of device and the time, and your account when you are signed in (to count visits to the website and downloads of the app; the record of each visit is kept for 90 days), the stars you give if you rate the app, and error reports (the page, the error and the device type) so we can fix problems.',
          `We do NOT collect or store mobile money PINs, bank card details or the content of your mobile money account. Mobile money is sent from a phone, outside the app; we only record what ${L ? 'you or your tenant' : 'you or your landlord'} type in.`,
        ],
      },
      {
        h: 'Why we use it (and our legal basis)',
        p: [
          L
            ? 'To provide the service you signed up for (performance of a contract): keep your properties, tenants and payments, let you confirm payments, send notifications and reminders, and run your subscription.'
            : 'To provide the service you signed up for (performance of a contract): show your rent and payments, let your landlord confirm them, send you notifications and reminders, and keep your payment records.',
          'To keep the service safe and working (legitimate interest): sign-in alerts, preventing misuse, error reports and automatic system checks.',
          'To meet legal duties, for example keeping records or answering lawful requests from authorities.',
          'With your consent where the law requires it, for example phone notifications, which you can switch off at any time.',
          'We do not sell personal data, do not use it for advertising and do not make automated decisions that have legal effects on you.',
        ],
      },
      {
        h: 'Who can see it',
        p: [
          L
            ? 'You see the details, rent and payments of the tenants in your own houses only. Your tenants see your name, phone number and the receiving numbers you add. The main administrator of Renta UG can see all records to run, support and secure the service.'
            : 'You see your own information only. Your landlord sees your details, rent and payments for their house. Other landlords and other tenants cannot see them. The main administrator of Renta UG can see all records to run, support and secure the service.',
          `We use trusted service providers who process data only on our instructions: Supabase (database and sign-in), Netlify (hosting), Google Gmail or another email provider (sign-up codes and password reset links). Mobile money itself is handled by MTN or Airtel, under their own terms.`,
          'We may disclose information if the law, a court or a government authority requires it, or to protect the rights, property or safety of Renta UG, our users or the public.',
          'If Renta UG is sold or merged, data may pass to the new owner, who must keep protecting it under this policy.',
        ],
      },
      {
        h: 'Data stored outside Uganda',
        p: ['Our service providers may store data on secure servers outside Uganda. We only use providers that protect personal data to a standard at least equal to Ugandan law, with access controls and encryption in transit.'],
      },
      {
        h: 'How long we keep it',
        p: [
          `Account details: while the account is open. Payment and rent records: for as long as ${L ? 'you need' : 'your landlord needs'} them for ${L ? 'your' : 'their'} accounts and up to 7 years where tax or other law requires. Error reports and system checks: up to 12 months. Sign-up codes: deleted within a day.`,
          'When data is no longer needed, it is deleted or made anonymous.',
        ],
      },
      {
        h: 'How we protect it',
        p: ['Encrypted connections (HTTPS), hashed passwords, access rules so each person reaches only their own data, separation of server keys from the app, and activity logs for administrator actions. No system is completely secure; if a breach puts your data at risk we will inform you and the Personal Data Protection Office as the law requires.'],
      },
      {
        h: 'Your rights',
        p: [
          'Under the Data Protection and Privacy Act you may ask to see the personal data we hold about you, correct it, have it deleted, object to or restrict its use, and withdraw consent. You can change your name and phone number in Settings, and ask for deletion on the Delete account page.',
          `To use a right, contact us ${reach}. We may ask you to prove who you are. If you are not satisfied, you may complain to the Personal Data Protection Office (PDPO) of Uganda.`,
        ],
      },
      L && {
        h: 'Your tenants’ information',
        p: ['You must have a lawful reason to enter your tenants’ personal data, tell them it is kept in Renta UG, keep it correct and use it only to manage their tenancy.'],
      },
      {
        h: 'Children',
        p: ['Renta UG is for people aged 18 and over. We do not knowingly collect data about children. If you believe a child has an account, contact us and we will delete it.'],
      },
      {
        h: 'Changes to this policy',
        p: ['We may update this policy. The date at the top shows the latest version; important changes are announced in the app. Continuing to use Renta UG after a change means you accept the updated policy.'],
      },
    ]),
  }
}

function terms(L) {
  return {
    title: 'Terms and conditions',
    intro: `These terms are for ${L ? 'landlords' : 'tenants'}. They are a legal agreement between you and ${N}. By creating an account, signing in or using ${N} in any way you accept them. If you do not accept them, do not use ${N}.`,
    sections: numbered([
      {
        h: 'What Renta UG is (and is not)',
        p: [
          L
            ? `${N} is a software tool that helps you record your properties, tenants, rent and payments, and receive payment details from your tenants.`
            : `${N} is a software tool that helps you see your rent, send payment details to your landlord, keep your receipts and receive notices.`,
          `${N} is NOT a landlord, a property agent, a bank, a payment service provider or a mobile money operator. ${N} never receives, holds, transfers or refunds rent. There is no digital cash in ${N}: no wallet, no balance and no stored money. All rent moves directly between the tenant and the landlord, in cash or through MTN or Airtel, under those networks' own terms.`,
          `${N} is not a party to any tenancy, rental agreement or other arrangement between a landlord and a tenant. Those agreements, and everything about them, are only between ${L ? 'you and your tenant' : 'you and your landlord'}.`,
        ],
      },
      {
        h: 'Who may use it',
        p: [
          `You must be at least 18 years old and able to enter a binding contract. ${L ? 'Landlord accounts are created by Renta UG.' : 'You join with a code or details from your landlord, or sign up yourself.'}`,
          'You must give true, complete and current details and keep them up to date.',
        ],
      },
      {
        key: 'account',
        h: 'Your account',
        p: [
          'Keep your password and devices secure. You are responsible for everything done with your account. Tell us at once if you think someone else has used it.',
          'We may refuse, suspend or close any account, at any time and without notice, if we reasonably believe these terms or the law were broken, to protect other users, or to protect Renta UG.',
        ],
      },
      L && {
        key: 'subscription',
        h: 'Your subscription: no refunds',
        p: [
          'You pay Renta UG a subscription to use the app. It starts when Renta UG confirms the payment and runs for the time paid for.',
          'NO REFUNDS: subscription payments are not refunded, in full or in part, for any reason. This includes time not used, changing or closing the account, fewer houses or tenants than planned, choosing the wrong package, or an account suspended for breaking these terms. The only exception is where Ugandan law says a refund must be given.',
          'If you pay a subscription by mobile money, you send it from your own phone. You are responsible for checking the number, the name shown by the network and the amount before sending.',
        ],
      },
      {
        key: 'money',
        h: 'Rent, payments and records',
        p: [
          L
            ? 'You set or record the rent amounts, the rent months and the date of a tenant\'s first payment. Renta UG does not set, change, collect or guarantee rent.'
            : 'Rent amounts, rent months and the date of your first payment are set or recorded by your landlord. Renta UG does not set, change, collect or guarantee rent.',
          L
            ? 'Mobile money rent is sent by the tenant from their own phone to the number you entered. You are responsible for the numbers and names you enter and for confirming only payments you really received.'
            : 'You send mobile money rent from your own phone to the number your landlord entered. You are responsible for checking the number and the name shown by the network before sending, and for keeping the network\'s confirmation message.',
          `No digital cash is involved in Renta UG: it only keeps a record of payments made outside the app. Renta UG is therefore NOT responsible for any mobile money payment, whoever sends it or receives it${L ? ', including rent and subscription payments' : ''}: sending, receiving, wrong numbers or amounts, failed, delayed, reversed or lost money, fraud, network charges and limits. Any such problem is between you, the other person and MTN or Airtel.`,
          `A payment changes the rent records only when ${L ? 'you confirm it (or record it)' : 'your landlord confirms it (or records it)'}. Renta UG does not check with MTN, Airtel or any bank that money was sent or received.`,
          `Rent months, debt days, balances and dates in the app are calculated from what ${L ? 'you and your tenant' : 'you and your landlord'} enter. If something looks wrong, settle it with ${L ? 'your tenant' : 'your landlord'}; the landlord's confirmed records are what the app shows.`,
          `Refunds of rent, deposits, arrears, evictions and any dispute about money or the property are only between ${L ? 'you and your tenant' : 'you and your landlord'}.`,
        ],
      },
      L && {
        h: 'Your duties as a landlord',
        p: [
          'You must have the right to rent the properties you add, must follow Ugandan landlord and tenant law, and must enter accurate information about your tenants.',
          'You are responsible for having a lawful reason to enter your tenants\' personal data, and for telling your tenants that it is kept in Renta UG.',
          'You must not record payments that did not happen or refuse to confirm payments you received.',
        ],
      },
      !L && {
        h: 'Your duties as a tenant',
        p: ['Report only payments you really sent, with the correct amount and the correct names registered on the line you paid from.'],
      },
      {
        h: 'Notifications',
        p: [
          `By using Renta UG you agree to receive service messages about your account, ${L ? 'subscription, tenants' : 'rent'} and payments in the app, by phone notification and by email. Phone notifications can be switched off in Settings.`,
          `Messages depend on networks, phones and third parties and may be delayed or not delivered. Do not rely on a message alone; check the app${L ? '' : ' or ask your landlord'}.`,
        ],
      },
      {
        h: 'Acceptable use',
        p: ['Do not: break the law; enter false, misleading or someone else\'s information; impersonate anyone; try to reach accounts or data that are not yours; copy, resell or reverse-engineer the app; upload harmful code; overload or disrupt the service; or use it to harass, defraud or threaten anyone.'],
      },
      {
        h: 'Third-party services',
        p: ['Renta UG relies on others, including MTN, Airtel, Africa\'s Talking, Supabase, Netlify, Google and app stores. Their services are governed by their own terms, and Renta UG is not responsible for them or for their failures.'],
      },
      {
        h: 'Availability and changes to the service',
        p: ['We work to keep Renta UG running and accurate, but we do not promise it will always be available, error-free or secure. We may change, pause or stop any part of the service, including for maintenance, at any time.'],
      },
      {
        key: 'warranty',
        h: 'No warranties',
        p: ['To the fullest extent the law allows, Renta UG is provided "as is" and "as available", without any promise or warranty of any kind, express or implied, including fitness for a particular purpose, accuracy of calculations or uninterrupted use.'],
      },
      {
        key: 'liability',
        h: 'Limit of our liability',
        p: [
          `To the fullest extent the law allows, Renta UG, its owners, staff and partners are not liable for any indirect or consequential loss, ${L ? 'lost rent, lost income, ' : ''}lost data, or any loss arising from: payments between landlords and tenants; any mobile money payment; money sent to a wrong number; information entered by users; decisions made using the app; messages that are late or not delivered; or the service being unavailable.`,
          `Where liability cannot be excluded, our total liability for all claims is limited to ${L ? 'the amount you paid Renta UG for the service in the 12 months before the claim, or UGX 100,000, whichever is lower' : 'UGX 100,000'}.`,
          'Nothing in these terms limits any liability that cannot be limited under Ugandan law.',
        ],
      },
      {
        key: 'indemnity',
        h: 'Your promise to cover our losses (indemnity)',
        p: [`You agree to compensate and protect Renta UG, its owners and staff against any claim, loss, cost or penalty (including reasonable legal fees) caused by your use of the service, information you enter, your breach of these terms or the law, or any dispute between you and ${L ? 'a tenant' : 'a landlord'}.`],
      },
      {
        h: 'Ownership',
        p: [`The ${N} app, name, logo, design and software belong to ${N}. You may use the app only as these terms allow. You keep ownership of the information you enter, and you allow us to store and use it to provide the service as described in the Privacy policy.`],
      },
      {
        h: 'Ending your use',
        p: (ref) => {
          const keep = ['subscription', 'money', 'warranty', 'liability', 'indemnity', 'events', 'law'].map(ref).filter(Boolean)
          return [
            `You may stop using Renta UG and ask to delete your account at any time (see Delete account). We may end or suspend your access as described in section ${ref('account')}. Sections ${keep.slice(0, -1).join(', ')} and ${keep.at(-1)} continue to apply after your account ends.`,
          ]
        },
      },
      {
        key: 'events',
        h: 'Events outside our control',
        p: ['Renta UG is not responsible for delays or failures caused by events outside its reasonable control, such as power or internet failures, network or provider outages, government action, strikes, natural disasters or cyber attacks.'],
      },
      {
        key: 'law',
        h: 'Law and disputes',
        p: [
          'These terms are governed by the laws of the Republic of Uganda.',
          'If you have a complaint, contact us first so we can try to solve it. If it is not solved within 30 days, either side may refer it to mediation in Kampala, and failing that to the courts of Uganda, which have exclusive jurisdiction.',
        ],
      },
      {
        h: 'General',
        p: [
          'These terms, with the Privacy policy, are the whole agreement between you and Renta UG about the service. If any part is found invalid, the rest still applies. If we do not enforce a right straight away, we have not given it up. You may not transfer your rights under these terms; we may transfer ours to a new owner of the service.',
          'We may update these terms. The date at the top shows the latest version and important changes are announced in the app. Continuing to use Renta UG after a change means you accept the updated terms.',
          `Questions about these terms? Contact us ${reach}.`,
        ],
      },
    ]),
  }
}

function deleteAccount(L) {
  return {
    title: 'Delete your account',
    intro: `You can ask us to delete your ${N} account and personal data at any time.`,
    sections: [
      { h: 'How to ask', p: [`Send a request ${reach} from the email address or phone number linked to your account. Say "Delete my account" and include your full name.`, 'We check it is really you, then delete the account, normally within 30 days.'] },
      { h: 'What is deleted', p: [L ? 'Your sign-in, name, email, phone number, notification settings, your properties and your tenants\' records in Renta UG. Download any reports you need first.' : 'Your sign-in, name, email, phone number, notification settings and the link to your home.'] },
      {
        h: 'What may be kept',
        p: [
          L
            ? 'Payment records that the law requires us to keep are kept for as long as needed (see the Privacy policy) and are no longer linked to your profile where possible. Subscription payments are not refunded.'
            : 'Rent and payment records your landlord needs for their accounts, or that the law requires us to keep, are kept for as long as needed (see the Privacy policy) and are no longer linked to your profile where possible.',
        ],
      },
    ],
  }
}

const build = { privacy, terms, 'delete-account': deleteAccount }

// The text of one page for one kind of account: 'tenant' or 'landlord'
export const legalFor = (page, audience) => (build[page] ?? privacy)(audience === 'landlord')
