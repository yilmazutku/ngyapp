// functions/index.js'teki busySlots aynasını emülatörde dener:
// mirrorBusySlot (randevu yazıldıkça ayna) ve backfillBusySlots (admin'in
// eski randevularla doldurması). `npm test` emülatörü açar ve bunu çalıştırır.
import {createHash} from 'node:crypto';
import admin from 'firebase-admin';

const PROJECT = 'demo-ngy';
const ADMIN_UID = 'SdPI69ChOvepuq9HrlW6no9rMRn1';
const FUNCTIONS_URL = `http://127.0.0.1:5001/${PROJECT}/us-central1`;

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();
const {Timestamp} = admin.firestore;

let failures = 0;
function check(name, ok, detail = '') {
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ` | ${detail}` : ''}`);
  if (!ok) failures++;
}

const slotId = (uid, id) =>
  createHash('sha256').update(`${uid}/${id}`).digest('hex');
const appointmentRef = (uid, id) =>
  db.collection('users').doc(uid).collection('appointments').doc(id);
const slotRef = (uid, id) => db.collection('busySlots').doc(slotId(uid, id));

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/** [predicate] doğru olana kadar aynayı okur; olmazsa son hâli döner. */
async function waitSlot(uid, id, predicate, timeoutMs = 20000) {
  const end = Date.now() + timeoutMs;
  let snap;
  do {
    snap = await slotRef(uid, id).get();
    if (predicate(snap)) return snap;
    await sleep(300);
  } while (Date.now() < end);
  return snap;
}

const at = (iso) => Timestamp.fromDate(new Date(iso));
const T1 = at('2030-01-10T09:00:00Z');
const T2 = at('2030-01-10T11:30:00Z');

/** İmzasız ID token: Functions emülatörü callable'larda doğrulamadan çözer. */
function fakeIdToken(uid) {
  const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');
  const now = Math.floor(Date.now() / 1000);
  return `${b64({alg: 'none', typ: 'JWT'})}.${b64({
    iss: `https://securetoken.google.com/${PROJECT}`,
    aud: PROJECT,
    auth_time: now,
    user_id: uid,
    sub: uid,
    uid,
    iat: now,
    exp: now + 3600,
  })}.`;
}

async function callBackfill(uid) {
  const headers = {'Content-Type': 'application/json'};
  if (uid) headers.Authorization = `Bearer ${fakeIdToken(uid)}`;
  const res = await fetch(`${FUNCTIONS_URL}/backfillBusySlots`, {
    method: 'POST',
    headers,
    body: JSON.stringify({data: {}}),
  });
  return {status: res.status, body: await res.json().catch(() => null)};
}

// Tetikleyicinin yüklendiğinden emin olmak için ilk yazım biraz bekler.
async function waitForFunctions() {
  const end = Date.now() + 60000;
  while (Date.now() < end) {
    try {
      const res = await fetch(`${FUNCTIONS_URL}/backfillBusySlots`, {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({data: {}}),
      });
      if (res.status !== 404) return;
    } catch (e) {
      // Emülatör henüz hazır değil.
    }
    await sleep(500);
  }
  throw new Error('Functions emülatörü yanıt vermedi');
}

await waitForFunctions();

// --- mirrorBusySlot ---------------------------------------------------------
await appointmentRef('c1', 'a1').set({
  appointmentId: 'a1',
  userId: 'c1',
  subscriptionId: 'sub1',
  appointmentDateTime: T1,
  durationMinutes: 45,
  status: 'Planlandı',
  notes: 'özel not',
  isDeleted: null,
  createUser: 'user',
});
let snap = await waitSlot('c1', 'a1', (s) => s.exists);
check('M1 yeni randevunun aynası oluşur', snap.exists);
if (snap.exists) {
  const data = snap.data();
  check('M2 aynada yalnızca saat ve süre var',
      JSON.stringify(Object.keys(data).sort()) ===
      JSON.stringify(['appointmentDateTime', 'durationMinutes']),
      JSON.stringify(Object.keys(data)));
  check('M3 saat ve süre randevununki',
      data.appointmentDateTime.isEqual(T1) && data.durationMinutes === 45);
}
check('M4 ayna kimliği UID değil, özet (eski c1_a1 biçimi yok)',
    /^[0-9a-f]{64}$/.test(snap.id) &&
    !(await db.collection('busySlots').doc('c1_a1').get()).exists);

await appointmentRef('c1', 'a1').update({appointmentDateTime: T2,
  durationMinutes: 60});
snap = await waitSlot('c1', 'a1', (s) => s.exists &&
    s.data().appointmentDateTime.isEqual(T2));
check('M5 saat ve süre değişince ayna güncellenir', snap.exists &&
    snap.data().appointmentDateTime.isEqual(T2) &&
    snap.data().durationMinutes === 60);

const beforeNote = (await slotRef('c1', 'a1').get()).updateTime;
await appointmentRef('c1', 'a1').update({notes: 'yeni not', status: 'Tamamlandı'});
await sleep(3000);
const afterNote = (await slotRef('c1', 'a1').get()).updateTime;
check('M6 not/durum değişikliği aynaya dokunmaz',
    beforeNote && afterNote && beforeNote.isEqual(afterNote));

await appointmentRef('c1', 'a2').set({userId: 'c1', status: 'Planlandı'});
await sleep(3000);
check('M7 saati olmayan randevunun aynası olmaz',
    !(await slotRef('c1', 'a2').get()).exists);

await appointmentRef('c1', 'a1').delete();
snap = await waitSlot('c1', 'a1', (s) => !s.exists);
check('M8 randevu silinince ayna silinir', !snap.exists);

await appointmentRef('c2', 'b1').set({userId: 'c2', appointmentDateTime: T1});
snap = await waitSlot('c2', 'b1', (s) => s.exists);
check('M9 süresi olmayan randevunun aynasında süre alanı yok',
    snap.exists && !('durationMinutes' in snap.data()));

// --- backfillBusySlots ------------------------------------------------------
// Ayna kurulmadan önceki durumu taklit eder: eksik, yanlış ve sahipsiz ayna.
await appointmentRef('c3', 'x1').set({userId: 'c3', appointmentDateTime: T1,
  durationMinutes: 30});
await appointmentRef('c3', 'x2').set({userId: 'c3', appointmentDateTime: T2,
  durationMinutes: 30});
await waitSlot('c3', 'x1', (s) => s.exists);
await waitSlot('c3', 'x2', (s) => s.exists);
await slotRef('c3', 'x1').delete();
await slotRef('c3', 'x2').set({appointmentDateTime: T2, durationMinutes: 999});
await db.collection('busySlots').doc('sahipsiz').set({appointmentDateTime: T1,
  durationMinutes: 30});

let res = await callBackfill(null);
check('B1 girişsiz çağrı reddedilir', res.status !== 200,
    `${res.status} ${JSON.stringify(res.body)}`);
res = await callBackfill('c3');
check('B2 danışanın çağrısı reddedilir', res.status !== 200 &&
    JSON.stringify(res.body).includes('PERMISSION_DENIED'),
    `${res.status} ${JSON.stringify(res.body)}`);

res = await callBackfill(ADMIN_UID);
check('B3 admin çağırabilir', res.status === 200,
    `${res.status} ${JSON.stringify(res.body)}`);
const result = res.body && res.body.result;
check('B4 eksik ve yanlış ayna eşitlenir, sahipsiz silinir (sayılar)',
    result && result.written === 2 && result.deleted === 1,
    JSON.stringify(result));
snap = await slotRef('c3', 'x1').get();
check('B5 eksik ayna yazıldı', snap.exists &&
    snap.data().appointmentDateTime.isEqual(T1) &&
    snap.data().durationMinutes === 30);
snap = await slotRef('c3', 'x2').get();
check('B6 yanlış ayna düzeltildi', snap.exists &&
    snap.data().durationMinutes === 30);
check('B7 sahipsiz ayna silindi',
    !(await db.collection('busySlots').doc('sahipsiz').get()).exists);

res = await callBackfill(ADMIN_UID);
check('B8 tekrar çalıştırınca bir şey değişmez',
    res.status === 200 && res.body.result.written === 0 &&
    res.body.result.deleted === 0, JSON.stringify(res.body));

const all = await db.collection('busySlots').get();
check('B9 her saatli randevunun tek aynası var (c2/b1, c3/x1, c3/x2)',
    all.size === 3, `size=${all.size}`);

if (failures > 0) {
  console.error(`\n${failures} beklenti karşılanmadı`);
  process.exit(1);
}
console.log('\nTüm beklentiler karşılandı');
