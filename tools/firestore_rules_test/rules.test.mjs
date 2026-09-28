// firestore.rules dosyasını Firestore emülatöründe uygulamanın gerçek
// yazımlarıyla dener: sohbet özeti + mesaj toplu yazımı (ilk mesaj dahil),
// yanıt ve öğün fotoğrafı alanları, ifade, "fotoğraf silindi", okundu işareti
// ve yetkisiz erişim denemeleri. Kural değiştikten sonra çalıştırılır:
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
