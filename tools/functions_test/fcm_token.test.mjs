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

// Birden çok cihazlı hesap (Nilay): her cihazın jetonu fcmTokens listesinde,
// fcmToken en son girileni tutar (bkz. FcmService.tokenSaveUpdate).
const listOf = (snap) => (snap.exists ? snap.get('fcmTokens') : undefined);
const sameList = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const FV = admin.firestore.FieldValue;

await userRef('n').set({
  name: 'Nilay', fcmToken: 'n-tablet', fcmTokens: ['n-tel', 'n-tablet'],
});
await userRef('u6').set({name: 'F', fcmToken: 'eski-cihaz'});
await userRef('u7').set({name: 'G'});
await sleep(3000);

await userRef('u7').update({fcmToken: 'n-tel'});
snap = await waitUser('n', (s) => sameList(listOf(s), ['n-tablet']));
check('T10 Nilay\'ın cihazına giren hesap jetonu Nilay\'ın listesinden alır',
    sameList(listOf(snap), ['n-tablet']), JSON.stringify(snap.data()));
check('T11 Nilay\'ın diğer cihazı ve son cihaz alanı kalır',
    tokenOf(snap) === 'n-tablet', JSON.stringify(snap.data()));
check('T12 yeni hesabın jetonu kalır',
    tokenOf(await userRef('u7').get()) === 'n-tel');

await userRef('u7').update({fcmToken: 'n-tablet'});
snap = await waitUser('n',
    (s) => tokenOf(s) === undefined && sameList(listOf(s), []));
check('T13 Nilay\'ın son girdiği cihaz iki alandan da çıkar',
    tokenOf(snap) === undefined && sameList(listOf(snap), []),
    JSON.stringify(snap.data()));

await userRef('n').update({
  fcmToken: 'eski-cihaz', fcmTokens: FV.arrayUnion('eski-cihaz'),
});
snap = await waitUser('u6', (s) => tokenOf(s) === undefined);
check('T14 Nilay\'ın listesine eklenen cihaz önceki hesabın kaydından çıkar',
    tokenOf(snap) === undefined, JSON.stringify(snap.data()));
snap = await userRef('n').get();
check('T15 Nilay\'ın kaydı yeni cihazı tutar',
    tokenOf(snap) === 'eski-cihaz' && sameList(listOf(snap), ['eski-cihaz']),
    JSON.stringify(snap.data()));

await userRef('n').update({fcmTokens: FV.arrayRemove('eski-cihaz')});
await sleep(3000);
check('T16 Nilay\'ın listesinden cihaz çıkınca başka kayda dokunulmaz',
    tokenOf(await userRef('u7').get()) === 'n-tablet' &&
    tokenOf(await userRef('u3').get()) === 'baska-cihaz');

if (failures > 0) {
  console.error(`\n${failures} beklenti karşılanmadı`);
  process.exit(1);
}
console.log('\nTüm beklentiler karşılandı');
