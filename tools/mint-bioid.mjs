#!/usr/bin/env node
/**
 * Prints a fresh `bioid` — the single-use document-link token that
 * `SignosoftSigner.open()` takes.
 *
 * This is the backend half of a Signosoft integration, in four calls: upload a
 * PDF, place the signature fields, send it for signature, mint the link. A real
 * host app does exactly this server-side and hands the token to its mobile app.
 *
 *   flutter run --dart-define=BIOID=$(node tools/mint-bioid.mjs)
 *
 * Credentials come from tools/.mint-bioid.env — see .mint-bioid.env.example.
 */

import { readFileSync, existsSync } from 'node:fs';
import { randomUUID } from 'node:crypto';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const PDF = resolve(here, '../examples/medicly/assets/mock-medical-report.pdf');

// Field geometry is in **percentages of the page**, top-left origin, pages from
// 1 — the same numbers the web app sends. PDF points here would land off-page,
// and the server renders an off-page field on a page of its own.
//
// Exactly **one** field, and it must be `simple`. One `bioid` authorises one
// signature, so a two-field document can never be finalised — the ceremony
// completes the first field and the host app never receives a terminal result.
// And `biometric` needs an external hardware signature pad that cannot be
// reached from this origin. One typed field is the only shape that completes
// end to end. Centred on the span the old `simple` + `biometric` pair covered
// (51-89, midpoint 70, so an 18-wide field starts at 61).
const FIELDS = [
  { authmethod: 'simple', x: 61, y: 60, width: 18, height: 6 },
];

// ---------------------------------------------------------------------------

const envFile = resolve(here, '.mint-bioid.env');
for (const line of existsSync(envFile) ? readFileSync(envFile, 'utf8').split('\n') : []) {
  const [, k, v] = line.match(/^\s*([A-Z_]+)\s*=\s*(.*)$/) ?? [];
  if (k && !(k in process.env)) process.env[k] = v.trim();
}

const { SIGNOSOFT_API: api, SIGNOSOFT_AUTH: auth, SIGNOSOFT_REALM: realm } = process.env;
const { SIGNOSOFT_CLIENT_ID: clientId, SIGNOSOFT_USER: user } = process.env;
const { SIGNOSOFT_PASSWORD: password } = process.env;

const die = (message) => {
  console.error(`mint-bioid: ${message}`);
  process.exit(1);
};

if (!api || !auth || !realm || !clientId || !user || !password) {
  die(`fill in ${envFile} — see .mint-bioid.env.example`);
}
if (!existsSync(PDF)) die(`PDF not found: ${PDF}`);

/** Every Signosoft REST endpoint here is form-encoded and answers JSON. */
async function post(url, body, bearer) {
  const res = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
      ...(bearer && { Authorization: `Bearer ${bearer}` }),
    },
    body: new URLSearchParams(
      Object.entries(body).map(([k, v]) => [k, typeof v === 'object' ? JSON.stringify(v) : v]),
    ),
    signal: AbortSignal.timeout(120_000),
  }).catch((e) => die(`${url} -> ${e.name === 'TimeoutError' ? 'timed out' : e.message}`));

  const text = await res.text();
  // A 5xx here is the server being unwell, not your credentials.
  if (!res.ok) die(`${url} -> HTTP ${res.status}\n${text.slice(0, 400)}`);
  return JSON.parse(text);
}

const step = (message) => console.error(message); // stdout stays token-only

// --- 0. authenticate -------------------------------------------------------

const { access_token: bearer } = await post(
  `${auth}/realms/${realm}/protocol/openid-connect/token`,
  { grant_type: 'password', client_id: clientId, username: user, password },
);
if (!bearer) die(`no access_token from ${auth}`);
step('auth  ok');

// --- 1. upload the document ------------------------------------------------

const upload = await post(
  `${api}/REST/uploadDocument`,
  {
    docData: readFileSync(PDF).toString('base64'),
    docOwner: user,
    documentName: `mint-bioid ${new Date().toISOString()}`,
    docExtension: 'pdf',
  },
  bearer,
);
// The document is nested: {uploadResult, document: {docid, doctoken}}.
const { docid: docId, doctoken: docToken } = upload.document ?? {};
if (!docToken) die(`uploadDocument returned no doctoken:\n${JSON.stringify(upload).slice(0, 300)}`);
step(`upload ok  docId=${docId}`);

// --- 2. place the signature fields -----------------------------------------

await post(
  `${api}/REST/saveSignatures`,
  {
    docId,
    name: `mint-bioid ${docId}`,
    acroFields: '[]',
    signatures: {
      signatures: FIELDS.map((f, i) => ({
        sigid: i + 1,
        signame: `Signature_${i + 1}`,
        // `order` indexes THIS signature's own auth-method list, not the field.
        // Each field here declares exactly one method, so it is always 0.
        // (Passing the field index instead was wrong but harmless — a document
        // minted with order: 0 on both fields behaved identically.)
        sigauthmethods: [{ type: f.authmethod, order: 0 }],
        sigpage: 1,
        sigx: f.x, sigy: f.y, sigwidth: f.width, sigheight: f.height,
        sigsigner: user, sigsigneremail: user,
        sigsignerfirstname: 'Test', sigsignersecondname: 'Signer',
        sigsignerlang: 'en',
        siginperson: true, sigrequired: true, sigsigned: false,
        sigmethod: [], sigorder: -1, sigsignerphone: '',
        siglockfields: null, siggenerateqr: false,
      })),
    },
  },
  bearer,
);
step(`fields ok  ${FIELDS.length} placed`);

// --- 3. send it for signature ----------------------------------------------

await post(
  `${api}/REST/createSignRequest`,
  {
    notificationChannel: 'EMAIL',
    docid: [docId],
    idempotencyKey: randomUUID(),
    isCreditBilling: true,
  },
  bearer,
);
step('sign request ok');

// --- 4. mint the document link --------------------------------------------

const link = await post(
  `${api}/REST/createDocLink`,
  { doctoken: docToken, language: 'en', showPRFinalize: 'false', signerLogin: user },
  bearer,
);
const bioid = link.bioId ?? link.bioid;
if (!bioid) die(`createDocLink returned no bioid:\n${JSON.stringify(link).slice(0, 400)}`);

step(`docToken ${docToken}`);
console.log(bioid);
