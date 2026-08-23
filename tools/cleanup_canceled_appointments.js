#!/usr/bin/env node
/**
 * "Iptal edildi" durumundaki randevuları Firestore'dan kalıcı olarak siler.
 *
 * Neden gerekli:
 *   Uygulamadan randevu iptali kaldırıldı ve AppointmentStatus enum'ından
 *   canceled değeri çıkarıldı. Veritabanında hâlâ bu etiketi taşıyan eski
 *   kayıtlar, uygulamada "Planlandı" olarak görünür. Bu script onları temizler.
 *
 * Paket sayaçlarına DOKUNMAZ ve dokunmamalıdır:
 *   Bir randevu iptal edilirken meetingsCompleted / meetingsBurned sayacı zaten
 *   o anda geri verilmişti. "Iptal edildi" durumu hiçbir sayacı beslemediği için
 *   bu kayıtların silinmesi paket sayaçlarını etkilemez. postponementsUsed de
 *   aynı şekilde bırakılır: erteleme hakkı iptalde geri verilmiyor.
 *
 * Kullanım:
 *   cd tools
 *   npm install
 *
 *   # 1) Önce sadece rapor (hiçbir şey silinmez):
 *   node cleanup_canceled_appointments.js
 *
 *   # 2) Sonuçtan memnunsan gerçekten sil:
 *   node cleanup_canceled_appointments.js --apply
 *
 * Kimlik doğrulama (birini seç):
 *   a) Servis hesabı anahtarı:
 *      export GOOGLE_APPLICATION_CREDENTIALS=/tam/yol/serviceAccountKey.json
 *   b) gcloud ile:
 *      gcloud auth application-default login
 *      gcloud config set project deneme2-bc96d
 *
 * Ek seçenekler:
 *   --project=<id>   Proje kimliği (varsayılan: deneme2-bc96d veya ortam değişkeni)
 *   --per-user       collectionGroup yerine kullanıcıları tek tek tarar.
 *                    collectionGroup sorgusu index hatası verirse bunu kullan.
 *   --label="..."    Silinecek durum etiketi (varsayılan: "Iptal edildi").
 *                    Rapor bölümünde farklı bir yazım görürsen bununla ver.
 */

'use strict';

const fs = require('fs');
const path = require('path');
const admin = require('firebase-admin');

const DEFAULT_PROJECT_ID = 'deneme2-bc96d';
const DEFAULT_LABEL = 'Iptal edildi';
// Uygulamanın bugün tanıdığı durumlar. Rapor, bunların dışındaki her etiketi
// ayrıca gösterir; böylece "İptal Edildi" gibi farklı bir yazım varsa görülür.
const KNOWN_STATUSES = ['Yapıldı', 'Planlandı', 'Yakıldı', 'Ertelendi'];
const BATCH_LIMIT = 450; // Firestore'un 500 sınırının altında güvenli pay

function parseArgs(argv) {
  const args = { apply: false, perUser: false, label: DEFAULT_LABEL, project: null };
  for (const raw of argv.slice(2)) {
    if (raw === '--apply') args.apply = true;
    else if (raw === '--per-user') args.perUser = true;
    else if (raw.startsWith('--label=')) args.label = raw.slice('--label='.length);
    else if (raw.startsWith('--project=')) args.project = raw.slice('--project='.length);
    else {
      console.error(`Bilinmeyen seçenek: ${raw}`);
      process.exit(1);
    }
  }
  return args;
}

function initFirebase(projectId) {
  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId,
  });
  return admin.firestore();
}

/** Tüm randevuları tek collectionGroup sorgusuyla getirir. */
async function readAllViaCollectionGroup(db) {
  const snap = await db.collectionGroup('appointments').get();
  return snap.docs;
}

/** Kullanıcı kullanıcı gezerek getirir; hiçbir index gerektirmez. */
async function readAllPerUser(db) {
  const users = await db.collection('users').get();
  const docs = [];
  for (const user of users.docs) {
    const appts = await user.ref.collection('appointments').get();
    docs.push(...appts.docs);
  }
  return docs;
}

function summarizeStatuses(docs) {
  const counts = new Map();
  for (const doc of docs) {
    const status = doc.get('status');
    const key = status === undefined || status === null ? '(status alanı yok)' : String(status);
    counts.set(key, (counts.get(key) || 0) + 1);
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1]);
}

function describe(doc) {
  const data = doc.data() || {};
  const raw = data.appointmentDateTime;
  let when = '(tarihsiz)';
  if (raw && typeof raw.toDate === 'function') {
    when = raw.toDate().toISOString().slice(0, 16).replace('T', ' ');
  }
  // users/{userId}/appointments/{appointmentId}
  const userId = doc.ref.parent.parent ? doc.ref.parent.parent.id : '(bilinmiyor)';
  return { userId, appointmentId: doc.id, when, path: doc.ref.path };
}

async function deleteInBatches(db, docs) {
  let deleted = 0;
  for (let i = 0; i < docs.length; i += BATCH_LIMIT) {
    const chunk = docs.slice(i, i + BATCH_LIMIT);
    const batch = db.batch();
    for (const doc of chunk) batch.delete(doc.ref);
    await batch.commit();
    deleted += chunk.length;
    console.log(`  ... ${deleted}/${docs.length} silindi`);
  }
  return deleted;
}

async function main() {
  const args = parseArgs(process.argv);
  const projectId =
    args.project ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    DEFAULT_PROJECT_ID;

  console.log(`Proje       : ${projectId}`);
  console.log(`Aranan durum: "${args.label}"`);
  console.log(`Mod         : ${args.apply ? 'SİLME (--apply)' : 'sadece rapor (kuru çalışma)'}`);
  console.log('');

  const db = initFirebase(projectId);

  let docs;
  if (args.perUser) {
    console.log('Randevular kullanıcı kullanıcı taranıyor...');
    docs = await readAllPerUser(db);
  } else {
    console.log('Randevular collectionGroup ile okunuyor...');
    try {
      docs = await readAllViaCollectionGroup(db);
    } catch (e) {
      const msg = String(e && e.message ? e.message : e);
      console.error('\ncollectionGroup sorgusu başarısız oldu:');
      console.error(`  ${msg}`);
      if (/credential/i.test(msg)) {
        // Kimlik doğrulama eksik: --per-user de aynı hatayı verir.
        console.error('\nKimlik doğrulaması yapılmamış. Birini uygula:');
        console.error('  export GOOGLE_APPLICATION_CREDENTIALS=/tam/yol/serviceAccountKey.json');
        console.error('  ya da: gcloud auth application-default login\n');
      } else {
        console.error('\nMuhtemelen collectionGroup index eksik.');
        console.error('Hata mesajındaki bağlantıdan index oluşturabilir ya da');
        console.error('scripti index gerektirmeyen modda çalıştırabilirsin:');
        console.error('  node cleanup_canceled_appointments.js --per-user\n');
      }
      process.exit(1);
    }
  }

  console.log(`Toplam randevu kaydı: ${docs.length}\n`);

  console.log('Durum dağılımı:');
  for (const [status, count] of summarizeStatuses(docs)) {
    const flag = KNOWN_STATUSES.includes(status) ? '' : '   <-- uygulamanın tanımadığı etiket';
    console.log(`  ${String(count).padStart(6)}  ${status}${flag}`);
  }
  console.log('');

  const targets = docs.filter((doc) => doc.get('status') === args.label);
  if (targets.length === 0) {
    console.log(`"${args.label}" durumunda kayıt yok. Yapılacak bir şey kalmadı.`);
    return;
  }

  console.log(`Silinecek kayıtlar (${targets.length}):`);
  for (const doc of targets) {
    const d = describe(doc);
    console.log(`  ${d.when}  kullanıcı=${d.userId}  randevu=${d.appointmentId}`);
  }
  console.log('');

  // Silme geri alınamaz: ne silindiğini yanına bir JSON olarak bırak.
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const backupPath = path.join(__dirname, `canceled-appointments-backup-${stamp}.json`);
  const backup = targets.map((doc) => ({ path: doc.ref.path, data: doc.data() }));
  fs.writeFileSync(backupPath, JSON.stringify(backup, null, 2), 'utf8');
  console.log(`Yedek yazıldı: ${backupPath}`);

  if (!args.apply) {
    console.log('\nKuru çalışma bitti, hiçbir kayıt silinmedi.');
    console.log('Gerçekten silmek için: node cleanup_canceled_appointments.js --apply');
    return;
  }

  console.log('\nSiliniyor...');
  const deleted = await deleteInBatches(db, targets);
  console.log(`\nBitti. ${deleted} randevu silindi.`);
  console.log('Paket sayaçlarına dokunulmadı (iptal edilen randevular sayaç tutmuyordu).');
}

main().catch((e) => {
  console.error('\nHata:', e);
  process.exit(1);
});
