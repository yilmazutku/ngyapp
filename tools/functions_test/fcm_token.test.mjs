// functions/index.js'teki releaseFcmTokenFromOtherUsers'ı emülatörde dener:
// bir cihazın jetonu bir hesabın kaydına yazılınca aynı jeton diğer
// hesapların kaydından silinir. `npm test` emülatörü açar ve bunu çalıştırır.
import admin from 'firebase-admin';

const PROJECT = 'demo-ngy';

admin.initializeApp({projectId: PROJECT});
const db = admin.firestore();

let failures = 0;
function check(name, ok, detail = '') {
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ` | ${detail}` : ''}`);
  if (!ok) failures++;
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const userRef = (uid) => db.collection('users').doc(uid);

/** [predicate] doğru olana kadar kaydı okur; olmazsa son hâli döner. */
async function waitUser(uid, predicate, timeoutMs = 20000) {
  const end = Date.now() + timeoutMs;
  let snap;
  do {
    snap = await userRef(uid).get();
    if (predicate(snap)) return snap;
    await sleep(300);
  } while (Date.now() < end);
  return snap;
}

const tokenOf = (snap) => (snap.exists ? snap.get('fcmToken') : undefined);

// Kayıtları admin açar; jeton sonradan update ile yazılır (bkz.
// FcmService._saveTokenIfChanged).
await userRef('u1').set({name: 'A', kvkkConsentVersion: 1});
await userRef('u2').set({name: 'B'});
await userRef('u3').set({name: 'C', fcmToken: 'baska-cihaz'});

await userRef('u1').update({fcmToken: 'cihaz-1'});
await sleep(3000);
let snap = await userRef('u1').get();
check('T1 jetonu başka kimsede yoksa kendi kaydına dokunulmaz',
    tokenOf(snap) === 'cihaz-1', JSON.stringify(snap.data()));

// İlk tetikleyici emülatörde geç yüklenebilir: bekleme uzun tutulur.
await userRef('u2').update({fcmToken: 'cihaz-1'});
snap = await waitUser('u1', (s) => tokenOf(s) === undefined, 60000);
check('T2 aynı cihazda giren hesap jetonu önceki hesabın kaydından alır',
    tokenOf(snap) === undefined, JSON.stringify(snap.data()));
check('T3 önceki hesabın diğer alanları kalır',
    snap.get('name') === 'A' && snap.get('kvkkConsentVersion') === 1,
    JSON.stringify(snap.data()));
check('T4 yeni hesabın jetonu kalır',
    tokenOf(await userRef('u2').get()) === 'cihaz-1');
check('T5 başka cihazın jetonuna dokunulmaz',
    tokenOf(await userRef('u3').get()) === 'baska-cihaz');

await userRef('u2').update({name: 'B2'});
await sleep(3000);
check('T6 jeton değişmeden yazılan kayıt bir şey silmez',
    tokenOf(await userRef('u2').get()) === 'cihaz-1');

// Aynı jeton birden çok eski kayıtta kalmışsa (ör. eski sürümlerden) hepsi
// temizlenir.
await userRef('u4').set({name: 'D', fcmToken: 'cihaz-2'});
await userRef('u5').set({name: 'E', fcmToken: 'cihaz-2'});
await sleep(3000);
await userRef('u1').update({fcmToken: 'cihaz-2'});
const [s4, s5] = await Promise.all([
  waitUser('u4', (s) => tokenOf(s) === undefined),
  waitUser('u5', (s) => tokenOf(s) === undefined),
]);
check('T7 jetonu taşıyan bütün eski kayıtlardan silinir',
    tokenOf(s4) === undefined && tokenOf(s5) === undefined,
    `${JSON.stringify(s4.data())} ${JSON.stringify(s5.data())}`);
check('T8 son yazanın jetonu kalır',
    tokenOf(await userRef('u1').get()) === 'cihaz-2');

await userRef('u1').update({fcmToken: admin.firestore.FieldValue.delete()});
await sleep(3000);
check('T9 jeton silinince başka kayda dokunulmaz',
    tokenOf(await userRef('u2').get()) === 'cihaz-1' &&
    tokenOf(await userRef('u3').get()) === 'baska-cihaz');

if (failures > 0) {
  console.error(`\n${failures} beklenti karşılanmadı`);
  process.exit(1);
}
console.log('\nTüm beklentiler karşılandı');
