import fs from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import firebase from 'firebase/compat/app';
import 'firebase/compat/firestore';

const ADMIN = '0MvvbZsjbmNPW4QYShRNSOOtkE43';
const ADMIN2 = 'SdPI69ChOvepuq9HrlW6no9rMRn1';
const ADMINS = [ADMIN, ADMIN2];
const FV = firebase.firestore.FieldValue;
const TS = firebase.firestore.Timestamp;
const GUN = '2026-10-13';
const IMAGE_FIELD_NAMES = ['imageUrl', 'thumbUrl', 'imageWidth', 'imageHeight'];
const MEAL_LABELS = { br: 'Sabah', firstmid: 'Ara', lunch: 'Öğle', secondmid: 'Ara', dinner: 'Akşam', thirdmid: 'Ara', none: 'Diğer' };
const GOZLEM = 'gözlem';

const chatCaption = (meal) => `Öğün: ${MEAL_LABELS[meal]}`;
const chatSummaryText = (meal) => `Öğün Fotoğrafı (${MEAL_LABELS[meal]})`;
const deletedPhotoChatText = (text) => (text && text.trim() ? `${text.trim()} (fotoğraf silindi)` : 'Fotoğraf silindi');
const storageUrl = (path, token) =>
  `https://firebasestorage.googleapis.com/v0/b/demo-ngy.appspot.com/o/${encodeURIComponent(path)}?alt=media&token=${token}`;
const mealPhoto = (uid, meal, n) => {
  const base = `users/${uid}/mealPhotos/${GUN}/${meal}/17000000000${n}_IMG_${n}`;
  return { url: storageUrl(`${base}.jpg`, `t${n}`), thumbUrl: storageUrl(`${base}_thumb.jpg`, `tt${n}`), width: 1600, height: 1200 };
};

function chatSummaryData(chatId, { lastMessage, lastImageUrl, lastImageThumbUrl, lastAt, incrementUnreadForAdmins = false, incrementUnreadForUser = false }) {
  const unreadFor = [...(incrementUnreadForAdmins ? ADMINS : []), ...(incrementUnreadForUser ? [chatId] : [])];
  return {
    participants: [chatId, ...ADMINS],
    ...(lastMessage != null ? { lastMessage } : {}),
    ...(lastImageUrl != null ? { lastImageUrl } : {}),
    ...(lastImageThumbUrl != null ? { lastImageThumbUrl } : {}),
    ...(lastAt != null ? { lastMessageAt: lastAt } : {}),
    updatedAt: FV.serverTimestamp(),
    ...(incrementUnreadForAdmins ? { adminUnreadCount: Object.fromEntries(ADMINS.map((a) => [a, FV.increment(1)])) } : {}),
    ...(incrementUnreadForUser ? { userUnreadCount: FV.increment(1) } : {}),
    ...(unreadFor.length ? { hasUnreadFor: FV.arrayUnion(...unreadFor) } : {}),
  };
}

async function sendTextTo(db, senderUid, chatId, text, replyTo) {
  const isAdminMessage = ADMINS.includes(senderUid);
  const chat = db.collection('chats').doc(chatId);
  const batch = db.batch();
  batch.set(chat, chatSummaryData(chatId, {
    lastMessage: text, lastImageUrl: '', lastImageThumbUrl: '', lastAt: TS.now(),
    incrementUnreadForAdmins: !isAdminMessage, incrementUnreadForUser: isAdminMessage,
  }), { merge: true });
  batch.set(chat.collection('messages').doc(), {
    chatId, senderId: senderUid, text,
    ...(replyTo ? { replyTo } : {}),
    createdAt: FV.serverTimestamp(), clientCreatedAt: TS.now(),
  });
  await batch.commit();
}

async function postMealPhotoToChat(db, uid, meal, image) {
  const chat = db.collection('chats').doc(uid);
  const batch = db.batch();
  batch.set(chat, {
    participants: [uid, ...ADMINS],
    lastMessage: chatSummaryText(meal),
    lastImageUrl: image.url,
    lastImageThumbUrl: image.thumbUrl ?? '',
    lastMessageAt: TS.now(),
    updatedAt: FV.serverTimestamp(),
    adminUnreadCount: Object.fromEntries(ADMINS.map((a) => [a, FV.increment(1)])),
    hasUnreadFor: FV.arrayUnion(...ADMINS),
  }, { merge: true });
  batch.set(chat.collection('messages').doc(), {
    chatId: uid, senderId: uid, text: chatCaption(meal),
    imageUrl: image.url, thumbUrl: image.thumbUrl, imageWidth: image.width, imageHeight: image.height,
    storagePath: `meals/${uid}/${meal}`,
    createdAt: FV.serverTimestamp(), clientCreatedAt: TS.now(),
  });
  await batch.commit();
}

const markChatAsReadForUser = (db, uid) =>
  db.collection('chats').doc(uid).set({ userUnreadCount: 0, userLastReadAt: FV.serverTimestamp(), hasUnreadFor: FV.arrayRemove(uid) }, { merge: true });

const setReaction = (db, uid, chatId, messageId, emoji) =>
  db.collection('chats').doc(chatId).collection('messages').doc(messageId).update({ [`reactions.${uid}`]: emoji });
const removeReaction = (db, uid, chatId, messageId) =>
  db.collection('chats').doc(chatId).collection('messages').doc(messageId).update({ [`reactions.${uid}`]: FV.delete() });

function mealModelMap(meal, photos, subscriptionId = 'sub1') {
  const times = photos.map((_, i) => TS.fromDate(new Date(`${GUN}T19:0${i}:00Z`)));
  return {
    mealType: meal,
    imageUrls: photos.map((p) => p.url),
    thumbUrls: photos.map((p) => p.thumbUrl ?? ''),
    imageTimes: times,
    imageUrl: photos.length ? photos[0].url : '',
    subscriptionId,
    description: null,
    timestamp: times[times.length - 1],
    calories: null,
    notes: null,
    isChecked: true,
    createDate: TS.now(),
  };
}

const mealEntryRef = (db, uid, meal) => db.collection('users').doc(uid).collection('meals').doc(GUN).collection('mealEntries').doc(meal);
const dayRef = (db, uid) => db.collection('users').doc(uid).collection('meals').doc(GUN);
const updateMealState = (db, uid, meal, isChecked) => dayRef(db, uid).set({ meals: { [meal]: isChecked } }, { merge: true });

function expectEq(actual, expected, label) {
  const a = JSON.stringify(actual);
  const e = JSON.stringify(expected);
  if (a !== e) throw new Error(`BEKLENMEYEN ${label}: beklenen ${e}, gelen ${a}`);
}

async function run(rulesFile) {
  const env = await initializeTestEnvironment({
    projectId: 'demo-ngy-senaryo-' + rulesFile.replace(/\W/g, ''),
    firestore: { rules: fs.readFileSync(rulesFile, 'utf8'), host: '127.0.0.1', port: 8089 },
  });
  await env.clearFirestore();
  const results = [];
  const check = async (step, name, expect, fn) => {
    let outcome;
    let detail = '';
    try { await fn(); outcome = 'ALLOW'; } catch (e) {
      const text = `${e.code ?? ''} ${e.message ?? e}`;
      if (/PERMISSION_DENIED|permission-denied/i.test(text)) outcome = 'DENY';
      else { outcome = 'ERR'; detail = text.replace(/\s+/g, ' ').slice(0, 220); }
    }
    const ok = expect === GOZLEM ? outcome !== 'ERR' : outcome === expect;
    results.push({ step, name, expect, outcome, ok, detail });
  };
  const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();
  const seed = async (fn) => env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));

  const D = 'danisanSil';
  const YABANCI = 'baskaDanisan';
  const aksam = mealPhoto(D, 'dinner', 1);
  const ara = [2, 3, 4, 5].map((n) => mealPhoto(D, 'secondmid', n));
  await seed(async (f) => {
    const chat = f.collection('chats').doc(D);
    await chat.set({
      participants: [D, ...ADMINS], lastMessage: chatSummaryText('dinner'), lastImageUrl: aksam.url, lastImageThumbUrl: aksam.thumbUrl,
      lastMessageAt: TS.now(), adminUnreadCount: { [ADMIN]: 1, [ADMIN2]: 1 }, hasUnreadFor: ADMINS,
    });
    await chat.collection('messages').doc('admMesaj').set({ chatId: D, senderId: ADMIN, text: 'Afiyet olsun', createdAt: TS.now() });
    for (const [i, p] of ara.entries()) {
      await chat.collection('messages').doc(`ara${i + 1}`).set({
        chatId: D, senderId: D, text: chatCaption('secondmid'), imageUrl: p.url, thumbUrl: p.thumbUrl, imageWidth: p.width, imageHeight: p.height,
        storagePath: `meals/${D}/secondmid`, createdAt: TS.now(), ...(i === 1 ? { reactions: { [ADMIN]: '👍' } } : {}),
      });
    }
    await chat.collection('messages').doc('aksamFoto').set({
      chatId: D, senderId: D, text: chatCaption('dinner'), imageUrl: aksam.url, thumbUrl: aksam.thumbUrl, imageWidth: aksam.width, imageHeight: aksam.height,
      storagePath: `meals/${D}/dinner`, createdAt: TS.now(),
    });
    await mealEntryRef(f, D, 'dinner').set(mealModelMap('dinner', [aksam]));
    await mealEntryRef(f, D, 'secondmid').set(mealModelMap('secondmid', ara));
    await dayRef(f, D).set({ meals: { dinner: true, secondmid: true } });
    await f.collection('users').doc(YABANCI).set({ role: 'customer', name: 'Yabancı' });
  });

  const d = db(D);
  const chatOf = (ctx, id) => ctx.collection('chats').doc(id);

  await check('7.1', 'Danışan silmeden önce kendi öğün kaydını okur (deleteMealImage: mealDocRef.get)', 'ALLOW', () => mealEntryRef(d, D, 'dinner').get());
  await check('7.1', 'Danışan öğünün son fotoğrafını silince öğün kaydını siler (mealDocRef.delete)', 'ALLOW', () => mealEntryRef(d, D, 'dinner').delete());
  await check('7.1', 'Danışan öğünü "yüklenmedi" yapar (updateMealState false, set merge)', 'ALLOW', () => updateMealState(d, D, 'dinner', false));
  await check('7.1', 'Danışan sohbette fotoğrafın mesajını adresinden bulur (where imageUrl ==)', 'ALLOW', async () => {
    const q = await chatOf(d, D).collection('messages').where('imageUrl', '==', aksam.url).get();
    expectEq(q.docs.map((x) => x.id), ['aksamFoto'], 'bulunan mesajlar');
  });
  await check('7.1', 'Danışan kendi fotoğraf mesajını "fotoğraf silindi" notuna çevirir (toplu update)', 'ALLOW', async () => {
    const b = d.batch();
    b.update(chatOf(d, D).collection('messages').doc('aksamFoto'), {
      ...Object.fromEntries(IMAGE_FIELD_NAMES.map((f) => [f, FV.delete()])), storagePath: FV.delete(),
      text: deletedPhotoChatText(chatCaption('dinner')), photoDeleted: true,
    });
    await b.commit();
  });
  await check('7.3', 'Danışan sohbet özetini okur ve son görselin silinen fotoğraf olduğunu görür', 'ALLOW', async () => {
    const s = await chatOf(d, D).get();
    expectEq(s.data().lastImageUrl, aksam.url, 'lastImageUrl');
  });
  await check('7.3', 'Danışan sohbet özetini günceller (lastImageUrl/lastImageThumbUrl boş, lastMessage not metni)', 'ALLOW', () =>
    chatOf(d, D).update({ lastImageUrl: '', lastImageThumbUrl: '', lastMessage: deletedPhotoChatText(chatCaption('dinner')) }));
  await check('7.3', 'Admin listede önizlemeyi "Öğün: Akşam (fotoğraf silindi)" ve küçük görselsiz okur', 'ALLOW', async () => {
    const s = (await chatOf(db(ADMIN), D).get()).data();
    expectEq([s.lastMessage, s.lastImageUrl, s.lastImageThumbUrl], ['Öğün: Akşam (fotoğraf silindi)', '', ''], 'özet');
  });
  await check('7.2', 'Admin notu okur: photoDeleted true, görsel alanları ve storagePath yok', 'ALLOW', async () => {
    const m = (await chatOf(db(ADMIN), D).collection('messages').doc('aksamFoto').get()).data();
    expectEq({ text: m.text, photoDeleted: m.photoDeleted, kalanGorselAlanlari: [...IMAGE_FIELD_NAMES, 'storagePath'].filter((f) => f in m) },
      { text: 'Öğün: Akşam (fotoğraf silindi)', photoDeleted: true, kalanGorselAlanlari: [] }, 'not');
  });

  await check('7.7', 'Albümün ortasındaki fotoğraf silinince kalan 3 fotoğrafla öğün kaydı yeniden yazılır (set)', 'ALLOW', () =>
    mealEntryRef(d, D, 'secondmid').set(mealModelMap('secondmid', [ara[0], ara[2], ara[3]])));
  await check('7.7', 'İfadesi olan albüm fotoğrafı (admin 👍) adresinden bulunup notuna çevrilir (_markChatPhotoDeleted sorgusu + toplu update)', 'ALLOW', async () => {
    const q = await chatOf(d, D).collection('messages').where('imageUrl', '==', ara[1].url).get();
    expectEq(q.docs.map((x) => x.id), ['ara2'], 'bulunan mesajlar');
    const b = d.batch();
    q.docs.forEach((x) => b.update(x.ref, {
      ...Object.fromEntries(IMAGE_FIELD_NAMES.map((f) => [f, FV.delete()])), storagePath: FV.delete(),
      text: deletedPhotoChatText(x.data().text), photoDeleted: true,
    }));
    await b.commit();
  });
  await check('7.7', 'Albümde silinen fotoğrafın önceki ve sonraki komşusu (ara1, ara3) fotoğraflı mesaj olarak kalır', 'ALLOW', async () => {
    for (const [id, p] of [['ara1', ara[0]], ['ara3', ara[2]]]) {
      const m = (await chatOf(db(ADMIN), D).collection('messages').doc(id).get()).data();
      expectEq([m.imageUrl, 'photoDeleted' in m], [p.url, false], `komşu mesaj ${id}`);
    }
  });
  await check('7.7', 'Bulgu #2: notuna dönen mesajda eski ifade kalmamalı (reactions boş olmalı)', 'ALLOW', async () => {
    const n = (await chatOf(db(ADMIN), D).collection('messages').doc('ara2').get()).data();
    expectEq(n.reactions ?? {}, {}, 'silinen fotoğrafın notundaki reactions');
  });
  await seed((f) => chatOf(f, D).collection('messages').doc('ara4').update({ reactions: { [ADMIN]: '❤️' } }));
  await check('7.7', 'Bulgu #2 düzeltme yolu: danışan silerken admin ifadesini de aynı update ile kaldırabilir mi', GOZLEM, () =>
    chatOf(d, D).collection('messages').doc('ara4').update({
      ...Object.fromEntries(IMAGE_FIELD_NAMES.map((f) => [f, FV.delete()])), storagePath: FV.delete(),
      text: deletedPhotoChatText(chatCaption('secondmid')), photoDeleted: true, reactions: FV.delete(),
    }));

  const y = db(YABANCI);
  await check('7.1/7.11', 'Başka danışan bu danışanın öğün kaydını okuyamaz', 'DENY', () => mealEntryRef(y, D, 'secondmid').get());
  await check('7.1/7.11', 'Başka danışan bu danışanın öğün kaydını güncelleyemez (set)', 'DENY', () => mealEntryRef(y, D, 'secondmid').set(mealModelMap('secondmid', [ara[0]])));
  await check('7.1/7.11', 'Başka danışan bu danışanın öğün kaydını silemez', 'DENY', () => mealEntryRef(y, D, 'secondmid').delete());
  await check('7.1/7.11', 'Başka danışan bu danışanın gün kaydını (updateMealState) değiştiremez', 'DENY', () => updateMealState(y, D, 'secondmid', false));
  await check('7.1/7.11', 'Başka danışan bu danışanın mesajlarını imageUrl ile sorgulayamaz', 'DENY', () => chatOf(y, D).collection('messages').where('imageUrl', '==', ara[0].url).get());
  await check('7.1/7.11', 'Başka danışan bu danışanın fotoğraf mesajını nota çeviremez', 'DENY', () =>
    chatOf(y, D).collection('messages').doc('ara1').update({ ...Object.fromEntries(IMAGE_FIELD_NAMES.map((f) => [f, FV.delete()])), storagePath: FV.delete(), text: 'x', photoDeleted: true }));
  await check('7.3/7.11', 'Başka danışan bu danışanın sohbet özetini güncelleyemez', 'DENY', () => chatOf(y, D).update({ lastImageUrl: '', lastImageThumbUrl: '', lastMessage: 'x' }));
  await check('7.11', 'Danışan admin mesajını "fotoğraf silindi" notuna çeviremez', 'DENY', () =>
    chatOf(d, D).collection('messages').doc('admMesaj').update({ text: deletedPhotoChatText('Afiyet olsun'), photoDeleted: true }));

  await check('Bulgu #1', 'Admin, "fotoğraf silindi" notuna dönmüş mesaja ifade bırakamamalı (reactions.<admin>)', 'DENY', () => setReaction(db(ADMIN), ADMIN, D, 'aksamFoto', '😍'));
  await check('Bulgu #1', 'İkinci admin de silinmiş fotoğraf notuna ifade bırakamamalı', 'DENY', () => setReaction(db(ADMIN2), ADMIN2, D, 'aksamFoto', '👍'));
  await check('Bulgu #1', 'Admin silinmiş fotoğraf notundaki eski ifadesini kaldırabilir mi', GOZLEM, () => removeReaction(db(ADMIN), ADMIN, D, 'ara2'));

  const R = 'danisanIfade';
  await seed(async (f) => {
    const chat = f.collection('chats').doc(R);
    await chat.set({ participants: [R, ...ADMINS], lastMessage: 'x' });
    await chat.collection('messages').doc('adm').set({ chatId: R, senderId: ADMIN, text: 'Nasılsınız?' });
    await chat.collection('messages').doc('ownFoto').set({ chatId: R, senderId: R, text: chatCaption('lunch'), imageUrl: 'https://x/l.jpg', reactions: { [ADMIN]: '❤️' } });
    await chat.collection('messages').doc('ownText').set({ chatId: R, senderId: R, text: 'Merhaba' });
  });
  const r = db(R);
  await check('2.9', 'Danışan admin mesajına kendi ifadesini bırakır (setReaction 👍)', 'ALLOW', () => setReaction(r, R, R, 'adm', '👍'));
  await check('2.10', 'Danışan ifadesini değiştirir (👍 → ❤️)', 'ALLOW', () => setReaction(r, R, R, 'adm', '❤️'));
  await check('2.10', 'Danışan aynı ifadeye tekrar basınca kaldırır (toggleReaction → removeReaction) ve harita boşalır', 'ALLOW', async () => {
    await removeReaction(r, R, R, 'adm');
    const m = (await chatOf(r, R).collection('messages').doc('adm').get()).data();
    expectEq(m.reactions ?? {}, {}, 'reactions');
  });
  await check('2.9', 'Danışan admin mesajına admin adına ifade yazamaz (reactions.<admin>)', 'DENY', () => setReaction(r, ADMIN, R, 'adm', '👍'));
  await check('2.9', 'Danışan admin mesajına başka bir kullanıcı adına ifade yazamaz (reactions.<başka uid>)', 'DENY', () => setReaction(r, 'baskaKullanici', R, 'adm', '👍'));
  await check('4.4', 'Danışan, admin\'in kendi fotoğrafına bıraktığı ifadeyi değiştiremez', 'DENY', () => setReaction(r, ADMIN, R, 'ownFoto', '😡'));
  await check('4.4', 'Danışan reactions haritasının tamamını kendi ifadesiyle değiştiremez (admin ifadesi düşerdi)', 'DENY', () =>
    chatOf(r, R).collection('messages').doc('ownFoto').update({ reactions: { [R]: '👍' } }));
  await check('2.9', 'Danışan ifadeyle birlikte mesaj metnini değiştiremez', 'DENY', () =>
    chatOf(r, R).collection('messages').doc('adm').update({ [`reactions.${R}`]: '👍', text: 'değişti' }));
  await check('2.11', 'Danışan kendi mesajına ifade bırakabilir mi (UI engelliyor; kural için şart değil)', GOZLEM, () => setReaction(r, R, R, 'ownText', '👍'));
  await check('2.9', 'Başka danışan bu sohbetteki admin mesajına ifade bırakamaz', 'DENY', () => setReaction(db(YABANCI), YABANCI, R, 'adm', '👍'));
  await check('2.9', 'Giriş yapmamış kullanıcı ifade bırakamaz', 'DENY', () => setReaction(db(null), 'anon', R, 'adm', '👍'));
  await check('4.1', 'Admin danışanın mesajına ifade bırakır (reactions.<admin>)', 'ALLOW', () => setReaction(db(ADMIN), ADMIN, R, 'ownText', '👍'));
  await check('4.4', 'Admin ifadesini değiştirir (👍 → 😍)', 'ALLOW', () => setReaction(db(ADMIN), ADMIN, R, 'ownText', '😍'));
  await check('4.5', 'Admin kendi mesajına ifade bırakabilir mi (UI engelliyor; admin kuralda sınırsız)', GOZLEM, () => setReaction(db(ADMIN), ADMIN, R, 'adm', '👍'));

  const K = 'danisanYeniden';
  const ilkFoto = mealPhoto(K, 'lunch', 6);
  await seed(async (f) => {
    const chat = f.collection('chats').doc(K);
    await chat.set({ participants: [K, ...ADMINS], lastMessage: 'eski', lastMessageAt: TS.now() });
    for (let i = 0; i < 3; i++) await chat.collection('messages').doc(`eski${i}`).set({ chatId: K, senderId: i % 2 ? ADMIN : K, text: `eski ${i}` });
  });
  await check('9.1', 'Admin sohbeti siler (mesajlar toplu silme + sohbet dokümanı)', 'ALLOW', async () => {
    const a = db(ADMIN);
    const msgs = await chatOf(a, K).collection('messages').get();
    const b = a.batch();
    msgs.docs.forEach((m) => b.delete(m.ref));
    await b.commit();
    await chatOf(a, K).delete();
  });
  await check('9.3', 'Sohbeti silinmiş danışan kendi (olmayan) sohbet dokümanını ve boş mesaj listesini okur', 'ALLOW', async () => {
    const s = await chatOf(db(K), K).get();
    const m = await chatOf(db(K), K).collection('messages').orderBy('createdAt', 'desc').limit(30).get();
    expectEq([s.exists, m.size], [false, 0], 'sohbet var mı / mesaj sayısı');
  });
  await check('9.4', 'Danışan sohbeti açınca okundu işareti participants\'sız sohbet dokümanı oluşturur', 'ALLOW', () => markChatAsReadForUser(db(K), K));
  await check('9.4', 'Sohbeti olmayan danışanın ilk metin mesajı (özet + mesaj toplu yazımı)', 'ALLOW', () => sendTextTo(db(K), K, K, 'Yeniden merhaba'));
  await check('9.4', 'Sohbeti olmayan danışanın ilk öğün fotoğrafı: öğün kaydı + gün kaydı + sohbet toplu yazımı', 'ALLOW', async () => {
    const k = db(K);
    await Promise.all([
      mealEntryRef(k, K, 'lunch').set(mealModelMap('lunch', [ilkFoto])),
      updateMealState(k, K, 'lunch', true),
      postMealPhotoToChat(k, K, 'lunch', ilkFoto),
    ]);
  });
  await check('9.4', 'Danışan admin listesinde yeniden çıkar (participants array-contains admin sorgusu)', 'ALLOW', async () => {
    const q = await db(ADMIN).collection('chats').where('participants', 'array-contains', ADMIN).orderBy('lastMessageAt', 'desc').limit(200).get();
    const doc = q.docs.find((x) => x.id === K);
    expectEq(doc ? [doc.data().lastMessage, doc.data().lastImageThumbUrl] : null, [chatSummaryText('lunch'), ilkFoto.thumbUrl], 'listede satır');
  });
  await check('9.4', 'Sohbeti olmayan danışan ilk mesajı admin adına yazamaz', 'DENY', () => sendTextTo(db('danisanYeni2'), ADMIN, 'danisanYeni2', 'sahte'));

  const U = 'danisanRol';
  await seed((f) => f.collection('users').doc(U).set({ role: 'customer', name: 'Rol Deneme', email: 'rol@example.com' }));
  await check('Ek', 'Danışan kendi users dokümanında rol dışındaki alanı günceller', 'ALLOW', () => db(U).collection('users').doc(U).update({ name: 'Yeni Ad' }));
  await check('Ek', 'Danışan kendi rolünü değiştirememeli (kural: role == resource.data.role)', 'DENY', () => db(U).collection('users').doc(U).update({ role: 'admin' }));
  await check('Ek', 'Danışan kendi users dokümanını silememeli (kuralda users/{uid} için delete izni yok)', 'DENY', () => db(U).collection('users').doc(U).delete());
  await seed((f) => f.collection('chats').doc(U).set({ participants: [U, ...ADMINS], lastMessage: 'x', lastMessageAt: TS.now() }));
  await check('Ek', 'Danışan kendi sohbet özetinden admin\'leri çıkarabilir mi (participants)', GOZLEM, () => chatOf(db(U), U).update({ participants: [U] }));
  await check('Ek', 'Danışan kendi sohbetinin participants alanına başka danışanı ekleyebilir mi', GOZLEM, () => chatOf(db(U), U).update({ participants: [U, ...ADMINS, YABANCI] }));
  await check('Ek', 'Participants\'a eklenen başka danışan o sohbetin mesajlarını okuyabilir mi', GOZLEM, () => chatOf(db(YABANCI), U).collection('messages').get());

  await env.cleanup();
  return results;
}

const files = process.argv.slice(2);
const results = await run(files[files.length - 1]);
let failed = 0;
for (const r of results) {
  if (!r.ok) failed++;
  const tag = r.ok ? (r.expect === GOZLEM ? 'GOZ' : 'OK ') : 'BAD';
  console.log(`${tag} [${r.step}] ${r.name} | beklenen=${r.expect} gözlenen=${r.outcome}${r.detail ? ` | ${r.detail}` : ''}`);
}
const byStep = {};
for (const r of results) {
  const s = (byStep[r.step] ??= { toplam: 0, ok: 0, bad: 0, gozlem: 0 });
  s.toplam++;
  if (!r.ok) s.bad++; else if (r.expect === GOZLEM) s.gozlem++; else s.ok++;
}
console.log('\nAdım özeti:');
for (const [step, s] of Object.entries(byStep)) console.log(`  ${step.padEnd(10)} toplam=${s.toplam} geçti=${s.ok} kaldı=${s.bad} gözlem=${s.gozlem}`);
console.log(failed ? `\n${failed} vaka beklenenden farklı (${files[files.length - 1]})` : `\nTüm beklentiler karşılandı (${files[files.length - 1]})`);
process.exit(failed ? 1 : 0);
