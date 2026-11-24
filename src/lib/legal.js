// The legal texts: Privacy policy, Terms and conditions, and how to delete an account.
// ONE source for the public pages (/privacy, /terms, /delete-account) and Settings → Terms,
// so they always say the same thing. Have a Ugandan lawyer review them before launch.
import { SITE } from './site'

const N = SITE.name
const contact = SITE.supportEmail
const reach = contact ? `by email at ${contact}` : 'through the contact details on our website'

export const LEGAL = {
  privacy: {
    title: 'Privacy policy',
    intro: `This policy explains what personal data ${N} collects, why, who it is shared with, how long it is kept and the rights you have. It is written to meet the Data Protection and Privacy Act, 2019 of Uganda and its Regulations. By using ${N} you confirm you have read it.`,
    sections: [
      {
        h: '1. Who we are',
        p: [
          `${N} ("we", "us") runs the ${N} app and website (${SITE.url}). For the information described here we are the data controller, except for tenant information a landlord enters about their own tenants: for that information the landlord is the data controller and we process it on the landlord's behalf.`,
          `You can contact us about privacy ${reach}.`,
        ],
      },
      {
        h: '2. What we collect',
        p: [
          'Account details: name, email address, phone number and password (stored only in scrambled, hashed form).',
          'Rental details: the house or room rented, rent amounts, rent months, dates paid, amounts paid, payment method (cash, MTN Mobile Money or Airtel Money), the names registered on the line a payment was sent from, notices, move-out requests and ratings.',
          'Landlord payment details: the mobile money number(s) and the registered name a landlord chooses to show their tenants.',
          'Technical details: the device and browser used to sign in (for sign-in alerts), the address your phone gives us if you turn on notifications, a random device code when the installed app is opened (to count installs, without any personal details), and error reports (the page, the error and the device type) so we can fix problems.',
          'We do NOT collect or store mobile money PINs, bank card details or the content of your mobile money account. Mobile money is sent by the tenant from their own phone; we only record what the tenant or landlord types in.',
        ],
      },
      {
        h: '3. Why we use it (and our legal basis)',
        p: [
          'To provide the service you signed up for (performance of a contract): show rent and payments, let landlords confirm payments, send notifications, SMS and reminders, and keep payment records.',
          'To keep the service safe and working (legitimate interest): sign-in alerts, preventing misuse, error reports and automatic system checks.',
          'To meet legal duties, for example keeping records or answering lawful requests from authorities.',
          'With your consent where the law requires it, for example phone notifications, which you can switch off at any time.',
          'We do not sell personal data, do not use it for advertising and do not make automated decisions that have legal effects on you.',
        ],
      },
      {
        h: '4. Who can see it',
        p: [
          'Tenants see their own information. A landlord sees the details, rent and payments of the tenants in their own houses only. The main administrator of Renta UG can see all records to run, support and secure the service.',
          'We use trusted service providers who process data only on our instructions: Supabase (database and sign-in), Netlify (hosting), Google Gmail or another email provider (sign-up codes), and Africa\'s Talking (SMS to tenants\' phone numbers). Mobile money itself is handled by MTN or Airtel between the tenant and the landlord, under their own terms.',
          'We may disclose information if the law, a court or a government authority requires it, or to protect the rights, property or safety of Renta UG, our users or the public.',
          'If Renta UG is sold or merged, data may pass to the new owner, who must keep protecting it under this policy.',
        ],
      },
      {
        h: '5. Data stored outside Uganda',
        p: [
          'Our service providers may store data on secure servers outside Uganda. We only use providers that protect personal data to a standard at least equal to Ugandan law, with access controls and encryption in transit.',
        ],
      },
      {
        h: '6. How long we keep it',
        p: [
          'Account details: while the account is open. Payment and rent records: for as long as the landlord needs them for their accounts and up to 7 years where tax or other law requires. Error reports and system checks: up to 12 months. Sign-up codes: deleted within a day.',
          'When data is no longer needed, it is deleted or made anonymous.',
        ],
      },
      {
        h: '7. How we protect it',
        p: [
          'Encrypted connections (HTTPS), hashed passwords, access rules so each person reaches only their own data, separation of server keys from the app, and activity logs for administrator actions. No system is completely secure; if a breach puts your data at risk we will inform you and the Personal Data Protection Office as the law requires.',
        ],
      },
      {
        h: '8. Your rights',
        p: [
          'Under the Data Protection and Privacy Act you may ask to see the personal data we hold about you, correct it, have it deleted, object to or restrict its use, and withdraw consent. You can change your name and phone number in Settings, and ask for deletion on the Delete account page.',
          `To use a right, contact us ${reach}. We may ask you to prove who you are. If you are not satisfied, you may complain to the Personal Data Protection Office (PDPO) of Uganda.`,
        ],
      },
      {
        h: '9. Children',
        p: ['Renta UG is for people aged 18 and over. We do not knowingly collect data about children. If you believe a child has an account, contact us and we will delete it.'],
      },
      {
        h: '10. Changes to this policy',
        p: ['We may update this policy. The date at the top shows the latest version; important changes are announced in the app. Continuing to use Renta UG after a change means you accept the updated policy.'],
      },
    ],
  },

  terms: {
    title: 'Terms and conditions',
    intro: `These terms are a legal agreement between you and ${N}. By creating an account, signing in or using ${N} in any way you accept them. If you do not accept them, do not use ${N}.`,
    sections: [
      {
        h: '1. What Renta UG is (and is not)',
        p: [
          `${N} is a software tool that helps landlords record their properties, tenants, rent and payments, and helps tenants see their rent, send payment details to their landlord and receive notices.`,
          `${N} is NOT a landlord, a property agent, a bank, a payment service provider or a mobile money operator. ${N} never receives, holds, transfers or refunds rent or any other money. All money moves directly between the tenant and the landlord, in cash or through MTN or Airtel, under those networks' own terms.`,
          `${N} is not a party to any tenancy, rental agreement or other arrangement between a landlord and a tenant. Those agreements, and everything about them, are only between the landlord and the tenant.`,
        ],
      },
      {
        h: '2. Who may use it',
        p: [
          'You must be at least 18 years old and able to enter a binding contract. Landlord accounts are created by Renta UG; tenants join with a code or details from their landlord, or sign up themselves.',
          'You must give true, complete and current details and keep them up to date.',
        ],
      },
      {
        h: '3. Your account',
        p: [
          'Keep your password and devices secure. You are responsible for everything done with your account. Tell us at once if you think someone else has used it.',
          'We may refuse, suspend or close any account, at any time and without notice, if we reasonably believe these terms or the law were broken, to protect other users, or to protect Renta UG.',
        ],
      },
      {
        h: '4. Rent, payments and records',
        p: [
          'Rent amounts, rent months and the date of a tenant\'s first payment are set or recorded by the landlord. Renta UG does not set, change, collect or guarantee rent.',
          'Mobile money: the tenant sends money from their own phone to the number the landlord entered. The TENANT is responsible for checking the number and the name shown by the network before sending, and for keeping the network\'s confirmation message. The LANDLORD is responsible for the numbers they enter and for confirming only payments they really received.',
          'A payment changes the rent records only when the landlord confirms it (or records it). Renta UG does not check with MTN, Airtel or any bank that money was sent or received, and is not responsible for money sent to a wrong number, reversed, delayed, lost or charged fees by a network.',
          'Rent months, debt days, balances and dates in the app are calculated from what the landlord and tenant enter. If something looks wrong, the landlord and tenant must settle it between themselves; the landlord\'s confirmed records are what the app shows.',
          'Refunds, deposits, arrears, evictions and any dispute about money or the property are only between the landlord and the tenant.',
        ],
      },
      {
        h: '5. Landlords\' extra duties',
        p: [
          'Landlords must have the right to rent the properties they add, must follow Ugandan landlord and tenant law, and must enter accurate information about their tenants.',
          'Landlords are responsible for having a lawful reason to enter their tenants\' personal data, and for telling their tenants that it is kept in Renta UG.',
          'Landlords must not record payments that did not happen or refuse to confirm payments they received.',
        ],
      },
      {
        h: '6. Notifications and SMS',
        p: [
          'By using Renta UG you agree to receive service messages about your account, rent and payments in the app, by phone notification, by email and by SMS. Phone notifications can be switched off in Settings.',
          'Messages depend on networks, phones and third parties and may be delayed or not delivered. Do not rely on a message alone; check the app or ask your landlord.',
        ],
      },
      {
        h: '7. Acceptable use',
        p: [
          'Do not: break the law; enter false, misleading or someone else\'s information; impersonate anyone; try to reach accounts or data that are not yours; copy, resell or reverse-engineer the app; upload harmful code; overload or disrupt the service; or use it to harass, defraud or threaten anyone.',
        ],
      },
      {
        h: '8. Third-party services',
        p: ['Renta UG relies on others, including MTN, Airtel, Africa\'s Talking, Supabase, Netlify, Google and app stores. Their services are governed by their own terms, and Renta UG is not responsible for them or for their failures.'],
      },
      {
        h: '9. Availability and changes to the service',
        p: ['We work to keep Renta UG running and accurate, but we do not promise it will always be available, error-free or secure. We may change, pause or stop any part of the service, including for maintenance, at any time.'],
      },
      {
        h: '10. No warranties',
        p: ['To the fullest extent the law allows, Renta UG is provided "as is" and "as available", without any promise or warranty of any kind, express or implied, including fitness for a particular purpose, accuracy of calculations or uninterrupted use.'],
      },
      {
        h: '11. Limit of our liability',
        p: [
          'To the fullest extent the law allows, Renta UG, its owners, staff and partners are not liable for any indirect or consequential loss, lost rent, lost income, lost data, or any loss arising from: payments between landlords and tenants; money sent to a wrong number; information entered by users; decisions made using the app; messages that are late or not delivered; or the service being unavailable.',
          'Where liability cannot be excluded, our total liability for all claims is limited to the amount you paid Renta UG for the service in the 12 months before the claim, or UGX 100,000, whichever is lower.',
          'Nothing in these terms limits any liability that cannot be limited under Ugandan law.',
        ],
      },
      {
        h: '12. Your promise to cover our losses (indemnity)',
        p: ['You agree to compensate and protect Renta UG, its owners and staff against any claim, loss, cost or penalty (including reasonable legal fees) caused by your use of the service, information you enter, your breach of these terms or the law, or any dispute between you and a landlord or tenant.'],
      },
      {
        h: '13. Ownership',
        p: [`The ${N} app, name, logo, design and software belong to ${N}. You may use the app only as these terms allow. You keep ownership of the information you enter, and you allow us to store and use it to provide the service as described in the Privacy policy.`],
      },
      {
        h: '14. Ending your use',
        p: ['You may stop using Renta UG and ask to delete your account at any time (see Delete account). We may end or suspend your access as described in section 3. Sections 4, 10, 11, 12, 15 and 16 continue to apply after your account ends.'],
      },
      {
        h: '15. Events outside our control',
        p: ['Renta UG is not responsible for delays or failures caused by events outside its reasonable control, such as power or internet failures, network or provider outages, government action, strikes, natural disasters or cyber attacks.'],
      },
      {
        h: '16. Law and disputes',
        p: [
          'These terms are governed by the laws of the Republic of Uganda.',
          'If you have a complaint, contact us first so we can try to solve it. If it is not solved within 30 days, either side may refer it to mediation in Kampala, and failing that to the courts of Uganda, which have exclusive jurisdiction.',
        ],
      },
      {
        h: '17. General',
        p: [
          'These terms, with the Privacy policy, are the whole agreement between you and Renta UG about the service. If any part is found invalid, the rest still applies. If we do not enforce a right straight away, we have not given it up. You may not transfer your rights under these terms; we may transfer ours to a new owner of the service.',
          'We may update these terms. The date at the top shows the latest version and important changes are announced in the app. Continuing to use Renta UG after a change means you accept the updated terms.',
          `Questions about these terms? Contact us ${reach}.`,
        ],
      },
    ],
  },

  'delete-account': {
    title: 'Delete your account',
    intro: `You can ask us to delete your ${N} account and personal data at any time.`,
    sections: [
      { h: 'How to ask', p: [`Send a request ${reach} from the email address or phone number linked to your account. Say "Delete my account" and include your full name.`, 'We check it is really you, then delete the account, normally within 30 days.'] },
      { h: 'What is deleted', p: ['Your sign-in, name, email, phone number, notification settings and the link to your home.'] },
      { h: 'What may be kept', p: ['Rent and payment records a landlord needs for their accounts, or that the law requires us to keep, are kept for as long as needed (see the Privacy policy) and are no longer linked to your profile where possible.'] },
      { h: 'Tenants and landlords', p: ['If you rent a home, your landlord keeps their record of the rent you paid. If you are a landlord, deleting your account also deletes your properties and your tenants\' records in Renta UG; download any reports you need first.'] },
    ],
  },
}
