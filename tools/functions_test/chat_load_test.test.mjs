import {createRequire} from 'node:module';
import admin from 'firebase-admin';

const require = createRequire(import.meta.url);
const core = require('../../functions/chat_load_test.js');

const PROJECT = 'demo-ngy';
const BUCKET = `${PROJECT}.appspot.com`;
const ADMIN_UID = 'SdPI69ChOvepuq9HrlW6no9rMRn1';
const OFFICE_UID = '0MvvbZsjbmNPW4QYShRNSOOtkE43';
const FUNCTIONS_URL = `http://127.0.0.1:5001/${PROJECT}/us-central1`;

admin.initializeApp({projectId: PROJECT, storageBucket: BUCKET});
const db = admin.firestore();
const bucket = admin.storage().bucket();
const {Timestamp} = admin.firestore;

let failures = 0;
function check(name, ok, detail = '') {
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ` | ${detail}` : ''}`);
  if (!ok) failures++;
}

function throwsInput(fn) {
  try {
    fn();
    return false;
  } catch (e) {
    return e instanceof core.LoadTestInputError;
  }
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function validRequest(overrides = {}) {
  const runId = 'Run1234567890';
  return {
    runId,
    userCount: 3,
    photosPerUser: 2,
    gapSeconds: 1,
    startDelaySeconds: 2,
    order: 'roundRobin',
    utcOffsetMinutes: 180,
    photos: [{
      path: `chatLoadTests/${runId}/p0_tabak.jpg`,
      fileName: 'tabak.jpg',
      thumbPath: `chatLoadTests/${runId}/p0_tabak_thumb.jpg`,
      width: 1200,
      height: 1600,
    }],
    slots: [
      {photo: 0, meal: 'lunch', caption: 'Öğün: Öğle',
        summary: 'Öğün Fotoğrafı (Öğle)'},
      {photo: 0, meal: 'dinner', caption: 'Öğün: Akşam',
        summary: 'Öğün Fotoğrafı (Akşam)'},
    ],
    ...overrides,
  };
}

const parsed = core.parseStartRequest(validRequest());
check('U1 geçerli istek okunur',
    parsed.totalSteps === 6 && parsed.gapMs === 1000 &&
    parsed.photos[0].width === 1200 && parsed.slots[1].meal === 'dinner');
check('U2 kullanıcı sayısı sınırı',
    throwsInput(() => core.parseStartRequest(validRequest({userCount: 0}))) &&
    throwsInput(() => core.parseStartRequest(validRequest({userCount: 101}))));
check('U3 sıra sayısı kişi başı fotoğrafla aynı olmalı',
    throwsInput(() => core.parseStartRequest(validRequest({photosPerUser: 3}))));
check('U4 başka klasördeki kaynak reddedilir',
    throwsInput(() => core.parseStartRequest(validRequest({
      photos: [{path: 'users/x/a.jpg', fileName: 'a.jpg'}],
    }))) &&
    throwsInput(() => core.parseStartRequest(validRequest({
      photos: [{path: 'chatLoadTests/Run1234567890/../x.jpg',
        fileName: 'a.jpg'}],
    }))));
check('U5 öğün adı yol karakteri taşıyamaz',
    throwsInput(() => core.parseStartRequest(validRequest({
      slots: [
        {photo: 0, meal: 'lu/nch', caption: 'a', summary: 'b'},
        {photo: 0, meal: 'dinner', caption: 'a', summary: 'b'},
      ],
    }))));
check('U6 dosya adında / olamaz',
    throwsInput(() => core.parseStartRequest(validRequest({
      photos: [{path: 'chatLoadTests/Run1234567890/p0', fileName: 'a/b.jpg'}],
    }))));
check('U7 iki saati aşan test reddedilir',
    throwsInput(() => core.parseStartRequest(validRequest({
      userCount: 100, photosPerUser: 2, gapSeconds: 600,
      slots: validRequest().slots,
    }))));
check('U8 kesirli aralık kabul edilir',
    core.parseStartRequest(validRequest({gapSeconds: 0.5})).gapMs === 500);
check('U9 tek ölçü verilirse ölçü yazılmaz',
    core.parseStartRequest(validRequest({
      photos: [{path: 'chatLoadTests/Run1234567890/p0.jpg',
        fileName: 'p0.jpg', width: 10}],
    })).photos[0].width === null);

const rr = [0, 1, 2, 3, 4, 5].map((k) => core.stepPosition(k, 3, 2,
    'roundRobin'));
check('U10 sırayla: her turda herkes birer',
    JSON.stringify(rr) === JSON.stringify([
      {user: 0, slot: 0}, {user: 1, slot: 0}, {user: 2, slot: 0},
      {user: 0, slot: 1}, {user: 1, slot: 1}, {user: 2, slot: 1},
    ]), JSON.stringify(rr));
const pu = [0, 1, 2, 3].map((k) => core.stepPosition(k, 2, 2, 'perUser'));
check('U11 kişi kişi: önce bir kişinin bütün fotoğrafları',
    JSON.stringify(pu) === JSON.stringify([
      {user: 0, slot: 0}, {user: 0, slot: 1},
      {user: 1, slot: 0}, {user: 1, slot: 1},
    ]), JSON.stringify(pu));

const tickBase = {
  totalSteps: 1000, startAtMs: 100000, gapMs: 1000, nowMs: 100000,
  windowMs: 240000, maxSteps: 200, leadMs: 45000,
};
let plan = core.planTick({...tickBase, fromIndex: 0});
check('U12 sık adımlarda halka adım sınırında biter, devri ilk adımdan önce',
    plan.until === 200 && plan.handoffAtMs === 100000 + 200000 - 45000,
    JSON.stringify(plan));
plan = core.planTick({...tickBase, fromIndex: 0, gapMs: 0});
check('U13 aralık 0: halkalar hemen devreder',
    plan.until === 200 && plan.handoffAtMs === 100000, JSON.stringify(plan));
plan = core.planTick({...tickBase, fromIndex: 0, totalSteps: 5});
check('U14 son halka devretmez', plan.until === 5 && plan.handoffAtMs === null,
    JSON.stringify(plan));
plan = core.planTick({...tickBase, fromIndex: 3, gapMs: 600000,
  totalSteps: 10});
check('U15 uzun aralıkta halka boş kalır, pencere sonunda devreder',
    plan.until === 3 && plan.handoffAtMs === 100000 + 240000,
    JSON.stringify(plan));
plan = core.planTick({...tickBase, fromIndex: 0, startAtMs: 100000 + 250000,
  totalSteps: 10});
check('U16 başlama gecikmesi pencereyi aşarsa devir ilk adımdan 45 sn önce',
    plan.until === 0 && plan.handoffAtMs === 100000 + 250000 - 45000,
    JSON.stringify(plan));
plan = core.planTick({...tickBase, fromIndex: 0, startAtMs: 100000 + 400000,
  totalSteps: 10});
check('U17 ilk adım iki pencere ötedeyse devir pencere sonunda',
    plan.until === 0 && plan.handoffAtMs === 100000 + 240000,
    JSON.stringify(plan));

check('U18 gün cihazın saat dilimine göre',
    core.dateKeyOf(Date.UTC(2026, 10, 10, 22, 30), 180) === '2026-11-11' &&
    core.dateKeyOf(Date.UTC(2026, 10, 10, 22, 30), 0) === '2026-11-10' &&
    core.dateKeyOf(Date.UTC(2026, 10, 10, 1, 0), -300) === '2026-11-09');
check('U19 küçük görsel adı uygulamadaki gibi',
    core.thumbnailNameFor('171_tabak.jpg', '.jpg') === '171_tabak_thumb.jpg' &&
    core.thumbnailNameFor('171_tabak', '.png') === '171_tabak_thumb.png' &&
    core.extensionOf('chatLoadTests/R/p0_a.b_thumb.png') === '.png' &&
    core.extensionOf('chatLoadTests/R.x/p0') === '');
check('U20 indirme adresi istemcinin biçiminde',
    core.downloadUrlOf('b.appspot.com', 'users/u 1/a.jpg', 't1', undefined) ===
    'https://firebasestorage.googleapis.com/v0/b/b.appspot.com/o/' +
    'users%2Fu%201%2Fa.jpg?alt=media&token=t1' &&
    core.downloadUrlOf('b', 'a/b', 't', '127.0.0.1:9199') ===
    'http://127.0.0.1:9199/v0/b/b/o/a%2Fb?alt=media&token=t');

const t1 = Timestamp.fromMillis(1000);
const t2 = Timestamp.fromMillis(2000);
let entry = core.mealEntryWithImage(null, {meal: 'lunch',
  subscriptionId: 'u', imageUrl: 'a', thumbUrl: 'ta', time: t1});
check('U21 yeni öğün kaydı uygulamanın biçiminde',
    entry.kind === 'written' &&
    JSON.stringify(entry.doc.imageUrls) === '["a"]' &&
    JSON.stringify(entry.doc.thumbUrls) === '["ta"]' &&
    entry.doc.imageTimes[0] === t1 && entry.doc.imageUrl === 'a' &&
    entry.doc.isChecked === true && entry.doc.description === null &&
    entry.doc.calories === null && entry.doc.notes === null &&
    entry.doc.subscriptionId === 'u' && entry.doc.mealType === 'lunch',
    JSON.stringify(entry));
entry = core.mealEntryWithImage({imageUrls: ['a', 'b'], thumbUrls: ['ta'],
  imageTimes: [t1], timestamp: t1, description: 'not'}, {meal: 'lunch',
  subscriptionId: 'u', imageUrl: 'c', thumbUrl: null, time: t2});
check('U22 eksik küçük görsel ve saatler hizalanır, yeni fotoğraf sona',
    entry.kind === 'written' &&
    JSON.stringify(entry.doc.imageUrls) === '["a","b","c"]' &&
    JSON.stringify(entry.doc.thumbUrls) === '["ta","",""]' &&
    entry.doc.imageTimes.length === 3 && entry.doc.imageTimes[1] === t1 &&
    entry.doc.imageTimes[2] === t2 && entry.doc.description === 'not',
    JSON.stringify(entry.doc));
check('U23 aynı fotoğraf ikinci kez eklenmez',
    core.mealEntryWithImage({imageUrls: ['a'], timestamp: t1},
        {meal: 'lunch', imageUrl: 'a', time: t2}).kind === 'already');
check('U24 sınır (10) doluysa eklenmez',
    core.mealEntryWithImage({imageUrls: Array.from({length: 10},
        (_, i) => `u${i}`), timestamp: t1},
    {meal: 'lunch', imageUrl: 'z', time: t2}).kind === 'limit');
check('U25 test UID biçimi ve kapsamı',
    core.testUserUid('Run1234567890', 0) === 'loadtest_Run1234567890_001' &&
    core.isTestUserUid('loadtest_Run1234567890_001') &&
    !core.isTestUserUid('0MvvbZsjbmNPW4QYShRNSOOtkE43') &&
    !core.isTestUserUid('loadtest_x_001') &&
    core.isTestUserUidOf('loadtest_Run1234567890_012', 'Run1234567890') &&
    !core.isTestUserUidOf('loadtest_Run1234567890_012', 'Run123456789'));

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

async function call(name, uid, data) {
  const headers = {'Content-Type': 'application/json'};
  if (uid) headers.Authorization = `Bearer ${fakeIdToken(uid)}`;
  const res = await fetch(`${FUNCTIONS_URL}/${name}`, {
    method: 'POST',
    headers,
    body: JSON.stringify({data}),
  });
  return {status: res.status, body: await res.json().catch(() => null)};
}

async function waitForFunctions() {
  const end = Date.now() + 60000;
  while (Date.now() < end) {
    try {
      const res = await call('cleanupChatLoadTests', null, {});
      if (res.status !== 404) return;
    } catch (e) {
      await sleep(500);
      continue;
    }
    await sleep(500);
  }
  throw new Error('Functions emülatörü yanıt vermedi');
}

async function waitRun(runId, predicate, timeoutMs = 90000) {
  const end = Date.now() + timeoutMs;
  let snap;
  do {
    snap = await db.collection('chatLoadTests').doc(runId).get();
    if (predicate(snap)) return snap;
    await sleep(500);
  } while (Date.now() < end);
  return snap;
}

const ORIGINAL = Buffer.from('ilk-test-fotografi-'.repeat(200));
const THUMB = Buffer.from('kucuk-gorsel-'.repeat(20));

async function prepareRun(runId) {
  await bucket.file(`chatLoadTests/${runId}/p0_tabak.jpg`)
      .save(ORIGINAL, {resumable: false,
        metadata: {contentType: 'image/jpeg'}});
  await bucket.file(`chatLoadTests/${runId}/p0_tabak_thumb.jpg`)
      .save(THUMB, {resumable: false,
        metadata: {contentType: 'image/jpeg'}});
  await db.collection('chatLoadTests').doc(runId).set({
    status: 'preparing',
    createdAt: Timestamp.now(),
    createdBy: ADMIN_UID,
  });
}

function startData(runId, overrides = {}) {
  const request = validRequest(overrides);
  request.runId = runId;
  request.photos = request.photos.map((photo) => ({
    ...photo,
    path: photo.path.replace('Run1234567890', runId),
    thumbPath: photo.thumbPath ?
      photo.thumbPath.replace('Run1234567890', runId) : photo.thumbPath,
  }));
  return request;
}

async function storageExists(path) {
  const [exists] = await bucket.file(path).exists();
  return exists;
}

function pathOfUrl(url) {
  const match = /\/o\/([^?]+)\?/.exec(url || '');
  return match ? decodeURIComponent(match[1]) : '';
}

await waitForFunctions();

const RUN_A = 'RunAaaaaaaaa1';
await prepareRun(RUN_A);

let res = await call('startChatLoadTest', 'musteri1', startData(RUN_A));
check('E1 danışan testi başlatamaz', res.status !== 200 &&
    JSON.stringify(res.body).includes('PERMISSION_DENIED'),
    `${res.status} ${JSON.stringify(res.body)}`);
res = await call('startChatLoadTest', ADMIN_UID,
    startData(RUN_A, {userCount: 0}));
check('E2 geçersiz istek reddedilir', res.status !== 200 &&
    JSON.stringify(res.body).includes('INVALID_ARGUMENT'),
    `${res.status} ${JSON.stringify(res.body)}`);

const startedAt = Date.now();
res = await call('startChatLoadTest', ADMIN_UID, startData(RUN_A));
check('E3 admin başlatır', res.status === 200 &&
    res.body.result.totalSteps === 6 && res.body.result.userCount === 3,
    `${res.status} ${JSON.stringify(res.body)}`);
const startAtMs = res.body && res.body.result ? res.body.result.startAtMs : 0;
check('E4 ilk mesaj başlama gecikmesi kadar sonra',
    startAtMs >= startedAt + 2000, `${startAtMs - startedAt}`);

res = await call('startChatLoadTest', ADMIN_UID, startData(RUN_A));
check('E5 aynı test ikinci kez başlatılamaz', res.status !== 200 &&
    JSON.stringify(res.body).includes('FAILED_PRECONDITION'),
    `${res.status} ${JSON.stringify(res.body)}`);

let run = await waitRun(RUN_A, (s) => s.get('status') === 'completed');
check('E6 test tamamlanır', run.get('status') === 'completed' &&
    run.get('sentCount') === 6 && run.get('failedCount') === 0,
    JSON.stringify(run.data() && {
      status: run.get('status'), sent: run.get('sentCount'),
      failed: run.get('failedCount'), error: run.get('lastError'),
    }));

const users = run.get('users') || [];
check('E7 kullanıcılar çalıştırmaya yazılır', users.length === 3 &&
    users.every((u, i) => u.uid === core.testUserUid(RUN_A, i)),
    JSON.stringify(users));

const userDocs = await Promise.all(users.map((u) =>
  db.collection('users').doc(u.uid).get()));
check('E8 kullanıcı kayıtları danışan ve test işaretli',
    userDocs.every((d) => d.exists && d.get('role') === 'customer' &&
        d.get('isLoadTestUser') === true &&
        d.get('loadTestRunId') === RUN_A &&
        d.get('surname').startsWith('Test ') &&
        d.get('email').endsWith('@example.com')),
    JSON.stringify(userDocs.map((d) => d.data())));
const authUsers = await Promise.all(users.map((u) =>
  admin.auth().getUser(u.uid).then(() => true, () => false)));
check('E9 Auth hesapları açılır', authUsers.every(Boolean),
    JSON.stringify(authUsers));

const firstUser = users[0] ? users[0].uid : 'yok';
const messages = await db.collection('chats').doc(firstUser)
    .collection('messages').orderBy('createdAt').get();
check('E10 her kullanıcıya iki mesaj', messages.size === 2,
    `size=${messages.size}`);
const message = messages.docs[0] ? messages.docs[0].data() : {};
const expectedKeys = ['chatId', 'clientCreatedAt', 'createdAt', 'imageHeight',
  'imageUrl', 'imageWidth', 'loadTestRunId', 'senderId', 'storagePath', 'text',
  'thumbUrl'];
check('E11 mesaj uygulamanın öğün fotoğrafı mesajı biçiminde',
    JSON.stringify(Object.keys(message).sort()) ===
        JSON.stringify(expectedKeys) &&
    message.chatId === firstUser && message.senderId === firstUser &&
    message.text === 'Öğün: Öğle' &&
    message.storagePath === `meals/${firstUser}/lunch` &&
    message.imageWidth === 1200 && message.imageHeight === 1600 &&
    message.loadTestRunId === RUN_A,
    JSON.stringify(message));

const imagePath = pathOfUrl(message.imageUrl);
const thumbPath = pathOfUrl(message.thumbUrl);
const dateKey = core.dateKeyOf(message.clientCreatedAt.toMillis(), 180);
check('E12 fotoğraf kullanıcının öğün klasöründe, küçük görsel yanında',
    imagePath.startsWith(`users/${firstUser}/mealPhotos/${dateKey}/lunch/`) &&
    imagePath.endsWith('_tabak.jpg') &&
    thumbPath === imagePath.replace('_tabak.jpg', '_tabak_thumb.jpg'),
    `${imagePath} ${thumbPath}`);
check('E13 dosyalar Storage\'da', await storageExists(imagePath) &&
    await storageExists(thumbPath));
const download = await fetch(message.imageUrl);
const downloaded = Buffer.from(await download.arrayBuffer());
check('E14 indirme adresi çalışır ve aynı baytları verir',
    download.status === 200 && downloaded.equals(ORIGINAL),
    `${download.status} ${downloaded.length}`);
const [metadata] = await bucket.file(imagePath).getMetadata();
check('E15 dosya türü kaynaktan gelir', metadata.contentType === 'image/jpeg',
    metadata.contentType);

const chat = await db.collection('chats').doc(firstUser).get();
check('E16 sohbet özeti ve okunmamış sayısı',
    chat.exists &&
    JSON.stringify(chat.get('participants')) ===
        JSON.stringify([firstUser, OFFICE_UID]) &&
    chat.get('lastMessage') === 'Öğün Fotoğrafı (Akşam)' &&
    chat.get('adminUnreadCount')[OFFICE_UID] === 2 &&
    JSON.stringify(chat.get('hasUnreadFor')) === JSON.stringify([OFFICE_UID]) &&
    chat.get('lastImageThumbUrl') === messages.docs[1].get('thumbUrl') &&
    chat.get('lastImageUrl') === messages.docs[1].get('imageUrl'),
    JSON.stringify(chat.data()));

const lunch = await db.collection('users').doc(firstUser)
    .collection('meals').doc(dateKey).collection('mealEntries').doc('lunch')
    .get();
check('E17 öğün kaydı yazılır',
    lunch.exists && lunch.get('imageUrls').length === 1 &&
    lunch.get('imageUrls')[0] === message.imageUrl &&
    lunch.get('thumbUrls')[0] === message.thumbUrl &&
    lunch.get('subscriptionId') === firstUser && lunch.get('isChecked'),
    JSON.stringify(lunch.data()));
const day = await db.collection('users').doc(firstUser)
    .collection('meals').doc(dateKey).get();
check('E18 günün öğün işareti ve hatırlatma iptali',
    day.exists && day.get('meals').lunch === true &&
    day.get('meals').dinner === true &&
    day.get('reminderCancelled').lunch === true,
    JSON.stringify(day.data()));

const all = [];
for (const user of users) {
  const snap = await db.collection('chats').doc(user.uid)
      .collection('messages').get();
  for (const doc of snap.docs) {
    all.push({uid: user.uid, at: doc.get('clientCreatedAt').toMillis(),
      meal: doc.get('storagePath').split('/').pop()});
  }
}
all.sort((a, b) => a.at - b.at);
check('E19 sırayla gönderim: önce herkes öğle, sonra herkes akşam',
    all.length === 6 &&
    all.slice(0, 3).every((m) => m.meal === 'lunch') &&
    all.slice(3).every((m) => m.meal === 'dinner') &&
    new Set(all.slice(0, 3).map((m) => m.uid)).size === 3,
    JSON.stringify(all.map((m) => `${m.uid.slice(-3)}:${m.meal}`)));
const gaps = all.slice(1).map((m, i) => m.at - all[i].at);
check('E20 mesajlar arası süre ~1 sn', gaps.every((g) => g >= 700 &&
    g <= 2500), JSON.stringify(gaps));
check('E21 ilk mesaj başlama anında', all.length > 0 &&
    all[0].at >= startAtMs - 50 && all[0].at <= startAtMs + 3000,
    `${all.length ? all[0].at - startAtMs : 'yok'}`);

await db.collection('chatLoadTests').doc(RUN_A).collection('ticks')
    .doc('r1_00000').set({chain: 'r1', fromIndex: 0, createdAt:
      Timestamp.now()});
await db.collection('chatLoadTests').doc(RUN_A).update({status: 'running'});
await sleep(6000);
let count = 0;
for (const user of users) {
  count += (await db.collection('chats').doc(user.uid)
      .collection('messages').get()).size;
}
run = await db.collection('chatLoadTests').doc(RUN_A).get();
check('E22 sürdürme gönderilmiş mesajı yinelemez', count === 6 &&
    run.get('sentCount') === 6, `count=${count} sent=${run.get('sentCount')}`);

const RUN_B = 'RunBbbbbbbbb2';
await prepareRun(RUN_B);
res = await call('startChatLoadTest', ADMIN_UID, startData(RUN_B, {
  userCount: 2, photosPerUser: 3, gapSeconds: 2, startDelaySeconds: 0,
  order: 'perUser',
  slots: [
    {photo: 0, meal: 'br', caption: 'Öğün: Sabah',
      summary: 'Öğün Fotoğrafı (Sabah)'},
    {photo: 0, meal: 'firstmid', caption: 'Öğün: Ara',
      summary: 'Öğün Fotoğrafı (Ara)'},
    {photo: 0, meal: 'lunch', caption: 'Öğün: Öğle',
      summary: 'Öğün Fotoğrafı (Öğle)'},
  ],
}));
check('E23 ikinci test başlar', res.status === 200,
    `${res.status} ${JSON.stringify(res.body)}`);
async function stopRun(runId) {
  const runRef = db.collection('chatLoadTests').doc(runId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(runRef);
    if (['preparing', 'creatingUsers', 'running']
        .includes(snap.get('status'))) {
      tx.update(runRef, {status: 'cancelled', finishedAt: Timestamp.now()});
    }
    tx.set(runRef.collection('control').doc('stop'),
        {createdAt: Timestamp.now()});
  });
}

run = await waitRun(RUN_B, (s) => (s.get('sentCount') || 0) >= 2, 30000);
await stopRun(RUN_B);
await sleep(8000);
run = await db.collection('chatLoadTests').doc(RUN_B).get();
const usersB = run.get('users') || [];
let countB = 0;
let filesB = 0;
for (const user of usersB) {
  countB += (await db.collection('chats').doc(user.uid)
      .collection('messages').get()).size;
  filesB += (await bucket.getFiles({prefix: `users/${user.uid}/`}))[0].length;
}
check('E24 durdurulan test yeni mesaj göndermez',
    run.get('status') === 'cancelled' && countB >= 2 && countB < 6 &&
    run.get('sentCount') === countB,
    `status=${run.get('status')} count=${countB} sent=${run.get('sentCount')}`);
check('E25 durdurmada yarım kalan gönderimin dosyası kalmaz',
    filesB === countB * 2, `files=${filesB} messages=${countB}`);
const firstB = usersB[0] ? usersB[0].uid : 'yok';
const firstBMessages = await db.collection('chats').doc(firstB)
    .collection('messages').get();
check('E26 kişi kişi: ilk kullanıcı fotoğraflarını art arda gönderir',
    firstBMessages.size >= 2, `size=${firstBMessages.size}`);

const RUN_C = 'RunCcccccccc3';
const MEALS = ['br', 'firstmid', 'lunch', 'secondmid', 'dinner', 'thirdmid'];
await prepareRun(RUN_C);
const burstStartedAt = Date.now();
res = await call('startChatLoadTest', ADMIN_UID, startData(RUN_C, {
  userCount: 30, photosPerUser: 10, gapSeconds: 0, startDelaySeconds: 0,
  slots: Array.from({length: 10}, (_, j) => ({
    photo: 0,
    meal: MEALS[j % MEALS.length],
    caption: `Öğün: ${j}`,
    summary: `Öğün Fotoğrafı (${j})`,
  })),
}));
check('E37 300 mesajlık aralıksız test başlar', res.status === 200 &&
    res.body.result.totalSteps === 300 && res.body.result.userCount === 30,
    `${res.status} ${JSON.stringify(res.body)}`);
run = await waitRun(RUN_C, (s) => s.get('status') === 'completed', 240000);
check('E38 aralıksız 300 mesajın hepsi gider',
    run.get('status') === 'completed' && run.get('sentCount') === 300 &&
    run.get('failedCount') === 0,
    `status=${run.get('status')} sent=${run.get('sentCount')} ` +
    `failed=${run.get('failedCount')} error=${run.get('lastError')} ` +
    `${Math.round((Date.now() - burstStartedAt) / 1000)} sn`);
const ticksC = await db.collection('chatLoadTests').doc(RUN_C)
    .collection('ticks').get();
check('E39 adım sınırında halka devredilir (0 ve 200)',
    JSON.stringify(ticksC.docs.map((d) => d.id).sort()) ===
    JSON.stringify(['c0_00000', 'c0_00200']),
    JSON.stringify(ticksC.docs.map((d) => d.id)));
let countC = 0;
let unreadOk = true;
for (const user of run.get('users') || []) {
  const [snap, chatC] = await Promise.all([
    db.collection('chats').doc(user.uid).collection('messages').get(),
    db.collection('chats').doc(user.uid).get(),
  ]);
  countC += snap.size;
  unreadOk = unreadOk && chatC.get('adminUnreadCount')[OFFICE_UID] === 10;
}
check('E40 her kullanıcıda 10 mesaj, okunmamış sayısı 10',
    countC === 300 && unreadOk, `count=${countC}`);

await db.collection('users').doc('gercekDanisan1').set({
  name: 'Gerçek', surname: 'Danışan', role: 'customer', isLoadTestUser: true,
});
await db.collection('chats').doc('gercekDanisan1').set({lastMessage: 'x'});
await admin.auth().createUser({uid: 'gercekDanisan1'});
await bucket.file('users/gercekDanisan1/mealPhotos/a.jpg')
    .save(THUMB, {resumable: false});

async function deleteTestUsers(runId, userCount) {
  const results = [];
  for (let i = 0; i < userCount; i++) {
    results.push(await call('deleteUserAccount', ADMIN_UID,
        {uid: core.testUserUid(runId, i)}));
  }
  return results;
}

async function leftovers(uid) {
  return {
    user: (await db.collection('users').doc(uid).get()).exists,
    chat: (await db.collection('chats').doc(uid).get()).exists,
    messages: (await db.collection('chats').doc(uid).collection('messages')
        .get()).size,
    meals: (await db.collection('users').doc(uid).collection('meals')
        .get()).size,
    auth: await admin.auth().getUser(uid).then(() => true, () => false),
    files: (await bucket.getFiles({prefix: `users/${uid}/`}))[0].length,
  };
}

const isGone = (l) => !l.user && !l.chat && l.messages === 0 &&
    l.meals === 0 && !l.auth && l.files === 0;

res = await call('cleanupChatLoadTests', 'musteri1', {runId: RUN_A});
check('E27 danışan test kayıtlarını silemez', res.status !== 200 &&
    JSON.stringify(res.body).includes('PERMISSION_DENIED'),
    `${res.status} ${JSON.stringify(res.body)}`);

await stopRun(RUN_A);
const deletedA = await deleteTestUsers(RUN_A, 3);
check('E28 test kullanıcıları mevcut deleteUserAccount ile silinir',
    deletedA.every((r) => r.status === 200 && r.body.result.success),
    JSON.stringify(deletedA.map((r) => r.status)));
await sleep(3000);
const leftA = await Promise.all(users.map((u) => leftovers(u.uid)));
check('E29 test kullanıcılarının hesabı, kayıtları, sohbeti ve fotoğrafları ' +
    'silinir; geri gelmez', leftA.every(isGone), JSON.stringify(leftA));

res = await call('cleanupChatLoadTests', ADMIN_UID, {runId: RUN_A});
check('E30 test kaydı silinir', res.status === 200 &&
    res.body.result.runs === 1, `${res.status} ${JSON.stringify(res.body)}`);
check('E31 test kaydı, tetiklemeleri ve kaynak fotoğraflar silinir',
    !(await db.collection('chatLoadTests').doc(RUN_A).get()).exists &&
    (await db.collection('chatLoadTests').doc(RUN_A).collection('ticks')
        .get()).size === 0 &&
    (await db.collection('chatLoadTests').doc(RUN_A).collection('control')
        .get()).size === 0 &&
    (await bucket.getFiles({prefix: `chatLoadTests/${RUN_A}/`}))[0]
        .length === 0);
check('E32 diğer testler duruyor',
    (await db.collection('chatLoadTests').doc(RUN_B).get()).exists &&
    (await db.collection('chatLoadTests').doc(RUN_C).get()).exists);

await stopRun(RUN_B);
await stopRun(RUN_C);
const deletedRest = [
  ...await deleteTestUsers(RUN_B, 2),
  ...await deleteTestUsers(RUN_C, 30),
];
check('E33 kalan test kullanıcıları silinir',
    deletedRest.every((r) => r.status === 200),
    JSON.stringify(deletedRest.filter((r) => r.status !== 200)));
res = await call('cleanupChatLoadTests', ADMIN_UID, {});
check('E34 bütün test kayıtları ve fotoğrafları silinir', res.status === 200 &&
    res.body.result.runs === 2 &&
    (await bucket.getFiles({prefix: 'chatLoadTests/'}))[0].length === 0 &&
    (await db.collection('chatLoadTests').get()).size === 0,
    `${res.status} ${JSON.stringify(res.body)}`);
await sleep(3000);
const leftRest = await Promise.all([
  ...usersB.map((u) => leftovers(u.uid)),
  ...Array.from({length: 30}, (_, i) =>
    leftovers(core.testUserUid(RUN_C, i))),
]);
check('E35 hiçbir test kullanıcısından iz kalmaz', leftRest.every(isGone),
    JSON.stringify(leftRest.filter((l) => !isGone(l))));
check('E36 gerçek kullanıcıya dokunulmaz',
    (await db.collection('users').doc('gercekDanisan1').get()).exists &&
    (await db.collection('chats').doc('gercekDanisan1').get()).exists &&
    await admin.auth().getUser('gercekDanisan1').then(() => true,
        () => false) &&
    await storageExists('users/gercekDanisan1/mealPhotos/a.jpg'));

res = await call('cleanupChatLoadTests', ADMIN_UID, {});
check('E41 temizlik tekrar çalıştırılabilir', res.status === 200 &&
    res.body.result.runs === 0, `${res.status} ${JSON.stringify(res.body)}`);

if (failures > 0) {
  console.error(`\n${failures} beklenti karşılanmadı`);
  process.exit(1);
}
console.log('\nTüm beklentiler karşılandı');
