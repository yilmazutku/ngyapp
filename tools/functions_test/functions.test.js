'use strict';

const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {randomUUID} = require('node:crypto');
const {createRequire} = require('node:module');
const {describe, test, before, beforeEach, after} = require('node:test');

const PROJECT_ID = 'demo-ngy';
process.env.GCLOUD_PROJECT = process.env.GCLOUD_PROJECT || PROJECT_ID;
process.env.FIRESTORE_EMULATOR_HOST =
    process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8189';

const FUNCTIONS_DIR = path.resolve(__dirname, '..', '..', 'functions');
const INDEX_PATH = path.join(FUNCTIONS_DIR, 'index.js');

const requireLikeIndex = createRequire(INDEX_PATH);
const admin = requireLikeIndex('firebase-admin');
const {Change} = requireLikeIndex('firebase-functions/v2/firestore');

const sent = [];

function recordSend(method) {
  return async (message, ...rest) => {
    sent.push({method, message, rest});
    const tokens = Array.isArray(message && message.tokens) ? message.tokens : [null];
    return {
      successCount: tokens.length,
      failureCount: 0,
      responses: tokens.map(() => ({success: true, messageId: `sahte-${randomUUID()}`})),
    };
  };
}

const fakeMessaging = {
  sendEachForMulticast: recordSend('sendEachForMulticast'),
  sendMulticast: recordSend('sendMulticast'),
  sendEach: recordSend('sendEach'),
  sendAll: recordSend('sendAll'),
  send: recordSend('send'),
  sendToDevice: recordSend('sendToDevice'),
  sendToTopic: recordSend('sendToTopic'),
  sendToCondition: recordSend('sendToCondition'),
};

Object.defineProperty(admin, 'messaging', {
  configurable: true,
  value: () => fakeMessaging,
});

const functions = require(INDEX_PATH);

const indexSource = fs.readFileSync(INDEX_PATH, 'utf8');
const adminBlock = indexSource.match(/const ADMIN_UIDS = new Set\(\[([\s\S]*?)\]\)/);
const ADMIN_UIDS = adminBlock ? [...adminBlock[1].matchAll(/'([^']+)'/g)].map((m) => m[1]) : [];
const ADMIN_UID = ADMIN_UIDS[0];

const ADMIN_TO_USER_TITLE = 'Nilay Göktepe Yılmaz';
const CLIENT_UID = 'danisanTest01';
const CLIENT_NAME = 'Ayşe';
const CLIENT_SURNAME = 'Kaya';
const CLIENT_TOKEN = 'fcm-token-danisan';
const adminToken = (uid) => `fcm-token-admin-${uid}`;
const DATE_KEY = '2026-10-13';

const db = admin.firestore();

const userRef = (uid) => db.collection('users').doc(uid);
const chatRef = (uid) => db.collection('chats').doc(uid);
const messageRef = (uid, messageId) => chatRef(uid).collection('messages').doc(messageId);
const mealEntryRef = (uid, mealName) =>
  userRef(uid).collection('meals').doc(DATE_KEY).collection('mealEntries').doc(mealName);

function photoUrl(name) {
  return `https://firebasestorage.googleapis.com/v0/b/demo-ngy.appspot.com/o/users%2F${CLIENT_UID}%2FmealPhotos%2F${DATE_KEY}%2F${name}.jpg?alt=media`;
}

function thumbUrl(name) {
  return `https://firebasestorage.googleapis.com/v0/b/demo-ngy.appspot.com/o/users%2F${CLIENT_UID}%2FmealPhotos%2F${DATE_KEY}%2Fthumb_${name}.jpg?alt=media`;
}

async function clearFirestore() {
  const host = process.env.FIRESTORE_EMULATOR_HOST;
  const res = await fetch(
      `http://${host}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
      {method: 'DELETE'});
  assert.equal(res.ok, true, `emülatör temizlenemedi: ${res.status}`);
}

async function seedUsers() {
  await userRef(CLIENT_UID).set({
    name: CLIENT_NAME,
    surname: CLIENT_SURNAME,
    email: 'ayse.kaya@example.com',
    fcmToken: CLIENT_TOKEN,
  });
  for (const uid of ADMIN_UIDS) {
    await userRef(uid).set({name: 'Admin', fcmToken: adminToken(uid)});
  }
}

function clientPhotoMessage(name, text, extra = {}) {
  return {
    chatId: CLIENT_UID,
    senderId: CLIENT_UID,
    text,
    imageUrl: photoUrl(name),
    thumbUrl: thumbUrl(name),
    imageWidth: 1080,
    imageHeight: 1440,
    storagePath: `meals/${CLIENT_UID}/lunch`,
    createdAt: admin.firestore.Timestamp.now(),
    clientCreatedAt: admin.firestore.Timestamp.now(),
    ...extra,
  };
}

function textMessage(senderId, text, extra = {}) {
  return {
    chatId: CLIENT_UID,
    senderId,
    text,
    createdAt: admin.firestore.Timestamp.now(),
    clientCreatedAt: admin.firestore.Timestamp.now(),
    ...extra,
  };
}

function mealEntry(mealType, names) {
  const now = admin.firestore.Timestamp.now();
  return {
    mealId: mealType,
    mealType,
    imageUrls: names.map(photoUrl),
    thumbUrls: names.map(thumbUrl),
    imageTimes: names.map(() => now),
    subscriptionId: 'abonelik-1',
    timestamp: now,
    isChecked: true,
  };
}

function baseEvent(type, document, params, data) {
  return {
    specversion: '1.0',
    id: randomUUID(),
    source: `//firestore.googleapis.com/projects/${PROJECT_ID}/databases/(default)`,
    type,
    time: new Date().toISOString(),
    project: PROJECT_ID,
    database: '(default)',
    namespace: '(default)',
    location: 'eur3',
    document,
    params,
    data,
  };
}

async function captureChange(ref, write) {
  const beforeSnap = await ref.get();
  await write();
  const afterSnap = await ref.get();
  return Change.fromObjects(beforeSnap, afterSnap);
}

async function runMessageCreated(chatId, messageId) {
  const snap = await messageRef(chatId, messageId).get();
  const event = baseEvent(
      'google.cloud.firestore.document.v1.created',
      `chats/${chatId}/messages/${messageId}`,
      {chatId, messageId},
      snap);
  await functions.notifyUserOnAdminMessage.run(event);
  await functions.notifyAdminsOnUserMessage.run(event);
}

async function runMessageUpdated(chatId, messageId, change) {
  const event = baseEvent(
      'google.cloud.firestore.document.v1.updated',
      `chats/${chatId}/messages/${messageId}`,
      {chatId, messageId},
      change);
  await functions.notifyUserOnAdminReaction.run(event);
  await functions.notifyAdminsOnUserReaction.run(event);
}

async function reactAndRun(chatId, messageId, reactorUid, emoji) {
  const ref = messageRef(chatId, messageId);
  const value = emoji === null ? admin.firestore.FieldValue.delete() : emoji;
  const change = await captureChange(ref, () => ref.update({[`reactions.${reactorUid}`]: value}));
  await runMessageUpdated(chatId, messageId, change);
  return change;
}

async function runMealEntryWritten(uid, mealName, write) {
  const ref = mealEntryRef(uid, mealName);
  const change = await captureChange(ref, write);
  const event = baseEvent(
      'google.cloud.firestore.document.v1.written',
      `users/${uid}/meals/${DATE_KEY}/mealEntries/${mealName}`,
      {userId: uid, dateKey: DATE_KEY, mealName},
      change);
  await functions.markChatMessagesOfDeletedMealPhotos.run(event);
  return change;
}

function summarize() {
  return sent.map(({method, message}) => ({
    method,
    tokens: message.tokens || message.token || null,
    title: message.notification && message.notification.title,
    body: message.notification && message.notification.body,
    data: message.data,
  }));
}

function report(t, label) {
  t.diagnostic(`${label}: ${JSON.stringify(summarize())}`);
}

function onlyNotification() {
  assert.equal(sent.length, 1, `tam 1 bildirim beklendi, ${sent.length} yakalandı: ${JSON.stringify(summarize())}`);
  return sent[0];
}

before(() => {
  assert.ok(ADMIN_UIDS.length > 0, 'ADMIN_UIDS index.js içinden okunamadı');
});

beforeEach(async () => {
  await clearFirestore();
  await seedUsers();
  sent.length = 0;
});

after(async () => {
  await Promise.all(admin.apps.map((app) => app.delete()));
});

describe('notifyUserOnAdminReaction: admin danışanın mesajına ifade bırakınca danışana bildirim', () => {
  test('4.1/4.3 admin "Öğün: Öğle" fotoğrafına 👍 bırakınca danışana "Öğle öğün fotoğrafınıza 👍 bıraktı" gider, data içinde chatId ve messageId var', async (t) => {
    await messageRef(CLIENT_UID, 'm-ogle').set(clientPhotoMessage('ogle1', 'Öğün: Öğle'));
    await reactAndRun(CLIENT_UID, 'm-ogle', ADMIN_UID, '👍');
    report(t, 'yakalanan');
    const {method, message} = onlyNotification();
    assert.equal(method, 'sendEachForMulticast');
    assert.deepEqual(message.tokens, [CLIENT_TOKEN]);
    assert.equal(message.notification.title, ADMIN_TO_USER_TITLE);
    assert.equal(message.notification.body, 'Öğle öğün fotoğrafınıza 👍 bıraktı');
    assert.equal(message.data.chatId, CLIENT_UID);
    assert.equal(message.data.messageId, 'm-ogle');
  });

  test('4.2 eski etiketli "Öğün: Ara Öğün 2" fotoğrafına ❤️ bırakınca gövde numarasız "Ara öğün fotoğrafınıza ❤️ bıraktı" olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-ara2').set(clientPhotoMessage('ara2', 'Öğün: Ara Öğün 2'));
    await reactAndRun(CLIENT_UID, 'm-ara2', ADMIN_UID, '❤️');
    report(t, 'yakalanan');
    const {message} = onlyNotification();
    assert.equal(message.notification.body, 'Ara öğün fotoğrafınıza ❤️ bıraktı');
    assert.equal(message.data.messageId, 'm-ara2');
  });

  test('4.2 yeni etiketli "Öğün: Ara" fotoğrafına ❤️ bırakınca gövde "Ara öğün fotoğrafınıza ❤️ bıraktı" olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-ara').set(clientPhotoMessage('ara', 'Öğün: Ara'));
    await reactAndRun(CLIENT_UID, 'm-ara', ADMIN_UID, '❤️');
    report(t, 'yakalanan');
    assert.equal(onlyNotification().message.notification.body, 'Ara öğün fotoğrafınıza ❤️ bıraktı');
  });

  test('4.2 "Öğün: Diğer" fotoğrafına 👍 bırakınca gövde "Öğün fotoğrafınıza 👍 bıraktı" olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-diger').set(clientPhotoMessage('diger', 'Öğün: Diğer'));
    await reactAndRun(CLIENT_UID, 'm-diger', ADMIN_UID, '👍');
    report(t, 'yakalanan');
    assert.equal(onlyNotification().message.notification.body, 'Öğün fotoğrafınıza 👍 bıraktı');
  });

  test('4.2 eski etiketli "Öğün: Hiçbiri" fotoğrafına 👍 bırakınca gövde "Öğün fotoğrafınıza 👍 bıraktı" olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-hicbiri').set(clientPhotoMessage('hicbiri', 'Öğün: Hiçbiri'));
    await reactAndRun(CLIENT_UID, 'm-hicbiri', ADMIN_UID, '👍');
    report(t, 'yakalanan');
    assert.equal(onlyNotification().message.notification.body, 'Öğün fotoğrafınıza 👍 bıraktı');
  });

  test('öğün dışı fotoğrafa (metinsiz) 👍 bırakınca gövde "bir fotoğrafınıza 👍 bıraktı" olur', async (t) => {
    const msg = clientPhotoMessage('serbest', '');
    delete msg.text;
    delete msg.storagePath;
    await messageRef(CLIENT_UID, 'm-foto').set(msg);
    await reactAndRun(CLIENT_UID, 'm-foto', ADMIN_UID, '👍');
    report(t, 'yakalanan');
    assert.equal(onlyNotification().message.notification.body, 'bir fotoğrafınıza 👍 bıraktı');
  });

  test('öğün dışı açıklamalı fotoğrafa ("Bugünkü tartım") 👍 bırakınca gövde "bir fotoğrafınıza 👍 bıraktı" olur', async (t) => {
    const msg = clientPhotoMessage('tartim', 'Bugünkü tartım');
    delete msg.storagePath;
    await messageRef(CLIENT_UID, 'm-foto2').set(msg);
    await reactAndRun(CLIENT_UID, 'm-foto2', ADMIN_UID, '👍');
    report(t, 'yakalanan');
    assert.equal(onlyNotification().message.notification.body, 'bir fotoğrafınıza 👍 bıraktı');
  });

  test('metin mesajına 👍 bırakınca gövde "bir mesajınıza 👍 ifadesi bıraktı" olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-metin').set(textMessage(CLIENT_UID, 'Merhaba'));
    await reactAndRun(CLIENT_UID, 'm-metin', ADMIN_UID, '👍');
    report(t, 'yakalanan');
    const {message} = onlyNotification();
    assert.equal(message.notification.title, ADMIN_TO_USER_TITLE);
    assert.equal(message.notification.body, 'bir mesajınıza 👍 ifadesi bıraktı');
    assert.equal(message.data.messageId, 'm-metin');
  });

  test('4.4 admin ifadesini 👍\'dan 😍\'ye değiştirince danışana ikinci bildirim gitmez', async (t) => {
    await messageRef(CLIENT_UID, 'm-ogle').set(clientPhotoMessage('ogle1', 'Öğün: Öğle'));
    await reactAndRun(CLIENT_UID, 'm-ogle', ADMIN_UID, '👍');
    report(t, 'ilk ifade (👍)');
    assert.equal(sent.length, 1);
    sent.length = 0;
    const change = await reactAndRun(CLIENT_UID, 'm-ogle', ADMIN_UID, '😍');
    report(t, 'değiştirme (😍)');
    assert.deepEqual(change.after.get('reactions'), {[ADMIN_UID]: '😍'});
    assert.equal(sent.length, 0);
  });

  test('admin ifadesini kaldırınca danışana bildirim gitmez', async (t) => {
    await messageRef(CLIENT_UID, 'm-ogle').set(clientPhotoMessage('ogle1', 'Öğün: Öğle'));
    await reactAndRun(CLIENT_UID, 'm-ogle', ADMIN_UID, '👍');
    report(t, 'ilk ifade (👍)');
    assert.equal(sent.length, 1);
    sent.length = 0;
    const change = await reactAndRun(CLIENT_UID, 'm-ogle', ADMIN_UID, null);
    report(t, 'kaldırma');
    assert.deepEqual(change.after.get('reactions'), {});
    assert.equal(sent.length, 0);
  });
});

describe('notifyAdminsOnUserReaction: danışan admin mesajına ifade bırakınca admine bildirim', () => {
  test('2.9 danışan admin mesajına 👍 bırakınca adminlere başlığı danışanın adı soyadı, gövdesi "bir mesajınıza 👍 ifadesi bıraktı" olan bildirim gider', async (t) => {
    await messageRef(CLIENT_UID, 'm-admin').set(textMessage(ADMIN_UID, 'Merhaba, bugün nasılsınız?'));
    await reactAndRun(CLIENT_UID, 'm-admin', CLIENT_UID, '👍');
    report(t, 'yakalanan');
    const {method, message} = onlyNotification();
    assert.equal(method, 'sendEachForMulticast');
    assert.deepEqual([...message.tokens].sort(), ADMIN_UIDS.map(adminToken).sort());
    assert.equal(message.notification.title, `${CLIENT_NAME} ${CLIENT_SURNAME}`);
    assert.equal(message.notification.body, 'bir mesajınıza 👍 ifadesi bıraktı');
    assert.equal(message.data.chatId, CLIENT_UID);
  });

  test('2.10 danışan ifadesini ❤️\'ye değiştirince adminlere ikinci bildirim gitmez', async (t) => {
    await messageRef(CLIENT_UID, 'm-admin').set(textMessage(ADMIN_UID, 'Merhaba, bugün nasılsınız?'));
    await reactAndRun(CLIENT_UID, 'm-admin', CLIENT_UID, '👍');
    assert.equal(sent.length, 1);
    sent.length = 0;
    const change = await reactAndRun(CLIENT_UID, 'm-admin', CLIENT_UID, '❤️');
    report(t, 'değiştirme (❤️)');
    assert.deepEqual(change.after.get('reactions'), {[CLIENT_UID]: '❤️'});
    assert.equal(sent.length, 0);
  });

  test('2.10 danışan ❤️\'ye tekrar basıp ifadeyi kaldırınca adminlere bildirim gitmez', async (t) => {
    await messageRef(CLIENT_UID, 'm-admin').set(textMessage(ADMIN_UID, 'Merhaba, bugün nasılsınız?'));
    await reactAndRun(CLIENT_UID, 'm-admin', CLIENT_UID, '❤️');
    report(t, 'ilk ifade (❤️)');
    assert.equal(sent.length, 1);
    sent.length = 0;
    const change = await reactAndRun(CLIENT_UID, 'm-admin', CLIENT_UID, null);
    report(t, 'kaldırma');
    assert.deepEqual(change.after.get('reactions'), {});
    assert.equal(sent.length, 0);
  });
});

describe('notifyAdminsOnUserMessage: danışan mesaj gönderince admine bildirim', () => {
  test('3.3 danışan "Öğün: Öğle" fotoğraf mesajı oluşturunca admin bildiriminin gövdesi "Öğün: Öğle", başlığı danışanın adı soyadı olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-yeni').set(clientPhotoMessage('ogle1', 'Öğün: Öğle'));
    await runMessageCreated(CLIENT_UID, 'm-yeni');
    report(t, 'yakalanan');
    const {message} = onlyNotification();
    assert.deepEqual([...message.tokens].sort(), ADMIN_UIDS.map(adminToken).sort());
    assert.equal(message.notification.title, `${CLIENT_NAME} ${CLIENT_SURNAME}`);
    assert.equal(message.notification.body, 'Öğün: Öğle');
    assert.equal(message.data.chatId, CLIENT_UID);
  });

  test('eski sürümden gelen "Öğün: Ara Öğün 2" mesajında admin bildiriminin gövdesi "Öğün: Ara" olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-eski').set(clientPhotoMessage('ara2', 'Öğün: Ara Öğün 2'));
    await runMessageCreated(CLIENT_UID, 'm-eski');
    report(t, 'yakalanan');
    assert.equal(onlyNotification().message.notification.body, 'Öğün: Ara');
  });

  test('eski sürümden gelen "Öğün: Hiçbiri" mesajında admin bildiriminin gövdesi "Öğün: Diğer" olur', async (t) => {
    await messageRef(CLIENT_UID, 'm-eski2').set(clientPhotoMessage('hicbiri', 'Öğün: Hiçbiri'));
    await runMessageCreated(CLIENT_UID, 'm-eski2');
    report(t, 'yakalanan');
    assert.equal(onlyNotification().message.notification.body, 'Öğün: Diğer');
  });

  test('2.5 danışan "Test 2" yazınca admin bildiriminin başlığı danışanın adı soyadı, gövdesi "Test 2" olur ve danışana bildirim gitmez', async (t) => {
    await messageRef(CLIENT_UID, 'm-test2').set(textMessage(CLIENT_UID, 'Test 2'));
    await runMessageCreated(CLIENT_UID, 'm-test2');
    report(t, 'yakalanan');
    const {message} = onlyNotification();
    assert.deepEqual([...message.tokens].sort(), ADMIN_UIDS.map(adminToken).sort());
    assert.equal(message.notification.title, `${CLIENT_NAME} ${CLIENT_SURNAME}`);
    assert.equal(message.notification.body, 'Test 2');
    assert.equal(message.data.type, 'chat_admin');
    assert.equal(message.data.chatId, CLIENT_UID);
    assert.equal(message.data.senderId, CLIENT_UID);
  });
});

describe('markChatMessagesOfDeletedMealPhotos: öğün kaydından silinen fotoğrafın sohbet mesajı nota döner', () => {
  async function seedLunchWithTwoPhotos(extraForFirst = {}) {
    await mealEntryRef(CLIENT_UID, 'lunch').set(mealEntry('lunch', ['u1', 'u2']));
    await messageRef(CLIENT_UID, 'm-u1').set(clientPhotoMessage('u1', 'Öğün: Öğle', extraForFirst));
    await messageRef(CLIENT_UID, 'm-u2').set(clientPhotoMessage('u2', 'Öğün: Öğle'));
    await chatRef(CLIENT_UID).set({
      participants: [CLIENT_UID, ...ADMIN_UIDS],
      lastMessage: 'Öğün Fotoğrafı (Öğle)',
      lastImageUrl: photoUrl('u1'),
      lastImageThumbUrl: thumbUrl('u1'),
      lastMessageAt: admin.firestore.Timestamp.now(),
    });
  }

  function assertDeletedNote(data, expectedText) {
    assert.equal(data.photoDeleted, true);
    assert.equal(data.text, expectedText);
    for (const field of ['imageUrl', 'thumbUrl', 'imageWidth', 'imageHeight']) {
      assert.equal(field in data, false, `${field} alanı silinmemiş: ${JSON.stringify(data[field])}`);
    }
  }

  test('7.1/7.3/7.9 imageUrls [u1,u2] → [u2] olunca u1 mesajı "Öğün: Öğle (fotoğraf silindi)" notuna döner, görsel alanları silinir, sohbet özeti temizlenir', async (t) => {
    await seedLunchWithTwoPhotos();
    await runMealEntryWritten(CLIENT_UID, 'lunch', () =>
      mealEntryRef(CLIENT_UID, 'lunch').set(mealEntry('lunch', ['u2'])));
    const m1 = (await messageRef(CLIENT_UID, 'm-u1').get()).data();
    const m2 = (await messageRef(CLIENT_UID, 'm-u2').get()).data();
    const chat = (await chatRef(CLIENT_UID).get()).data();
    t.diagnostic(`u1 mesajı: ${JSON.stringify({text: m1.text, photoDeleted: m1.photoDeleted, alanlar: Object.keys(m1).sort()})}`);
    t.diagnostic(`sohbet özeti: ${JSON.stringify({lastMessage: chat.lastMessage, lastImageUrl: chat.lastImageUrl, lastImageThumbUrl: chat.lastImageThumbUrl})}`);
    report(t, 'yakalanan bildirimler');
    assertDeletedNote(m1, 'Öğün: Öğle (fotoğraf silindi)');
    assert.equal(m2.imageUrl, photoUrl('u2'));
    assert.equal(m2.text, 'Öğün: Öğle');
    assert.equal('photoDeleted' in m2, false);
    assert.equal(chat.lastImageUrl, '');
    assert.equal(chat.lastImageThumbUrl, '');
    assert.equal(chat.lastMessage, 'Öğün: Öğle (fotoğraf silindi)');
    assert.equal(sent.length, 0);
  });

  test('silinen fotoğraf sohbetin son fotoğrafı değilse sohbet özeti olduğu gibi kalır', async (t) => {
    await seedLunchWithTwoPhotos();
    await chatRef(CLIENT_UID).update({lastImageUrl: photoUrl('u2'), lastImageThumbUrl: thumbUrl('u2')});
    await runMealEntryWritten(CLIENT_UID, 'lunch', () =>
      mealEntryRef(CLIENT_UID, 'lunch').set(mealEntry('lunch', ['u2'])));
    const chat = (await chatRef(CLIENT_UID).get()).data();
    t.diagnostic(`sohbet özeti: ${JSON.stringify({lastMessage: chat.lastMessage, lastImageUrl: chat.lastImageUrl})}`);
    assert.equal(chat.lastImageUrl, photoUrl('u2'));
    assert.equal(chat.lastMessage, 'Öğün Fotoğrafı (Öğle)');
  });

  test('7.1 öğünün son fotoğrafı silinip öğün kaydı tamamen kalkınca mesaj "Öğün: Akşam (fotoğraf silindi)" notuna döner ve sohbet özeti temizlenir', async (t) => {
    await mealEntryRef(CLIENT_UID, 'dinner').set(mealEntry('dinner', ['u3']));
    await messageRef(CLIENT_UID, 'm-u3').set(clientPhotoMessage('u3', 'Öğün: Akşam', {storagePath: `meals/${CLIENT_UID}/dinner`}));
    await chatRef(CLIENT_UID).set({
      participants: [CLIENT_UID, ...ADMIN_UIDS],
      lastMessage: 'Öğün Fotoğrafı (Akşam)',
      lastImageUrl: photoUrl('u3'),
      lastImageThumbUrl: thumbUrl('u3'),
    });
    const change = await runMealEntryWritten(CLIENT_UID, 'dinner', () =>
      mealEntryRef(CLIENT_UID, 'dinner').delete());
    assert.equal(change.after.exists, false);
    const m3 = (await messageRef(CLIENT_UID, 'm-u3').get()).data();
    const chat = (await chatRef(CLIENT_UID).get()).data();
    t.diagnostic(`u3 mesajı: ${JSON.stringify({text: m3.text, photoDeleted: m3.photoDeleted, alanlar: Object.keys(m3).sort()})}`);
    t.diagnostic(`sohbet özeti: ${JSON.stringify({lastMessage: chat.lastMessage, lastImageUrl: chat.lastImageUrl, lastImageThumbUrl: chat.lastImageThumbUrl})}`);
    assertDeletedNote(m3, 'Öğün: Akşam (fotoğraf silindi)');
    assert.equal(chat.lastImageUrl, '');
    assert.equal(chat.lastImageThumbUrl, '');
    assert.equal(chat.lastMessage, 'Öğün: Akşam (fotoğraf silindi)');
  });

  test('eski "Öğün: Ara Öğün 2" mesajının fotoğrafı silinince not "Öğün: Ara (fotoğraf silindi)" olur', async (t) => {
    await mealEntryRef(CLIENT_UID, 'secondmid').set(mealEntry('secondmid', ['u4', 'u5']));
    await messageRef(CLIENT_UID, 'm-u4').set(clientPhotoMessage('u4', 'Öğün: Ara Öğün 2', {storagePath: `meals/${CLIENT_UID}/secondmid`}));
    await chatRef(CLIENT_UID).set({
      participants: [CLIENT_UID, ...ADMIN_UIDS],
      lastMessage: 'Öğün Fotoğrafı (Ara Öğün 2)',
      lastImageUrl: photoUrl('u4'),
      lastImageThumbUrl: thumbUrl('u4'),
    });
    await runMealEntryWritten(CLIENT_UID, 'secondmid', () =>
      mealEntryRef(CLIENT_UID, 'secondmid').set(mealEntry('secondmid', ['u5'])));
    const m4 = (await messageRef(CLIENT_UID, 'm-u4').get()).data();
    const chat = (await chatRef(CLIENT_UID).get()).data();
    t.diagnostic(`u4 mesajı: ${JSON.stringify({text: m4.text, photoDeleted: m4.photoDeleted})}; sohbet özeti: ${JSON.stringify({lastMessage: chat.lastMessage, lastImageUrl: chat.lastImageUrl})}`);
    assertDeletedNote(m4, 'Öğün: Ara (fotoğraf silindi)');
    assert.equal(chat.lastMessage, 'Öğün: Ara (fotoğraf silindi)');
  });

  test('fonksiyonun mesajı nota çevirmesi (mesaj güncellemesi) ifade tetikleyicilerinde bildirim göndermez', async (t) => {
    await seedLunchWithTwoPhotos();
    await reactAndRun(CLIENT_UID, 'm-u1', ADMIN_UID, '👍');
    report(t, 'silmeden önceki ifade (👍)');
    assert.equal(sent.length, 1);
    sent.length = 0;
    const ref = messageRef(CLIENT_UID, 'm-u1');
    const change = await captureChange(ref, () =>
      runMealEntryWritten(CLIENT_UID, 'lunch', () =>
        mealEntryRef(CLIENT_UID, 'lunch').set(mealEntry('lunch', ['u2']))));
    await runMessageUpdated(CLIENT_UID, 'm-u1', change);
    report(t, 'yakalanan');
    assert.equal(change.after.get('photoDeleted'), true);
    assert.equal(sent.length, 0);
  });

  test('bulgu #2: daha önce ifade bırakılmış fotoğraf silinince notta eski ifade (reactions) kalmamalı', async (t) => {
    await seedLunchWithTwoPhotos({reactions: {[ADMIN_UID]: '👍'}});
    await runMealEntryWritten(CLIENT_UID, 'lunch', () =>
      mealEntryRef(CLIENT_UID, 'lunch').set(mealEntry('lunch', ['u2'])));
    const m1 = (await messageRef(CLIENT_UID, 'm-u1').get()).data();
    t.diagnostic(`silme sonrası u1 mesajı: ${JSON.stringify({text: m1.text, photoDeleted: m1.photoDeleted, reactions: m1.reactions})}`);
    assert.equal(m1.photoDeleted, true);
    assert.ok(
        m1.reactions === undefined || Object.keys(m1.reactions).length === 0,
        `reactions notta duruyor: ${JSON.stringify(m1.reactions)}`);
  });
});

describe('bulgu #1: fotoğrafı silinmiş (nota dönmüş) mesaja ifade', () => {
  test('admin "Öğün: Öğle (fotoğraf silindi)" notuna 👍 bırakınca danışana ifade bildirimi gitmemeli', async (t) => {
    await mealEntryRef(CLIENT_UID, 'lunch').set(mealEntry('lunch', ['u6']));
    await messageRef(CLIENT_UID, 'm-u6').set(clientPhotoMessage('u6', 'Öğün: Öğle'));
    await runMealEntryWritten(CLIENT_UID, 'lunch', () => mealEntryRef(CLIENT_UID, 'lunch').delete());
    const note = (await messageRef(CLIENT_UID, 'm-u6').get()).data();
    t.diagnostic(`not: ${JSON.stringify({text: note.text, photoDeleted: note.photoDeleted, alanlar: Object.keys(note).sort()})}`);
    assert.equal(note.photoDeleted, true);
    assert.equal(note.text, 'Öğün: Öğle (fotoğraf silindi)');
    await messageRef(CLIENT_UID, 'm-kontrol').set(clientPhotoMessage('kontrol', 'Öğün: Öğle'));
    sent.length = 0;
    await reactAndRun(CLIENT_UID, 'm-kontrol', ADMIN_UID, '👍');
    report(t, 'fotoğrafı duran mesaja ifade (kontrol)');
    assert.equal(sent.length, 1);
    sent.length = 0;
    await reactAndRun(CLIENT_UID, 'm-u6', ADMIN_UID, '👍');
    report(t, 'yakalanan');
    assert.equal(sent.length, 0, `silinmiş fotoğrafa ifade bildirimi gitti: ${JSON.stringify(summarize())}`);
  });
});
