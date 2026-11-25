// Phone numbers from every country. Pure helpers (no Vue, no browser), shared by the app and the server.
//
// Numbers are saved in international form: "+" + country code + number, e.g. +256772123456 or +254712345678.
// Older Ugandan numbers saved as 0772 123 456 still work: they are read as Uganda.
// Two numbers are the same person's when their canonical digits (phoneKey) are the same.

// name | ISO code | calling code. The first entry of a shared code is the one picked when a number is read back
// (+1 → United States, +44 → United Kingdom, +7 → Russia, …). NANP islands carry their area code (+1876 = Jamaica).
const RAW = `
Uganda|UG|256
Kenya|KE|254
Tanzania|TZ|255
Rwanda|RW|250
Burundi|BI|257
South Sudan|SS|211
Democratic Republic of the Congo|CD|243
Afghanistan|AF|93
Åland Islands|AX|358
Albania|AL|355
Algeria|DZ|213
American Samoa|AS|1684
Andorra|AD|376
Angola|AO|244
Anguilla|AI|1264
Antigua and Barbuda|AG|1268
Argentina|AR|54
Armenia|AM|374
Aruba|AW|297
Australia|AU|61
Austria|AT|43
Azerbaijan|AZ|994
Bahamas|BS|1242
Bahrain|BH|973
Bangladesh|BD|880
Barbados|BB|1246
Belarus|BY|375
Belgium|BE|32
Belize|BZ|501
Benin|BJ|229
Bermuda|BM|1441
Bhutan|BT|975
Bolivia|BO|591
Bonaire, Sint Eustatius and Saba|BQ|599
Bosnia and Herzegovina|BA|387
Botswana|BW|267
Brazil|BR|55
British Virgin Islands|VG|1284
Brunei|BN|673
Bulgaria|BG|359
Burkina Faso|BF|226
Cambodia|KH|855
Cameroon|CM|237
Canada|CA|1
Cape Verde|CV|238
Cayman Islands|KY|1345
Central African Republic|CF|236
Chad|TD|235
Chile|CL|56
China|CN|86
Christmas Island|CX|61
Cocos (Keeling) Islands|CC|61
Colombia|CO|57
Comoros|KM|269
Congo (Republic)|CG|242
Cook Islands|CK|682
Costa Rica|CR|506
Côte d'Ivoire|CI|225
Croatia|HR|385
Cuba|CU|53
Curaçao|CW|599
Cyprus|CY|357
Czechia|CZ|420
Denmark|DK|45
Djibouti|DJ|253
Dominica|DM|1767
Dominican Republic|DO|1809
Ecuador|EC|593
Egypt|EG|20
El Salvador|SV|503
Equatorial Guinea|GQ|240
Eritrea|ER|291
Estonia|EE|372
Eswatini|SZ|268
Ethiopia|ET|251
Falkland Islands|FK|500
Faroe Islands|FO|298
Fiji|FJ|679
Finland|FI|358
France|FR|33
French Guiana|GF|594
French Polynesia|PF|689
Gabon|GA|241
Gambia|GM|220
Georgia|GE|995
Germany|DE|49
Ghana|GH|233
Gibraltar|GI|350
Greece|GR|30
Greenland|GL|299
Grenada|GD|1473
Guadeloupe|GP|590
Guam|GU|1671
Guatemala|GT|502
Guernsey|GG|44
Guinea|GN|224
Guinea-Bissau|GW|245
Guyana|GY|592
Haiti|HT|509
Honduras|HN|504
Hong Kong|HK|852
Hungary|HU|36
Iceland|IS|354
India|IN|91
Indonesia|ID|62
Iran|IR|98
Iraq|IQ|964
Ireland|IE|353
Isle of Man|IM|44
Israel|IL|972
Italy|IT|39
Jamaica|JM|1876
Japan|JP|81
Jersey|JE|44
Jordan|JO|962
Kazakhstan|KZ|7
Kiribati|KI|686
Kosovo|XK|383
Kuwait|KW|965
Kyrgyzstan|KG|996
Laos|LA|856
Latvia|LV|371
Lebanon|LB|961
Lesotho|LS|266
Liberia|LR|231
Libya|LY|218
Liechtenstein|LI|423
Lithuania|LT|370
Luxembourg|LU|352
Macao|MO|853
Madagascar|MG|261
Malawi|MW|265
Malaysia|MY|60
Maldives|MV|960
Mali|ML|223
Malta|MT|356
Marshall Islands|MH|692
Martinique|MQ|596
Mauritania|MR|222
Mauritius|MU|230
Mayotte|YT|262
Mexico|MX|52
Micronesia|FM|691
Moldova|MD|373
Monaco|MC|377
Mongolia|MN|976
Montenegro|ME|382
Montserrat|MS|1664
Morocco|MA|212
Mozambique|MZ|258
Myanmar|MM|95
Namibia|NA|264
Nauru|NR|674
Nepal|NP|977
Netherlands|NL|31
New Caledonia|NC|687
New Zealand|NZ|64
Nicaragua|NI|505
Niger|NE|227
Nigeria|NG|234
Niue|NU|683
North Korea|KP|850
North Macedonia|MK|389
Northern Mariana Islands|MP|1670
Norway|NO|47
Oman|OM|968
Pakistan|PK|92
Palau|PW|680
Palestine|PS|970
Panama|PA|507
Papua New Guinea|PG|675
Paraguay|PY|595
Peru|PE|51
Philippines|PH|63
Poland|PL|48
Portugal|PT|351
Puerto Rico|PR|1787
Qatar|QA|974
Réunion|RE|262
Romania|RO|40
Russia|RU|7
Saint Barthélemy|BL|590
Saint Helena|SH|290
Saint Kitts and Nevis|KN|1869
Saint Lucia|LC|1758
Saint Martin|MF|590
Saint Pierre and Miquelon|PM|508
Saint Vincent and the Grenadines|VC|1784
Samoa|WS|685
San Marino|SM|378
São Tomé and Príncipe|ST|239
Saudi Arabia|SA|966
Senegal|SN|221
Serbia|RS|381
Seychelles|SC|248
Sierra Leone|SL|232
Singapore|SG|65
Sint Maarten|SX|1721
Slovakia|SK|421
Slovenia|SI|386
Solomon Islands|SB|677
Somalia|SO|252
South Africa|ZA|27
South Korea|KR|82
Spain|ES|34
Sri Lanka|LK|94
Sudan|SD|249
Suriname|SR|597
Svalbard and Jan Mayen|SJ|47
Sweden|SE|46
Switzerland|CH|41
Syria|SY|963
Taiwan|TW|886
Tajikistan|TJ|992
Thailand|TH|66
Timor-Leste|TL|670
Togo|TG|228
Tokelau|TK|690
Tonga|TO|676
Trinidad and Tobago|TT|1868
Tunisia|TN|216
Turkey|TR|90
Turkmenistan|TM|993
Turks and Caicos Islands|TC|1649
Tuvalu|TV|688
Ukraine|UA|380
United Arab Emirates|AE|971
United Kingdom|GB|44
United States|US|1
Uruguay|UY|598
US Virgin Islands|VI|1340
Uzbekistan|UZ|998
Vanuatu|VU|678
Vatican City|VA|379
Venezuela|VE|58
Vietnam|VN|84
Wallis and Futuna|WF|681
Western Sahara|EH|212
Yemen|YE|967
Zambia|ZM|260
Zimbabwe|ZW|263
`

// Flag emoji from the two-letter code (shows as the letters where the device has no flag emoji)
const flagOf = (iso) => String.fromCodePoint(...[...iso].map((c) => 0x1f1e6 + c.charCodeAt(0) - 65))

export const COUNTRIES = RAW.trim()
  .split('\n')
  .map((line) => {
    const [name, iso, dial] = line.split('|')
    return { name, iso, dial, flag: flagOf(iso) }
  })
// Several countries share a code: this is the one a number is read back as
const PRIMARY = { 1: 'US', 7: 'RU', 44: 'GB', 61: 'AU', 47: 'NO', 262: 'RE', 358: 'FI', 590: 'GP', 599: 'CW' }
export const countryByIso =(iso) => COUNTRIES.find((c) => c.iso === iso) ?? COUNTRIES[0]

const digitsOf = (v) => String(v ?? '').replace(/\D/g, '')

// A number is valid when it has a country code and 9–15 digits in all (the international limit is 15).
const MIN_DIGITS = 9
const MAX_DIGITS = 15
export function isValidPhone(value) {
  const raw = String(value ?? '').trim()
  const d = digitsOf(raw)
  if (raw.startsWith('+')) return d.length >= MIN_DIGITS && d.length <= MAX_DIGITS && d[0] !== '0'
  return /^(?:256|0)?7\d{8}$/.test(d) // an older Ugandan number: 0772 123 456
}

// → "+<digits>" in international form, or '' when it isn't a usable number
export function toE164(value) {
  const raw = String(value ?? '').trim()
  if (!raw) return ''
  let d = digitsOf(raw)
  if (raw.startsWith('+')) return isValidPhone(raw) ? `+${d}` : ''
  if (d.startsWith('00')) {
    d = d.slice(2)
    return d.length >= MIN_DIGITS && d.length <= MAX_DIGITS ? `+${d}` : ''
  }
  if (/^7\d{8}$/.test(d)) return `+256${d}`
  if (/^07\d{8}$/.test(d)) return `+256${d.slice(1)}`
  if (/^2567\d{8}$/.test(d)) return `+${d}`
  return ''
}

// The same number always gives the same key: +256 772 123 456, 0772123456 and 256772123456 → 256772123456
export function phoneKey(value) {
  const e = toE164(value)
  if (e) return e.slice(1)
  const d = digitsOf(value)
  return d.length >= MIN_DIGITS ? d : ''
}
export const samePhone = (a, b) => {
  const x = phoneKey(a)
  return Boolean(x) && x === phoneKey(b)
}

// Digits for a WhatsApp link (wa.me / AppLink): international, no "+"
export const whatsappDigits = (value) => phoneKey(value)

// "+256 772 123456" style display; unknown formats are returned as typed
export function prettyPhone(value) {
  const e = toE164(value)
  if (!e) return String(value ?? '')
  const { dial, local } = splitPhone(e)
  return `+${dial} ${local.replace(/(\d{3})(?=\d)/g, '$1 ').trim()}`
}

// "+254712345678" → { iso: 'KE', dial: '254', local: '712345678' } (the longest matching country code wins)
export function splitPhone(value, fallbackIso = 'UG') {
  const e = toE164(value)
  if (!e) return { iso: fallbackIso, dial: countryByIso(fallbackIso).dial, local: digitsOf(value).replace(/^0+/, '') }
  const d = e.slice(1)
  let best = null
  for (const c of COUNTRIES) {
    if (!d.startsWith(c.dial)) continue
    if (!best || c.dial.length > best.dial.length || (c.dial.length === best.dial.length && PRIMARY[c.dial] === c.iso)) best = c
  }
  best ??= countryByIso(fallbackIso)
  return { iso: best.iso, dial: best.dial, local: d.slice(best.dial.length) }
}

// A country code + what was typed → "+<code><number>" ('' when nothing was typed). A leading 0 is dropped.
export function composePhone(dial, typed) {
  const local = digitsOf(typed).replace(/^0+/, '')
  return local ? `+${dial}${local}` : ''
}
