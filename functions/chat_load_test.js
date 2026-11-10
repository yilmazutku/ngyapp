'use strict';

const crypto = require('crypto');
const admin = require('firebase-admin');
const {FieldValue, Timestamp} = require('firebase-admin/firestore');
const logger = require('firebase-functions/logger');
const {HttpsError} = require('firebase-functions/v2/https');

const RUNS_COLLECTION = 'chatLoadTests';
const TICKS_COLLECTION = 'ticks';
const CONTROL_COLLECTION = 'control';
const STOP_DOC = 'stop';
const FIRST_CHAIN = 'c0';

const LIMITS = Object.freeze({
  maxUsers: 100,
  maxPhotosPerUser: 10,
  maxSourcePhotos: 5,
  maxGapSeconds: 600,
  maxStartDelaySeconds: 600,
  maxDurationSeconds: 2 * 60 * 60,
  maxUtcOffsetMinutes: 14 * 60,
  maxTextLength: 100,
  maxFileNameLength: 120,
  maxImageSide: 20000,
});

const ORDERS = Object.freeze(['roundRobin', 'perUser']);

const STATUS = Object.freeze({
  preparing: 'preparing',
  creatingUsers: 'creatingUsers',
  running: 'running',
  completed: 'completed',
  cancelled: 'cancelled',
  failed: 'failed',
});

const MEAL_MAX_IMAGES = 10;
const MEAL_CHAT_MARKER_PREFIX = 'meals/';
const REMINDER_CANCELLED_FIELD = 'reminderCancelled';
const TEST_USER_UID_PREFIX = 'loadtest_';
const TEST_USER_EMAIL_DOMAIN = 'example.com';
const TEST_USER_SURNAME = 'Test';

const TEST_USER_NAMES = Object.freeze([
  'Ayşe', 'Fatma', 'Zeynep', 'Elif', 'Merve', 'Emine', 'Hatice', 'Büşra',
  'Esra', 'Selin', 'Deniz', 'Ece', 'Gizem', 'İrem', 'Sena', 'Melike',
  'Mehmet', 'Mustafa', 'Ahmet', 'Ali', 'Hüseyin', 'Hasan', 'Emre', 'Burak',
  'Can', 'Kerem', 'Oğuz', 'Serkan', 'Tolga', 'Umut', 'Volkan', 'Yusuf',
]);

const TICK_WINDOW_MS = 240000;
const HANDOFF_LEAD_MS = 45000;
const MAX_STEPS_PER_TICK = 200;
const SEND_CONCURRENCY = 16;
const SEND_TIMEOUT_MS = 90000;
const STATUS_CHECK_MS = 1000;
const FLUSH_DELAY_MS = 1000;
const FLUSH_ATTEMPTS = 3;
const HANDOFF_ATTEMPTS = 5;
const RETRY_DELAY_MS = 2000;
const USER_CREATE_CONCURRENCY = 10;
const FIRESTORE_BATCH_LIMIT = 400;
const ALREADY_EXISTS_CODE = 6;

const RUN_ID_PATTERN = /^[A-Za-z0-9]{8,40}$/;
const MEAL_NAME_PATTERN = /^[A-Za-z0-9]{1,30}$/;
const TEST_USER_UID_PATTERN = /^loadtest_[A-Za-z0-9]{8,40}_\d{3}$/;

/** Geçersiz yük testi isteği (invalid-argument olarak döner). */
class LoadTestInputError extends Error {}

/**
 * @param {string} message Kullanıcıya gösterilecek hata.
 */
function fail(message) {
  throw new LoadTestInputError(message);
}

/**
 * @param {*} value Değer.
 * @param {number} min En küçük.
 * @param {number} max En büyük.
 * @param {string} label Hatada geçen ad.
 * @return {number} Tam sayı.
 */
function requireInt(value, min, max, label) {
  if (!Number.isInteger(value) || value < min || value > max) {
    fail(`${label} ${min}-${max} arasında bir tam sayı olmalı.`);
  }
  return value;
}

/**
 * @param {*} value Değer.
 * @param {number} min En küçük.
 * @param {number} max En büyük.
 * @param {string} label Hatada geçen ad.
 * @return {number} Sayı.
 */
function requireNumber(value, min, max, label) {
  if (typeof value !== 'number' || !Number.isFinite(value) ||
      value < min || value > max) {
    fail(`${label} ${min}-${max} arasında olmalı.`);
  }
  return value;
}

/**
 * @param {*} value Değer.
 * @param {number} maxLength En uzun.
 * @param {string} label Hatada geçen ad.
 * @return {string} Boş olmayan metin.
 */
function requireText(value, maxLength, label) {
  if (typeof value !== 'string' || value.trim() === '' ||
      value.length > maxLength) {
    fail(`${label} geçersiz.`);
  }
  return value;
}

/**
 * @param {string} runId Çalıştırma kimliği.
 * @return {string} Kaynak fotoğrafların Storage klasörü (sonunda /).
 */
function stagingFolderOf(runId) {
  return `${RUNS_COLLECTION}/${runId}/`;
}

/**
 * @param {*} value Storage yolu.
 * @param {string} folder Yolun içinde olması gereken klasör.
 * @param {string} label Hatada geçen ad.
 * @return {string} Yol.
 */
function requireStagingPath(value, folder, label) {
  if (typeof value !== 'string' || !value.startsWith(folder) ||
      value.length > folder.length + 300 || value.includes('..') ||
      value.endsWith('/') || value.length === folder.length) {
    fail(`${label} geçersiz.`);
  }
  return value;
}

/**
 * @param {*} value Fotoğrafın piksel ölçüsü (yoksa null).
 * @param {string} label Hatada geçen ad.
 * @return {?number} Ölçü.
 */
function optionalSide(value, label) {
  if (value === null || value === undefined) return null;
  return requireInt(value, 1, LIMITS.maxImageSide, label);
}

/**
 * @param {*} raw İstekteki fotoğraf.
 * @param {number} index Sırası.
 * @param {string} folder Kaynak klasörü.
 * @return {object} Doğrulanmış kaynak fotoğraf.
 */
function parsePhoto(raw, index, folder) {
  const photo = raw && typeof raw === 'object' ? raw : {};
  const label = `${index + 1}. fotoğraf`;
  const fileName = requireText(
      photo.fileName, LIMITS.maxFileNameLength, `${label} adı`);
  if (fileName.startsWith('.') || /[/\\]/.test(fileName) ||
      [...fileName].some((char) => char.charCodeAt(0) < 32)) {
    fail(`${label} adı geçersiz.`);
  }
  const thumbPath = photo.thumbPath === null || photo.thumbPath === undefined ?
      null :
      requireStagingPath(photo.thumbPath, folder, `${label} küçük görseli`);
  const width = optionalSide(photo.width, `${label} genişliği`);
  const height = optionalSide(photo.height, `${label} yüksekliği`);
  return {
    path: requireStagingPath(photo.path, folder, label),
    fileName,
    thumbPath,
    width: width !== null && height !== null ? width : null,
    height: width !== null && height !== null ? height : null,
  };
}

/**
 * @param {*} raw İstekteki fotoğraf sırası.
 * @param {number} index Sırası.
 * @param {number} photoCount Kaynak fotoğraf sayısı.
 * @return {object} Doğrulanmış sıra: hangi fotoğraf, hangi öğün.
 */
function parseSlot(raw, index, photoCount) {
  const slot = raw && typeof raw === 'object' ? raw : {};
  const label = `${index + 1}. sıra`;
  const meal = slot.meal;
  if (typeof meal !== 'string' || !MEAL_NAME_PATTERN.test(meal)) {
    fail(`${label} öğünü geçersiz.`);
  }
  return {
    photo: requireInt(slot.photo, 0, photoCount - 1, `${label} fotoğrafı`),
    meal,
    caption: requireText(slot.caption, LIMITS.maxTextLength,
        `${label} açıklaması`),
    summary: requireText(slot.summary, LIMITS.maxTextLength,
        `${label} özeti`),
  };
}

/**
 * startChatLoadTest isteğini doğrular.
 * @param {*} data Callable verisi.
 * @return {object} Doğrulanmış istek.
 */
function parseStartRequest(data) {
  const input = data && typeof data === 'object' ? data : {};
  const runId = input.runId;
  if (typeof runId !== 'string' || !RUN_ID_PATTERN.test(runId)) {
    fail('Test kimliği geçersiz.');
  }
  const userCount =
      requireInt(input.userCount, 1, LIMITS.maxUsers, 'Kullanıcı sayısı');
  const photosPerUser = requireInt(input.photosPerUser, 1,
      LIMITS.maxPhotosPerUser, 'Kişi başı fotoğraf');
  const gapSeconds = requireNumber(input.gapSeconds, 0, LIMITS.maxGapSeconds,
      'Mesajlar arası süre');
  const startDelaySeconds = requireInt(input.startDelaySeconds, 0,
      LIMITS.maxStartDelaySeconds, 'Başlama gecikmesi');
  if (!ORDERS.includes(input.order)) fail('Gönderim sırası geçersiz.');
  const utcOffsetMinutes = requireInt(input.utcOffsetMinutes,
      -LIMITS.maxUtcOffsetMinutes, LIMITS.maxUtcOffsetMinutes, 'Saat dilimi');

  const folder = stagingFolderOf(runId);
  if (!Array.isArray(input.photos) || input.photos.length === 0 ||
      input.photos.length > LIMITS.maxSourcePhotos) {
    fail(`1-${LIMITS.maxSourcePhotos} fotoğraf seçilmeli.`);
  }
  const photos = input.photos.map((raw, i) => parsePhoto(raw, i, folder));
  if (!Array.isArray(input.slots) || input.slots.length !== photosPerUser) {
    fail('Fotoğraf sırası kişi başı fotoğraf sayısıyla aynı olmalı.');
  }
  const slots =
      input.slots.map((raw, i) => parseSlot(raw, i, photos.length));

  const totalSteps = userCount * photosPerUser;
  const gapMs = Math.round(gapSeconds * 1000);
  if ((totalSteps - 1) * gapMs / 1000 + startDelaySeconds >
      LIMITS.maxDurationSeconds) {
    fail(`Test en fazla ${LIMITS.maxDurationSeconds / 3600} saat sürebilir.`);
  }

  return {
    runId,
    userCount,
    photosPerUser,
    gapSeconds,
    gapMs,
    startDelaySeconds,
    order: input.order,
    utcOffsetMinutes,
    photos,
    slots,
    totalSteps,
  };
}

/**
 * @param {number} step Adım (0'dan).
 * @param {number} userCount Kullanıcı sayısı.
 * @param {number} photosPerUser Kişi başı fotoğraf.
 * @param {string} order roundRobin ya da perUser.
 * @return {{user: number, slot: number}} Gönderen ve fotoğraf sırası.
 */
function stepPosition(step, userCount, photosPerUser, order) {
  if (order === 'perUser') {
    return {
      user: Math.floor(step / photosPerUser),
      slot: step % photosPerUser,
    };
  }
  return {user: step % userCount, slot: Math.floor(step / userCount)};
}

/**
 * @param {number} startAtMs İlk mesajın zamanı.
 * @param {number} gapMs Mesajlar arası süre.
 * @param {number} step Adım.
 * @return {number} Adımın gönderileceği an.
 */
function stepTimeMs(startAtMs, gapMs, step) {
  return startAtMs + step * gapMs;
}

/**
 * Bir tetiklemenin göndereceği adımlar [fromIndex, until) ve sonraki
 * tetiklemenin ne zaman açılacağı (son adımdaysa null).
 * @param {object} p Girdi.
 * @return {{until: number, handoffAtMs: ?number}} Plan.
 */
function planTick(p) {
  const windowEnd = p.nowMs + p.windowMs;
  let until = Math.max(0, p.fromIndex);
  while (until < p.totalSteps && until - p.fromIndex < p.maxSteps &&
      stepTimeMs(p.startAtMs, p.gapMs, until) < windowEnd) {
    until++;
  }
  if (until >= p.totalSteps) return {until: p.totalSteps, handoffAtMs: null};
  const nextAt = stepTimeMs(p.startAtMs, p.gapMs, until);
  return {
    until,
    handoffAtMs: Math.min(Math.max(p.nowMs, nextAt - p.leadMs), windowEnd),
  };
}

/**
 * @param {string} runId Çalıştırma kimliği.
 * @param {number} index Kullanıcının sırası (0'dan).
 * @return {string} Test kullanıcısının UID'si.
 */
function testUserUid(runId, index) {
  const number = String(index + 1).padStart(3, '0');
  return `${TEST_USER_UID_PREFIX}${runId}_${number}`;
}

/**
 * @param {string} uid UID.
 * @param {string} runId Çalıştırma kimliği.
 * @return {boolean} Bu çalıştırmanın test kullanıcısı mı.
 */
function isTestUserUidOf(uid, runId) {
  return typeof uid === 'string' && TEST_USER_UID_PATTERN.test(uid) &&
      uid.startsWith(`${TEST_USER_UID_PREFIX}${runId}_`);
}

/**
 * @param {string} runId Çalıştırma kimliği.
 * @param {number} index Kullanıcının sırası.
 * @param {function(): number} random 0-1 arası rastgele sayı.
 * @return {{name: string, surname: string, email: string}} Profil.
 */
function testUserProfile(runId, index, random) {
  const number = String(index + 1).padStart(2, '0');
  const name =
      TEST_USER_NAMES[Math.floor(random() * TEST_USER_NAMES.length)];
  return {
    name,
    surname: `${TEST_USER_SURNAME} ${number}`,
    email: `loadtest.${runId.toLowerCase()}.${number}@` +
        TEST_USER_EMAIL_DOMAIN,
  };
}

/**
 * @param {string} runId Çalıştırma kimliği.
 * @param {number} step Adım.
 * @return {string} Mesaj kimliği; aynı adım iki kez yazılmaz.
 */
function messageIdOf(runId, step) {
  return `${TEST_USER_UID_PREFIX}${runId}_${String(step).padStart(4, '0')}`;
}

/**
 * @param {string} chain Zincir.
 * @param {number} fromIndex İlk adım.
 * @return {string} Tetikleme dokümanının kimliği.
 */
function tickIdOf(chain, fromIndex) {
  return `${chain}_${String(fromIndex).padStart(5, '0')}`;
}

/**
 * @param {number} ms An.
 * @param {number} utcOffsetMinutes Cihazın saat dilimi farkı.
 * @return {string} Cihazın takvimine göre gün (yyyy-MM-dd).
 */
function dateKeyOf(ms, utcOffsetMinutes) {
  return new Date(ms + utcOffsetMinutes * 60000).toISOString().slice(0, 10);
}

/**
 * @param {string} path Dosya yolu ya da adı.
 * @return {string} Uzantı (noktayla) ya da boş.
 */
function extensionOf(path) {
  const name = path.slice(path.lastIndexOf('/') + 1);
  const dot = name.lastIndexOf('.');
  return dot > 0 ? name.slice(dot) : '';
}

/**
 * Uygulamadaki thumbnailRefFor ile aynı ad: `<ad>_thumb<uzantı>`.
 * @param {string} originalName Asıl dosyanın adı.
 * @param {string} thumbExtension Küçük görselin uzantısı.
 * @return {string} Küçük görselin adı.
 */
function thumbnailNameFor(originalName, thumbExtension) {
  const dot = originalName.lastIndexOf('.');
  const base = dot > 0 ? originalName.slice(0, dot) : originalName;
  return `${base}_thumb${thumbExtension}`;
}

/**
 * @param {string} bucketName Kova.
 * @param {string} path Dosya yolu.
 * @param {string} token İndirme jetonu.
 * @param {string|undefined} emulatorHost Storage emülatörü (varsa).
 * @return {string} İstemci SDK'sının verdiği biçimde indirme adresi.
 */
function downloadUrlOf(bucketName, path, token, emulatorHost) {
  const base = emulatorHost ?
      `http://${emulatorHost}` : 'https://firebasestorage.googleapis.com';
  return `${base}/v0/b/${bucketName}/o/${encodeURIComponent(path)}` +
      `?alt=media&token=${token}`;
}

/**
 * @param {*} value Değer.
 * @return {boolean} Firestore zaman damgası mı.
 */
function isTimestamp(value) {
  return !!value && typeof value.toMillis === 'function';
}

/**
 * Öğün kaydına fotoğraf ekler (uygulamadaki mealWithImageAdded ve
 * MealModel.toMap ile aynı biçim).
 * @param {?object} current Kaydın şimdiki hâli.
 * @param {object} image Eklenecek fotoğraf.
 * @return {{kind: string, doc: ?object}} written, already ya da limit.
 */
function mealEntryWithImage(current, image) {
  const data = current || null;
  let urls = [];
  if (data && Array.isArray(data.imageUrls)) {
    urls = data.imageUrls.filter((url) => typeof url === 'string');
  } else if (data && typeof data.imageUrl === 'string' && data.imageUrl) {
    urls = [data.imageUrl];
  }
  if (urls.includes(image.imageUrl)) return {kind: 'already', doc: null};
  if (urls.length >= MEAL_MAX_IMAGES) return {kind: 'limit', doc: null};

  const thumbs = Array.isArray(data && data.thumbUrls) ? data.thumbUrls : [];
  const times = Array.isArray(data && data.imageTimes) ? data.imageTimes : [];
  const fallbackTime =
      data && isTimestamp(data.timestamp) ? data.timestamp : image.time;
  const imageUrls = [...urls, image.imageUrl];
  return {
    kind: 'written',
    doc: {
      mealType: image.meal,
      imageUrls,
      thumbUrls: [
        ...urls.map((_, i) => typeof thumbs[i] === 'string' ? thumbs[i] : ''),
        image.thumbUrl || '',
      ],
      imageTimes: [
        ...urls.map((_, i) => isTimestamp(times[i]) ? times[i] : fallbackTime),
        image.time,
      ],
      imageUrl: imageUrls[0],
      subscriptionId: image.subscriptionId,
      description: data ? (data.description ?? null) : null,
      timestamp: image.time,
      calories: data ? (data.calories ?? null) : null,
      notes: data ? (data.notes ?? null) : null,
      isChecked: true,
      createDate: image.time,
    },
  };
}

/**
 * @param {number} ms Süre.
 * @return {Promise<void>} Süre dolunca.
 */
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, Math.max(0, ms)));
}

/**
 * [items] için [task]'ı en fazla [concurrency] tanesi aynı anda olacak
 * şekilde çalıştırır; ilk hata fırlatılır (diğerleri biter).
 * @param {Array} items Öğeler.
 * @param {number} concurrency Aynı anda en fazla.
 * @param {function(*): Promise} task İş.
 * @return {Promise<Array>} Sonuçlar.
 */
async function mapWithConcurrency(items, concurrency, task) {
  const results = new Array(items.length);
  let next = 0;
  let firstError = null;
  const worker = async () => {
    while (next < items.length) {
      const index = next++;
      try {
        results[index] = await task(items[index]);
      } catch (e) {
        if (!firstError) firstError = e;
      }
    }
  };
  await Promise.all(Array.from(
      {length: Math.min(concurrency, items.length)}, worker));
  if (firstError) throw firstError;
  return results;
}

/**
 * @param {*} error Hata.
 * @return {string} Kısa hata metni.
 */
function errorText(error) {
  const message = error && error.message ? error.message : String(error);
  return message.length > 300 ? `${message.slice(0, 300)}…` : message;
}

/**
 * Callable: test kullanıcılarını oluşturur ve mesaj zincirini başlatır.
 * Çalıştırma dokümanını ve kaynak fotoğrafları uygulama önceden yazar.
 * @param {*} data İstek.
 * @param {string} callerUid Çağıran admin.
 * @return {Promise<object>} Başlayan testin özeti.
 */
async function startLoadTest(data, callerUid) {
  let request;
  try {
    request = parseStartRequest(data);
  } catch (e) {
    if (e instanceof LoadTestInputError) {
      throw new HttpsError('invalid-argument', e.message);
    }
    throw e;
  }

  const db = admin.firestore();
  const runRef = db.collection(RUNS_COLLECTION).doc(request.runId);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(runRef);
    if (!snap.exists || snap.get('status') !== STATUS.preparing) {
      throw new HttpsError('failed-precondition',
          'Test hazırlık aşamasında değil; yeniden başlatın.');
    }
    tx.update(runRef, {
      status: STATUS.creatingUsers,
      startedBy: callerUid,
      userCount: request.userCount,
      photosPerUser: request.photosPerUser,
      totalSteps: request.totalSteps,
      gapSeconds: request.gapSeconds,
      startDelaySeconds: request.startDelaySeconds,
      order: request.order,
      utcOffsetMinutes: request.utcOffsetMinutes,
      photos: request.photos,
      slots: request.slots,
    });
  });

  let users;
  try {
    users = await createTestUsers(db, request, callerUid);
  } catch (e) {
    logger.error('Load test users could not be created', {
      runId: request.runId,
      error: errorText(e),
    });
    await runRef.update({
      status: STATUS.failed,
      lastError: `Test kullanıcıları oluşturulamadı: ${errorText(e)}`,
      finishedAt: FieldValue.serverTimestamp(),
    }).catch(() => {});
    throw new HttpsError('internal',
        'Test kullanıcıları oluşturulamadı. Temizleyip yeniden deneyin.');
  }

  const startAtMs = Date.now() + request.startDelaySeconds * 1000;
  const started = await db.runTransaction(async (tx) => {
    const snap = await tx.get(runRef);
    if (!snap.exists || snap.get('status') !== STATUS.creatingUsers) {
      return false;
    }
    tx.update(runRef, {
      status: STATUS.running,
      users,
      startAt: Timestamp.fromMillis(startAtMs),
      sentCount: 0,
      failedCount: 0,
      heartbeatAt: FieldValue.serverTimestamp(),
    });
    tx.create(runRef.collection(TICKS_COLLECTION)
        .doc(tickIdOf(FIRST_CHAIN, 0)), {
      chain: FIRST_CHAIN,
      fromIndex: 0,
      createdAt: FieldValue.serverTimestamp(),
    });
    return true;
  });
  if (!started) {
    throw new HttpsError('aborted', 'Test başlatılırken durduruldu; ' +
        'oluşturulan test kullanıcıları temizlikte silinir.');
  }

  logger.info('Load test started', {
    runId: request.runId,
    users: users.length,
    steps: request.totalSteps,
  });
  return {
    runId: request.runId,
    userCount: users.length,
    totalSteps: request.totalSteps,
    startAtMs,
  };
}

/**
 * Auth hesaplarını ve kullanıcı dokümanlarını (danışan olarak) açar. UID'ler
 * çalıştırmadan türetilir: yarıda kalsa da temizlik hepsini bulur.
 * @param {admin.firestore.Firestore} db Firestore.
 * @param {object} request Doğrulanmış istek.
 * @param {string} callerUid Çağıran admin.
 * @return {Promise<Array<{uid: string, name: string}>>} Kullanıcılar.
 */
async function createTestUsers(db, request, callerUid) {
  const users = [];
  for (let i = 0; i < request.userCount; i++) {
    users.push({
      uid: testUserUid(request.runId, i),
      ...testUserProfile(request.runId, i, Math.random),
    });
  }

  await mapWithConcurrency(users, USER_CREATE_CONCURRENCY, async (user) => {
    try {
      await admin.auth().createUser({
        uid: user.uid,
        displayName: `${user.name} ${user.surname}`,
      });
    } catch (e) {
      if (e.code !== 'auth/uid-already-exists') throw e;
    }
  });

  const createDate = Timestamp.now();
  for (let i = 0; i < users.length; i += FIRESTORE_BATCH_LIMIT) {
    const batch = db.batch();
    for (const user of users.slice(i, i + FIRESTORE_BATCH_LIMIT)) {
      batch.set(db.collection('users').doc(user.uid), {
        userId: user.uid,
        name: user.name,
        surname: user.surname,
        email: user.email,
        role: 'customer',
        createDate,
        createUser: callerUid,
        medicationsAndConditions: null,
        isLoadTestUser: true,
        loadTestRunId: request.runId,
      });
    }
    await batch.commit();
  }

  return users.map((user) => ({
    uid: user.uid,
    name: `${user.name} ${user.surname}`,
  }));
}

/**
 * Bir tetiklemenin bağlamı: çalıştırma, ilerleme sayaçları, kaynak
 * fotoğrafların baytları.
 * @param {admin.firestore.Firestore} db Firestore.
 * @param {admin.firestore.DocumentReference} runRef Çalıştırma.
 * @param {object} run Çalıştırmanın verisi.
 * @param {string[]} officeUids Sohbet ofisi.
 * @return {object} Bağlam.
 */
function createTickContext(db, runRef, run, officeUids) {
  const bucket = admin.storage().bucket();
  const sources = new Map();
  let stopped = false;
  let checkedAtMs = 0;

  const source = (path) => {
    if (!sources.has(path)) {
      const file = bucket.file(path);
      const loading = Promise.all([file.download(), file.getMetadata()])
          .then(([[bytes], [metadata]]) => ({
            bytes,
            contentType: metadata.contentType || 'image/jpeg',
          }));
      loading.catch(() => sources.delete(path));
      sources.set(path, loading);
    }
    return sources.get(path);
  };

  const isStopped = async (force) => {
    if (!force && Date.now() - checkedAtMs < STATUS_CHECK_MS) return stopped;
    try {
      const snap = await runRef.get();
      stopped = !snap.exists || snap.get('status') !== STATUS.running;
    } catch (e) {
      logger.warn('Load test status read failed', {error: errorText(e)});
    }
    checkedAtMs = Date.now();
    return stopped;
  };

  return {
    db,
    bucket,
    runRef,
    runId: runRef.id,
    run,
    officeUids,
    gapMs: Math.round((run.gapSeconds || 0) * 1000),
    startAtMs: run.startAt.toMillis(),
    source,
    isStopped,
    progress: createProgress(db, runRef),
  };
}

/**
 * Gönderim sonuçlarını toplar ve çalıştırmaya en fazla saniyede bir yazar;
 * gönderilen ve başarısız toplamı adım sayısına ulaşınca test tamamlanır.
 * @param {admin.firestore.Firestore} db Firestore.
 * @param {admin.firestore.DocumentReference} runRef Çalıştırma.
 * @return {object} record ve close.
 */
function createProgress(db, runRef) {
  let sent = 0;
  let failed = 0;
  let lastError = null;
  let timer = null;
  let chain = Promise.resolve();

  const writeOnce = async () => {
    const deltaSent = sent;
    const deltaFailed = failed;
    const error = lastError;
    if (deltaSent === 0 && deltaFailed === 0) return true;
    sent = 0;
    failed = 0;
    lastError = null;
    try {
      await db.runTransaction(async (tx) => {
        const snap = await tx.get(runRef);
        if (!snap.exists) return;
        const sentCount = (snap.get('sentCount') || 0) + deltaSent;
        const failedCount = (snap.get('failedCount') || 0) + deltaFailed;
        const update = {
          sentCount,
          failedCount,
          heartbeatAt: FieldValue.serverTimestamp(),
        };
        if (error) update.lastError = error;
        if (snap.get('status') === STATUS.running &&
            sentCount + failedCount >= (snap.get('totalSteps') || 0)) {
          update.status = STATUS.completed;
          update.finishedAt = FieldValue.serverTimestamp();
        }
        tx.update(runRef, update);
      });
      return true;
    } catch (e) {
      sent += deltaSent;
      failed += deltaFailed;
      lastError = lastError || error;
      logger.warn('Load test progress write failed', {error: errorText(e)});
      return false;
    }
  };

  const flush = () => {
    chain = chain.then(writeOnce);
    return chain;
  };

  return {
    record(outcome, error) {
      if (outcome === 'written') {
        sent++;
      } else if (outcome !== 'duplicate' && outcome !== 'stopped') {
        failed++;
        lastError = error;
      }
      if (!timer) {
        timer = setTimeout(() => {
          timer = null;
          flush();
        }, FLUSH_DELAY_MS);
      }
    },
    async close() {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
      for (let attempt = 0; attempt < FLUSH_ATTEMPTS; attempt++) {
        if (await flush()) return;
        await sleep(RETRY_DELAY_MS);
      }
    },
  };
}

/**
 * Bir test mesajını gönderir: fotoğrafı ve küçük görseli kullanıcının öğün
 * klasörüne yükler, öğün kaydını, sohbet özetini ve mesajı uygulamanın
 * sohbetten yüklemesiyle aynı işlemde yazar.
 * @param {object} ctx Tetikleme bağlamı.
 * @param {number} step Adım.
 * @return {Promise<string>} written, duplicate, stopped, limit ya da
 *     userGone.
 */
async function sendLoadTestStep(ctx, step) {
  const {db, bucket, run, runId, officeUids} = ctx;
  const position =
      stepPosition(step, run.userCount, run.photosPerUser, run.order);
  const user = run.users[position.user];
  const slot = run.slots[position.slot];
  const photo = run.photos[slot.photo];
  const uid = user.uid;

  const userRef = db.collection('users').doc(uid);
  const stopRef = ctx.runRef.collection(CONTROL_COLLECTION).doc(STOP_DOC);
  const chatRef = db.collection('chats').doc(uid);
  const messageRef =
      chatRef.collection('messages').doc(messageIdOf(runId, step));
  if ((await messageRef.get()).exists) return 'duplicate';

  const nowMs = Date.now();
  const dateKey = dateKeyOf(nowMs, run.utcOffsetMinutes || 0);
  const dayRef = userRef.collection('meals').doc(dateKey);
  const mealRef = dayRef.collection('mealEntries').doc(slot.meal);
  const folder = `users/${uid}/mealPhotos/${dateKey}/${slot.meal}`;
  const originalName = `${nowMs}_${photo.fileName}`;
  const uploaded = [];

  const save = async (sourcePath, name) => {
    const {bytes, contentType} = await ctx.source(sourcePath);
    const path = `${folder}/${name}`;
    const token = crypto.randomUUID();
    await bucket.file(path).save(bytes, {
      resumable: false,
      metadata: {
        contentType,
        metadata: {firebaseStorageDownloadTokens: token},
      },
    });
    uploaded.push(path);
    return downloadUrlOf(bucket.name, path, token,
        process.env.FIREBASE_STORAGE_EMULATOR_HOST);
  };

  const imageUrl = await save(photo.path, originalName);
  const thumbUrl = photo.thumbPath ? await save(photo.thumbPath,
      thumbnailNameFor(originalName, extensionOf(photo.thumbPath))) : null;

  const message = {
    chatId: uid,
    senderId: uid,
    text: slot.caption,
    imageUrl,
    storagePath: `${MEAL_CHAT_MARKER_PREFIX}${uid}/${slot.meal}`,
    createdAt: FieldValue.serverTimestamp(),
    clientCreatedAt: Timestamp.fromMillis(nowMs),
    loadTestRunId: runId,
  };
  if (thumbUrl) message.thumbUrl = thumbUrl;
  if (photo.width && photo.height) {
    message.imageWidth = photo.width;
    message.imageHeight = photo.height;
  }

  const outcome = await db.runTransaction(async (tx) => {
    const [stopSnap, userSnap, mealSnap, messageSnap] =
        await tx.getAll(stopRef, userRef, mealRef, messageRef);
    if (stopSnap.exists) return 'stopped';
    if (!userSnap.exists) return 'userGone';
    if (messageSnap.exists) return 'duplicate';
    const entry = mealEntryWithImage(mealSnap.exists ? mealSnap.data() : null, {
      meal: slot.meal,
      subscriptionId: uid,
      imageUrl,
      thumbUrl,
      time: Timestamp.fromMillis(nowMs),
    });
    if (entry.kind === 'limit') return 'limit';
    if (entry.kind !== 'written') return 'duplicate';

    tx.set(mealRef, entry.doc);
    tx.set(dayRef, {
      meals: {[slot.meal]: true},
      [REMINDER_CANCELLED_FIELD]: {[slot.meal]: true},
    }, {merge: true});
    tx.set(chatRef, {
      participants: [uid, ...officeUids],
      lastMessage: slot.summary,
      lastImageUrl: imageUrl,
      lastImageThumbUrl: thumbUrl || '',
      lastMessageAt: Timestamp.now(),
      updatedAt: FieldValue.serverTimestamp(),
      adminUnreadCount: Object.fromEntries(
          officeUids.map((officeUid) => [officeUid, FieldValue.increment(1)])),
      hasUnreadFor: FieldValue.arrayUnion(...officeUids),
    }, {merge: true});
    tx.set(messageRef, message);
    return 'written';
  });

  if (outcome !== 'written') {
    await Promise.all(uploaded.map(
        (path) => bucket.file(path).delete().catch(() => {})));
  }
  return outcome;
}

/**
 * Adımı süre sınırıyla gönderir ve sonucu sayar; hiçbir zaman hata
 * fırlatmaz.
 * @param {object} ctx Tetikleme bağlamı.
 * @param {number} step Adım.
 * @return {Promise<void>} Sonuç sayılınca.
 */
async function sendStepAndRecord(ctx, step) {
  let timer = null;
  const timeout = new Promise((resolve) => {
    timer = setTimeout(() => resolve({outcome: 'timeout'}), SEND_TIMEOUT_MS);
  });
  const send = sendLoadTestStep(ctx, step).then(
      (outcome) => ({outcome}),
      (error) => ({outcome: 'error', error}));
  const result = await Promise.race([send, timeout]);
  clearTimeout(timer);

  switch (result.outcome) {
    case 'written':
    case 'duplicate':
    case 'stopped':
      ctx.progress.record(result.outcome, null);
      return;
    case 'timeout':
      ctx.progress.record('failed', `${step + 1}. mesaj zaman aşımına uğradı.`);
      return;
    case 'limit':
      ctx.progress.record('failed', 'Öğünün fotoğraf sınırı doldu.');
      return;
    case 'userGone':
      ctx.progress.record('failed', 'Test kullanıcısı silinmiş.');
      return;
    default:
      logger.warn('Load test message failed', {
        runId: ctx.runId,
        step,
        error: errorText(result.error),
      });
      ctx.progress.record('failed',
          `${step + 1}. mesaj gönderilemedi: ${errorText(result.error)}`);
  }
}

/**
 * Adımları zamanı gelince gönderir; aynı anda en fazla SEND_CONCURRENCY
 * gönderim sürer. Test durdurulursa yeni adım başlatılmaz.
 * @param {object} ctx Tetikleme bağlamı.
 * @param {number} from İlk adım.
 * @param {number} until Son adımdan sonraki.
 * @return {Promise<void>} Başlatılan gönderimler bitince.
 */
async function dispatchSteps(ctx, from, until) {
  const pending = new Set();
  for (let step = from; step < until; step++) {
    await sleep(stepTimeMs(ctx.startAtMs, ctx.gapMs, step) - Date.now());
    if (await ctx.isStopped(false)) break;
    while (pending.size >= SEND_CONCURRENCY) await Promise.race(pending);
    const sending = sendStepAndRecord(ctx, step)
        .finally(() => pending.delete(sending));
    pending.add(sending);
  }
  await Promise.all(pending);
}

/**
 * Sonraki tetiklemeyi açar (zincirin devamı). Aynı kimlik ikinci kez
 * açılmaz; geçici hatalarda yeniden denenir.
 * @param {object} ctx Tetikleme bağlamı.
 * @param {string} chain Zincir.
 * @param {number} fromIndex Sonraki tetiklemenin ilk adımı.
 * @param {number} atMs Ne zaman açılacağı.
 * @return {Promise<void>} Açılınca (ya da gerek kalmayınca).
 */
async function handOff(ctx, chain, fromIndex, atMs) {
  await sleep(atMs - Date.now());
  const tickRef = ctx.runRef.collection(TICKS_COLLECTION)
      .doc(tickIdOf(chain, fromIndex));
  for (let attempt = 1; attempt <= HANDOFF_ATTEMPTS; attempt++) {
    if (await ctx.isStopped(true)) return;
    try {
      await tickRef.create({
        chain,
        fromIndex,
        createdAt: FieldValue.serverTimestamp(),
      });
      return;
    } catch (e) {
      if (e.code === ALREADY_EXISTS_CODE) return;
      logger.warn('Load test hand-off failed', {
        runId: ctx.runId,
        fromIndex,
        attempt,
        error: errorText(e),
      });
      if (attempt === HANDOFF_ATTEMPTS) {
        await ctx.runRef.update({
          lastError: `Test zinciri ${fromIndex + 1}. mesajda durdu: ` +
              errorText(e),
        }).catch(() => {});
        return;
      }
      await sleep(RETRY_DELAY_MS * attempt);
    }
  }
}

/**
 * Firestore tetiklemesi: zincirin bir halkası. Kendi adımlarını gönderir,
 * sıradaki halkayı ilk adımından önce açar.
 * @param {string} runId Çalıştırma kimliği.
 * @param {object} tick Tetikleme dokümanının verisi.
 * @param {string[]} officeUids Sohbet ofisi.
 * @return {Promise<void>} Halka bitince.
 */
async function runLoadTestTick(runId, tick, officeUids) {
  const db = admin.firestore();
  const runRef = db.collection(RUNS_COLLECTION).doc(runId);
  const runSnap = await runRef.get();
  if (!runSnap.exists || runSnap.get('status') !== STATUS.running) return;
  const run = runSnap.data();
  if (!isTimestamp(run.startAt) || !Array.isArray(run.users) ||
      !Array.isArray(run.slots) || !Array.isArray(run.photos) ||
      !run.users.every((user) => user && isTestUserUidOf(user.uid, runId))) {
    logger.error('Load test run is malformed', {runId});
    return;
  }

  const chain = typeof tick.chain === 'string' && tick.chain ?
      tick.chain : FIRST_CHAIN;
  const fromIndex = Number.isInteger(tick.fromIndex) && tick.fromIndex >= 0 ?
      tick.fromIndex : 0;
  const ctx = createTickContext(db, runRef, run, officeUids);
  const plan = planTick({
    fromIndex,
    totalSteps: run.totalSteps,
    startAtMs: ctx.startAtMs,
    gapMs: ctx.gapMs,
    nowMs: Date.now(),
    windowMs: TICK_WINDOW_MS,
    maxSteps: MAX_STEPS_PER_TICK,
    leadMs: HANDOFF_LEAD_MS,
  });

  await runRef.update({heartbeatAt: FieldValue.serverTimestamp()})
      .catch(() => {});
  const handoff = plan.handoffAtMs === null ? Promise.resolve() :
      handOff(ctx, chain, plan.until, plan.handoffAtMs);
  try {
    await dispatchSteps(ctx, fromIndex, plan.until);
  } finally {
    await handoff;
    await ctx.progress.close();
  }
}

/**
 * Callable: test kaynak fotoğraflarını (Storage) ve test kayıtlarını
 * (çalıştırma, tetikleme ve dur kayıtları) siler; verilen çalıştırmanınkini ya
 * da runId yoksa hepsini. Kullanıcılara ve sohbetlere dokunmaz: test
 * kullanıcıları uygulamadaki kullanıcı silme işleviyle (deleteUserAccount)
 * silinir. Tekrar çalıştırılabilir.
 * @param {*} data İstek ({runId?}).
 * @return {Promise<{runs: number}>} Silinen çalıştırma sayısı.
 */
async function cleanupLoadTests(data) {
  const runId = data && data.runId !== undefined && data.runId !== null ?
      data.runId : null;
  if (runId !== null &&
      (typeof runId !== 'string' || !RUN_ID_PATTERN.test(runId))) {
    throw new HttpsError('invalid-argument', 'Test kimliği geçersiz.');
  }

  const db = admin.firestore();
  const bucket = admin.storage().bucket();
  const runRefs = runId !== null ?
      [db.collection(RUNS_COLLECTION).doc(runId)] :
      await db.collection(RUNS_COLLECTION).listDocuments();

  for (const runRef of runRefs) {
    await bucket.deleteFiles({prefix: stagingFolderOf(runRef.id)});
    await db.recursiveDelete(runRef);
  }
  if (runId === null) {
    await bucket.deleteFiles({prefix: `${RUNS_COLLECTION}/`});
  }

  logger.info('Load test records cleaned up', {runId, runs: runRefs.length});
  return {runs: runRefs.length};
}

module.exports = {
  LIMITS,
  STATUS,
  RUNS_COLLECTION,
  TICKS_COLLECTION,
  CONTROL_COLLECTION,
  STOP_DOC,
  FIRST_CHAIN,
  LoadTestInputError,
  parseStartRequest,
  stepPosition,
  stepTimeMs,
  planTick,
  testUserUid,
  isTestUserUidOf,
  testUserProfile,
  messageIdOf,
  tickIdOf,
  dateKeyOf,
  extensionOf,
  thumbnailNameFor,
  downloadUrlOf,
  mealEntryWithImage,
  mapWithConcurrency,
  startLoadTest,
  runLoadTestTick,
  cleanupLoadTests,
};
