// firestore.rules dosyasını Firestore emülatöründe uygulamanın gerçek
// yazımlarıyla dener: sohbet özeti + mesaj toplu yazımı (ilk mesaj dahil),
// yanıt ve öğün fotoğrafı alanları, ifade, "fotoğraf silindi", okundu işareti
// ve yetkisiz erişim denemeleri; danışanın kendi kullanıcı dokümanına ve alt
// koleksiyonlarına yaptığı yazımlar, yetki yükseltme denemeleri, randevu
// gizliliği ve busySlots aynası. Kural değiştikten sonra çalıştırılır:
//   cd tools/firestore_rules_test && npm install && npm test
// Emülatör açıkken birden çok kural dosyası yan yana karşılaştırılabilir:
//   node rules.test.mjs eski.rules ../../firestore.rules
// Emülatör için Java gerekir.
import fs from 'node:fs';
import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';

const ADMIN = '0MvvbZsjbmNPW4QYShRNSOOtkE43';
const ADMIN2 = 'SdPI69ChOvepuq9HrlW6no9rMRn1';
const FV = firebase.firestore.FieldValue;
const TS = firebase.firestore.Timestamp;

function summary(chatId, extra = {}) {
  return {
    participants: [chatId, ADMIN, ADMIN2],
    lastMessage: 'x', lastImageUrl: '', lastImageThumbUrl: '',
    lastMessageAt: TS.now(), updatedAt: FV.serverTimestamp(),
    adminUnreadCount: { [ADMIN]: FV.increment(1), [ADMIN2]: FV.increment(1) },
    hasUnreadFor: FV.arrayUnion(ADMIN, ADMIN2), ...extra,
  };
}
function textMsg(chatId, sender, extra = {}) {
  return { chatId, senderId: sender, text: 'merhaba', createdAt: FV.serverTimestamp(), clientCreatedAt: TS.now(), ...extra };
}
function photoMsg(chatId, sender) {
  return textMsg(chatId, sender, {
    text: 'Öğün: Öğle', imageUrl: 'https://x/a.jpg', thumbUrl: 'https://x/a_thumb.jpg',
    imageWidth: 1600, imageHeight: 1200, storagePath: `meals/${chatId}/lunch`,
  });
}

async function run(rulesFile) {
  const env = await initializeTestEnvironment({
    projectId: 'demo-ngy-' + rulesFile.replace(/\W/g, ''),
    firestore: { rules: fs.readFileSync(rulesFile, 'utf8'), host: '127.0.0.1', port: 8089 },
  });
  const results = [];
  const check = async (name, expectAllowed, fn) => {
    let allowed;
    try { await fn(); allowed = true; } catch (e) { allowed = false; if (!String(e).includes('PERMISSION_DENIED') && !String(e.code).includes('permission')) { allowed = 'ERR:' + e; } }
    results.push({ name, expectAllowed, allowed, ok: allowed === expectAllowed });
  };
  const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();
  const seed = async (fn) => env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));

  // A: brand-new chat, no chat doc.
  await check('A1 new customer reads own (missing) chat doc', true, () => db('c1').collection('chats').doc('c1').get());
  await check('A2 new customer lists own messages', true, () => db('c1').collection('chats').doc('c1').collection('messages').orderBy('createdAt', 'desc').limit(30).get());
  await check('A3 first text message (batch summary+message, replyTo)', true, async () => {
    const d = db('c1'); const b = d.batch(); const chat = d.collection('chats').doc('c1');
    b.set(chat, summary('c1'), { merge: true });
    b.set(chat.collection('messages').doc(), textMsg('c1', 'c1', { replyTo: { messageId: 'm0', senderId: ADMIN, text: 'soru' } }));
    await b.commit();
  });
  await check('A4 first meal photo in new chat (batch with image fields)', true, async () => {
    const d = db('c9'); const b = d.batch(); const chat = d.collection('chats').doc('c9');
    b.set(chat, summary('c9', { lastImageUrl: 'https://x/a.jpg', lastImageThumbUrl: 'https://x/a_thumb.jpg' }), { merge: true });
    b.set(chat.collection('messages').doc(), photoMsg('c9', 'c9'));
    await b.commit();
  });

  // B: chat doc exists without participants (read marker created it).
  await check('B1 read marker creates own chat doc', true, () => db('c2').collection('chats').doc('c2').set({ userUnreadCount: 0, userLastReadAt: FV.serverTimestamp(), hasUnreadFor: FV.arrayRemove('c2') }, { merge: true }));
  await seed((f) => f.collection('chats').doc('c3').set({ userUnreadCount: 0 }));
  await check('B2 read chat doc without participants', true, () => db('c3').collection('chats').doc('c3').get());
  await check('B3 send message into chat doc without participants', true, async () => {
    const d = db('c3'); const b = d.batch(); const chat = d.collection('chats').doc('c3');
    b.set(chat, summary('c3'), { merge: true });
    b.set(chat.collection('messages').doc(), textMsg('c3', 'c3'));
    await b.commit();
  });

  // C: normal existing chat created by admin.
  await seed(async (f) => {
    await f.collection('chats').doc('c4').set({ participants: ['c4', ADMIN, ADMIN2], lastMessage: 'hi' });
    await f.collection('chats').doc('c4').collection('messages').doc('adm').set({ chatId: 'c4', senderId: ADMIN, text: 'hi' });
    await f.collection('chats').doc('c4').collection('messages').doc('own').set({ chatId: 'c4', senderId: 'c4', text: 'Öğün: Öğle', imageUrl: 'https://x/o.jpg', thumbUrl: 'https://x/o_t.jpg', imageWidth: 10, imageHeight: 10, storagePath: 'meals/c4/lunch', reactions: { [ADMIN]: '👍' } });
  });
  await check('C1 customer sends reply + photo in existing chat', true, async () => {
    const d = db('c4'); const b = d.batch(); const chat = d.collection('chats').doc('c4');
    b.set(chat, summary('c4', { lastImageThumbUrl: 'https://x/t.jpg' }), { merge: true });
    b.set(chat.collection('messages').doc(), photoMsg('c4', 'c4'));
    b.set(chat.collection('messages').doc(), textMsg('c4', 'c4', { replyTo: { messageId: 'adm', senderId: ADMIN, text: 'hi', imageUrl: 'https://x/t.jpg' } }));
    await b.commit();
  });
  await check('C2 reaction on admin message', true, () => db('c4').collection('chats').doc('c4').collection('messages').doc('adm').update({ ['reactions.c4']: '❤️' }));
  await check('C2b remove own reaction', true, () => db('c4').collection('chats').doc('c4').collection('messages').doc('adm').update({ ['reactions.c4']: FV.delete() }));
  await check('C2c edit admin message text', false, () => db('c4').collection('chats').doc('c4').collection('messages').doc('adm').update({ text: 'hacked' }));
  await check('C2d remove admin reaction', false, () => db('c4').collection('chats').doc('c4').collection('messages').doc('own').update({ [`reactions.${ADMIN}`]: FV.delete() }));
  await check('C3 read marker update', true, () => db('c4').collection('chats').doc('c4').set({ userUnreadCount: 0, userLastReadAt: FV.serverTimestamp(), hasUnreadFor: FV.arrayRemove('c4') }, { merge: true }));
  await check('C4 read single message', true, () => db('c4').collection('chats').doc('c4').collection('messages').doc('adm').get());
  await check('C4b query messages by imageUrl', true, () => db('c4').collection('chats').doc('c4').collection('messages').where('imageUrl', '==', 'https://x/o.jpg').get());
  await check('C5 own meal photo -> "fotoğraf silindi"', true, () => db('c4').collection('chats').doc('c4').collection('messages').doc('own').update({ imageUrl: FV.delete(), thumbUrl: FV.delete(), imageWidth: FV.delete(), imageHeight: FV.delete(), storagePath: FV.delete(), text: 'Öğün: Öğle (fotoğraf silindi)', photoDeleted: true }));
  await check('C5b chat summary after photo delete', true, () => db('c4').collection('chats').doc('c4').update({ lastImageUrl: '', lastImageThumbUrl: '', lastMessage: 'Öğün: Öğle (fotoğraf silindi)' }));
  await check('C5c "delete" admin message photo', false, () => db('c4').collection('chats').doc('c4').collection('messages').doc('adm').update({ text: 'x', photoDeleted: true }));
  await seed((f) => f.collection('chats').doc('c4').collection('messages').doc('own2').set({ chatId: 'c4', senderId: 'c4', text: 'Öğün: Öğle', imageUrl: 'https://x/o2.jpg' }));
  await check('C5d swap own photo url while "deleting"', false, () => db('c4').collection('chats').doc('c4').collection('messages').doc('own2').update({ imageUrl: 'https://evil/x.jpg', photoDeleted: true }));
  await check('C5e edit own message text only', false, () => db('c4').collection('chats').doc('c4').collection('messages').doc('own2').update({ text: 'changed' }));
  await check('C6 customer deletes own message', false, () => db('c4').collection('chats').doc('c4').collection('messages').doc('own2').delete());
  await check('C7 customer deletes own chat', false, () => db('c4').collection('chats').doc('c4').delete());

  // D: other customers / spoofing.
  await check('D1 other customer reads chat doc', false, () => db('c5').collection('chats').doc('c4').get());
  await check('D1b other customer lists messages', false, () => db('c5').collection('chats').doc('c4').collection('messages').get());
  await check('D1c other customer reads missing chat', false, () => db('c5').collection('chats').doc('c7').get());
  await check('D2 other customer creates someone\'s chat doc', false, () => db('c5').collection('chats').doc('c8').set({ participants: ['c8', 'c5'] }));
  await check('D2b other customer writes message into chat', false, () => db('c5').collection('chats').doc('c4').collection('messages').add(textMsg('c4', 'c5')));
  await check('D3 customer writes message as admin', false, () => db('c4').collection('chats').doc('c4').collection('messages').add(textMsg('c4', ADMIN)));
  await check('D3b other customer updates chat summary', false, () => db('c5').collection('chats').doc('c4').update({ lastMessage: 'x' }));
  await check('D4 unauthenticated reads chat', false, () => db(null).collection('chats').doc('c4').get());

  // E: admin.
  await check('E1 admin list query', true, () => db(ADMIN).collection('chats').where('participants', 'array-contains', ADMIN).orderBy('lastMessageAt', 'desc').limit(200).get());
  await check('E2 admin sends into new chat', true, async () => {
    const d = db(ADMIN); const b = d.batch(); const chat = d.collection('chats').doc('c6');
    b.set(chat, summary('c6'), { merge: true });
    b.set(chat.collection('messages').doc(), textMsg('c6', ADMIN));
    await b.commit();
  });
  await check('E3 admin deletes chat message', true, () => db(ADMIN).collection('chats').doc('c4').collection('messages').doc('own2').delete());

  // F / G: unchanged areas.
  await check('F1 owner writes meal entry', true, () => db('c4').collection('users').doc('c4').collection('meals').doc('2026-09-28').collection('mealEntries').doc('lunch').set({ imageUrls: ['a'], thumbUrls: ['b'] }));
  await check('F2 other user reads meal entry', false, () => db('c5').collection('users').doc('c4').collection('meals').doc('2026-09-28').get());
  await seed((f) => f.collection('admininput').doc('appVersion').set({ v: 1 }));
  await check('G1 signed-out reads appVersion', true, () => db(null).collection('admininput').doc('appVersion').get());

  // H: yetki yükseltme denemeleri (kullanıcı dokümanı ve admin'in alt koleksiyonları).
  const slotStart = TS.fromDate(new Date('2026-10-22T10:00:00'));
  await seed(async (f) => {
    const u = f.collection('users').doc('u1');
    await u.set({ role: 'customer', name: 'Ayşe', email: 'a@x.com', fcmToken: 'old', mealNotificationsEnabled: true });
    await u.collection('payments').doc('p1').set({ status: 'Planlandı', amount: 1000 });
    await u.collection('subscriptions').doc('s1').set({ status: 'Aktif', meetingsCompleted: 2, meetingsBurned: 0 });
    await u.collection('dietLists').doc('d1').set({ title: 'Diyet' });
    await u.collection('measurements').doc('tanita').collection('pdfFiles').doc('t1').set({ fileName: 'x.pdf', uploadTime: TS.now() });
    await u.collection('appointments').doc('a1').set({ userId: 'u1', subscriptionId: 's1', notes: 'gizli not', appointmentDateTime: slotStart, durationMinutes: 45, status: 'Planlandı', isDeleted: null });
    await f.collection('busySlots').doc('u1_a1').set({ appointmentDateTime: slotStart, durationMinutes: 45 });
  });
  const u1 = () => db('u1').collection('users').doc('u1');
  await check('H1 customer updates own role', false, () => u1().update({ role: 'admin' }));
  await check('H1b customer edits admin-managed field', false, () => u1().set({ fcmToken: 'tok', email: 'b@x.com' }, { merge: true }));
  await check('H2 customer set-merges own role', false, () => u1().set({ fcmToken: 'tok', role: 'admin' }, { merge: true }));
  await check('H3 customer deletes own user doc', false, () => u1().delete());
  await check('H4 customer marks own payment paid', false, () => u1().collection('payments').doc('p1').update({ status: 'Ödendi' }));
  await check('H5 customer gives back a package meeting', false, () => u1().collection('subscriptions').doc('s1').update({ meetingsCompleted: FV.increment(-1) }));
  await check('H6 customer writes own diet list', false, () => u1().collection('dietLists').doc('d2').set({ title: 'x' }));
  await check('H7 customer writes own measurement', false, () => u1().collection('measurements').doc('m1').set({ weight: 50 }));
  await check('H8 customer creates own user doc', false, () => db('u9').collection('users').doc('u9').set({ fcmToken: 'tok' }, { merge: true }));
  await check('H9 customer edits own appointment', false, () => u1().collection('appointments').doc('a1').update({ status: 'Yapıldı' }));
  await check('H9b customer deletes own appointment', false, () => u1().collection('appointments').doc('a1').delete());
  await check('H10 customer writes dailyData extra field', false, () => u1().collection('dailyData').doc('2026-10-21').set({ role: 'admin' }, { merge: true }));

  // I: uygulamanın danışan adına gerçekten yaptığı yazımlar.
  await check('I1 FCM token set-merge', true, () => u1().set({ fcmToken: 'tok' }, { merge: true }));
  await check('I1c FCM token update (FcmService._saveTokenIfChanged)', true, () => u1().update({ fcmToken: 'tok2' }));
  await check('I2 FCM token removed in transaction (logout)', true, () => { const d = db('u1'); return d.runTransaction(async (tx) => {
    const ref = d.collection('users').doc('u1'); const snap = await tx.get(ref);
    if (snap.get('fcmToken') === 'tok') tx.update(ref, { fcmToken: FV.delete() });
  }); });
  await check('I3 FCM token removed by set-merge (offline)', true, () => u1().set({ fcmToken: FV.delete() }, { merge: true }));
  await check('I4 KVKK consent', true, () => u1().update({ kvkkVersion: '1.0', kvkkAcceptedAt: TS.now(), explicitConsentAcceptedAt: TS.now() }));
  await check('I5 Profilim save (age + preferences)', true, () => u1().set({ age: 34, mealNotificationsEnabled: true, announcementNotificationsEnabled: false }, { merge: true }));
  await check('I6 meal reminder toggle', true, () => u1().set({ mealNotificationsEnabled: false }, { merge: true }));
  await check('I7 account deletion request', true, () => u1().set({ isUserRequestedRemoval: true }, { merge: true }));
  await check('I7b withdraw deletion request', false, () => u1().set({ isUserRequestedRemoval: false }, { merge: true }));
  const day = () => u1().collection('meals').doc('2026-10-21');
  await check('I8 meal day state + reminder cancel (new day)', true, () => day().set({ meals: { lunch: true }, reminderCancelled: { lunch: true } }, { merge: true }));
  await check('I8b meal day uncheck', true, () => day().set({ meals: { lunch: false } }, { merge: true }));
  await check('I9 meal entry upload', true, () => day().collection('mealEntries').doc('lunch').set({ mealType: 'lunch', imageUrls: ['https://x/a.jpg'], thumbUrls: [''], imageTimes: [TS.now()], subscriptionId: 's1', timestamp: TS.now(), isChecked: true, createDate: TS.now() }));
  await check('I9b meal entry thumbnail backfill (transaction)', true, () => { const d = db('u1'); return d.runTransaction(async (tx) => {
    const ref = d.collection('users').doc('u1').collection('meals').doc('2026-10-21').collection('mealEntries').doc('lunch'); await tx.get(ref);
    tx.update(ref, { thumbUrls: ['https://x/a_t.jpg'] });
  }); });
  await check('I9c meal entry delete', true, () => day().collection('mealEntries').doc('lunch').delete());
  await check('I10 water intake (new day)', true, () => u1().collection('dailyData').doc('2026-10-21').set({ waterIntake: 1.5 }, { merge: true }));
  await check('I10b steps', true, () => u1().collection('dailyData').doc('2026-10-21').set({ steps: 4000 }, { merge: true }));
  const booking = (extra = {}) => ({
    userId: 'u1', subscriptionId: 's1', meetingType: 'Yüz yüze', appointmentType: 'Kontrol',
    appointmentDateTime: TS.fromDate(new Date('2026-10-23T11:00:00')), durationMinutes: 30, status: 'Planlandı',
    notes: null, createDate: TS.now(), updateDate: null, createUser: 'user', updateUser: null,
    postponedDate: null, postponedBy: null, isDeleted: null, ...extra,
  });
  await check('I11 book appointment (Randevularım)', true, () => u1().collection('appointments').doc('a2').set(booking()));
  await check('I11b book as "Yapıldı"', false, () => u1().collection('appointments').doc('a3').set(booking({ status: 'Yapıldı' })));
  await check('I11c book for another user', false, () => u1().collection('appointments').doc('a4').set(booking({ userId: 'u2' })));
  await check('I11d book into another user\'s appointments', false, () => db('u1').collection('users').doc('u2').collection('appointments').doc('a5').set(booking({ userId: 'u2' })));
  await check('I12 reads own user doc', true, () => u1().get());
  await check('I12b lists own subscriptions', true, () => u1().collection('subscriptions').get());
  await check('I12c planned payments query (home badge)', true, () => u1().collection('payments').where('status', '==', 'Planlandı').get());
  await check('I12d own appointments query', true, () => u1().collection('appointments').where('isDeleted', '==', null).orderBy('appointmentDateTime').get());
  await check('I12d2 own appointments of a day (slot picker)', true, () => u1().collection('appointments').where('appointmentDateTime', '>=', slotStart).where('appointmentDateTime', '<', TS.fromDate(new Date('2026-10-23T00:00:00'))).get());
  await check('I12e own diet lists and Tanita PDFs', true, async () => {
    await u1().collection('dietLists').get();
    await u1().collection('measurements').doc('tanita').collection('pdfFiles').orderBy('uploadTime', 'desc').get();
  });

  // J: başka danışanın randevusu (not, paket, kimlik) okunamaz.
  await check('J1 other customer reads appointment (notes)', false, () => db('u2').collection('users').doc('u1').collection('appointments').doc('a1').get());
  await check('J1b other customer lists appointments', false, () => db('u2').collection('users').doc('u1').collection('appointments').get());
  await check('J2 customer collection-group appointments (old slot picker)', false, () => db('u2').collectionGroup('appointments').where('appointmentDateTime', '>=', slotStart).get());

  // K: saat seçicinin aynası.
  await check('K1 customer reads busySlots for a day', true, () => db('u2').collection('busySlots').where('appointmentDateTime', '>=', TS.fromDate(new Date('2026-10-22T00:00:00'))).where('appointmentDateTime', '<', TS.fromDate(new Date('2026-10-23T00:00:00'))).get());
  await check('K2 customer creates busySlot', false, () => db('u2').collection('busySlots').doc('u2_x').set({ appointmentDateTime: slotStart, durationMinutes: 600 }));
  await check('K2b customer deletes busySlot', false, () => db('u2').collection('busySlots').doc('u1_a1').delete());
  await check('K3 signed-out reads busySlots', false, () => db(null).collection('busySlots').get());

  // L: admin her yere erişmeye devam eder.
  await check('L1 admin changes role', true, () => db(ADMIN).collection('users').doc('u1').update({ role: 'customer' }));
  await check('L1b admin creates user doc', true, () => db(ADMIN).collection('users').doc('u7').set({ role: 'customer', name: 'Yeni' }));
  await check('L2 admin collection-group appointments', true, () => db(ADMIN).collectionGroup('appointments').where('isDeleted', '==', null).where('appointmentDateTime', '>=', slotStart).get());
  await check('L3 admin updates payment and counters', true, async () => {
    await db(ADMIN2).collection('users').doc('u1').collection('payments').doc('p1').update({ status: 'Ödendi' });
    await db(ADMIN2).collection('users').doc('u1').collection('subscriptions').doc('s1').update({ meetingsCompleted: FV.increment(1) });
  });

  await env.cleanup();
  return results;
}

const files = process.argv.slice(2);
const all = {};
for (const f of files) all[f] = await run(f);
const names = all[files[0]].map((r) => r.name);
let failed = 0;
for (let i = 0; i < names.length; i++) {
  const cols = files.map((f) => { const r = all[f][i]; return `${f}: ${r.allowed === true ? 'ALLOW' : r.allowed === false ? 'deny ' : r.allowed}${r.ok ? '' : ' (!)'}`; });
  const last = all[files[files.length - 1]][i];
  if (!last.ok) failed++;
  console.log(`${last.ok ? 'OK ' : 'BAD'} ${names[i].padEnd(52)} expect=${last.expectAllowed ? 'ALLOW' : 'deny '} | ${cols.join(' | ')}`);
}
console.log(failed ? `\n${failed} unexpected result(s) with ${files[files.length - 1]}` : `\nAll expectations met with ${files[files.length - 1]}`);
process.exit(failed ? 1 : 0);
