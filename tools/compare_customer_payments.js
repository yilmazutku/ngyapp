#!/usr/bin/env node
/**
 * İki (veya daha fazla) danışanın PAKET ve ÖDEME kayıtlarını yan yana döker ve
 * "Danışanlar Özet" sayfasının ödeme sütunlarında ne göstereceğini simüle eder.
 *
 * Neden gerekli:
 *   Danışanlar Özet'te bir danışanda ödeme alınmış gibi görünüp, paketin içine
 *   girildiğinde "Eksik Ödeme" yazması genelde ödemenin BAŞKA BİR PAKETE (ya da
 *   "Paketsiz" olarak) bağlı olmasından kaynaklanır. Bu script, iki danışan
 *   arasındaki farkın tam olarak nerede olduğunu gösterir.
 *
 * SADECE OKUR. Hiçbir kayıt yazmaz, güncellemez, silmez.
 *
 * Kullanım:
 *   cd tools
 *   npm install
 *   node compare_customer_payments.js "Ecem Kurt" "Gizem Fatma Özer"
 *
 *   Arama terimi olarak ad-soyad parçası, dosya no ya da userId verilebilir:
 *   node compare_customer_payments.js 52 48
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
 */

'use strict';

const admin = require('firebase-admin');

const DEFAULT_PROJECT_ID = 'deneme2-bc96d';

// Firestore'da saklanan ham etiketler (lib/models/subs_model.dart,
// lib/models/payment_model.dart ile birebir aynı olmalı).
const SUB_STATUS_NAMES = {
  active: 'Aktif/Haftalık',
  active_kt: 'Aktif/Kilo Takip',
  completed: 'Tamamlandı',
  frozen: 'Donduruldu',
};
// Danışanlar Özet sekmeleri: her sekme tek bir paket durumunu listeler.
const SUMMARY_TABS = ['active', 'active_kt', 'frozen'];
const PAYMENT_COMPLETED = 'Tamamlandı';
const PAYMENT_PLANNED = 'Planlandı';
const MEETING_TYPE_NAMES = {
  online: 'Online',
  face_to_face: 'Yüzyüze',
  hybrid: 'Y+O',
};

function parseArgs(argv) {
  const args = { project: null, terms: [] };
  for (const raw of argv.slice(2)) {
    if (raw.startsWith('--project=')) args.project = raw.slice('--project='.length);
    else if (raw.startsWith('--')) {
      console.error(`Bilinmeyen seçenek: ${raw}`);
      process.exit(1);
    } else args.terms.push(raw);
  }
  return args;
}

/** Türkçe'ye duyarlı, aksansız karşılaştırma anahtarı. */
function normalize(text) {
  return String(text ?? '')
    .toLocaleLowerCase('tr')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function toDate(value) {
  if (value && typeof value.toDate === 'function') return value.toDate();
  return null;
}

function fmtDate(value) {
  const date = toDate(value);
  if (!date) return '—';
  const pad = (n) => String(n).padStart(2, '0');
  return `${pad(date.getDate())}.${pad(date.getMonth() + 1)}.${date.getFullYear()}`;
}

function fmtAmount(value) {
  const num = Number(value);
  if (!Number.isFinite(num)) return '—';
  return num.toLocaleString('tr-TR', { maximumFractionDigits: 0 });
}

/**
 * Uzun Firestore kimliklerini okunur tutmak için kısaltır. Baş ve son birlikte
 * gösterilir: aynı danışanın iki paketi yalnızca sonda ayrışabiliyor.
 */
function shortId(id) {
  const text = String(id);
  return text.length > 14 ? `${text.slice(0, 8)}…${text.slice(-4)}` : text;
}

function fullName(data) {
  return `${data.name ?? ''} ${data.surname ?? ''}`.trim() || '(İsimsiz)';
}

async function findCustomers(db, terms) {
  const snap = await db.collection('users').get();
  const matches = [];
  for (const term of terms) {
    const needle = normalize(term);
    const hits = snap.docs.filter((doc) => {
      const data = doc.data() || {};
      return (
        normalize(fullName(data)).includes(needle) ||
        normalize(data.dosyaNo) === needle ||
        doc.id === term
      );
    });
    if (hits.length === 0) {
      console.error(`"${term}" ile eşleşen danışan bulunamadı.`);
      continue;
    }
    if (hits.length > 1) {
      console.error(`"${term}" birden fazla danışanla eşleşti, hepsi gösterilecek:`);
      for (const hit of hits) {
        console.error(`  - ${fullName(hit.data())} (dosyaNo=${hit.get('dosyaNo') ?? '—'}, userId=${hit.id})`);
      }
    }
    matches.push(...hits);
  }
  // Aynı danışan iki terimle eşleştiyse tekrarlama.
  return [...new Map(matches.map((doc) => [doc.id, doc])).values()];
}

/**
 * Danışanlar Özet'in bir sekmede seçtiği paket: o durumdaki paketler arasından
 * başlangıç tarihi en yeni olan (CustomerSummaryProvider._findSubscriptionByStatus).
 */
function pickSummarySubscription(subs, statusLabel) {
  const candidates = subs.filter((s) => s.data.status === statusLabel);
  if (candidates.length === 0) return null;
  return candidates.sort(
    (a, b) => (toDate(b.data.startDate)?.getTime() ?? 0) - (toDate(a.data.startDate)?.getTime() ?? 0),
  )[0];
}

/** Tamamlanmış ödemelerin en yenisi (paymentDate yoksa createDate'e düşer). */
function latestCompleted(payments) {
  const completed = payments.filter((p) => p.data.status === PAYMENT_COMPLETED);
  if (completed.length === 0) return null;
  const key = (p) => (toDate(p.data.paymentDate) ?? toDate(p.data.createDate))?.getTime() ?? 0;
  return completed.sort((a, b) => key(b) - key(a))[0];
}

function describePaymentCells(payment) {
  if (!payment) return 'boş / boş / boş  (hiç ödeme gösterilmez)';
  const date = toDate(payment.data.paymentDate) ? fmtDate(payment.data.paymentDate) : 'Hata';
  return `${date} / ${fmtAmount(payment.data.amount)} / ${payment.data.paymentType ?? '-'}`;
}

async function loadCustomer(db, userDoc) {
  const [subsSnap, paymentsSnap] = await Promise.all([
    userDoc.ref.collection('subscriptions').get(),
    userDoc.ref.collection('payments').get(),
  ]);
  return {
    id: userDoc.id,
    data: userDoc.data() || {},
    subs: subsSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() || {} })),
    payments: paymentsSnap.docs.map((doc) => ({ id: doc.id, data: doc.data() || {} })),
  };
}

function printCustomer(customer) {
  const { data, subs, payments } = customer;
  console.log('='.repeat(78));
  console.log(`${fullName(data)}   dosyaNo=${data.dosyaNo ?? '—'}   userId=${customer.id}`);
  console.log('='.repeat(78));

  console.log(`\nPAKETLER (${subs.length})`);
  if (subs.length === 0) console.log('  (paket yok)');
  for (const sub of subs) {
    const s = sub.data;
    const statusName = SUB_STATUS_NAMES[s.status] ?? `${s.status} (bilinmeyen)`;
    const missing = Number(s.totalAmount ?? 0) - Number(s.amountPaid ?? 0);
    console.log(
      `  [${shortId(sub.id)}] ${statusName} | ${s.packageName ?? '(adsız)'} | ` +
        `${s.packageType ?? '(tip yok)'} ${MEETING_TYPE_NAMES[s.meetingType] ?? s.meetingType ?? '—'} | ` +
        `başlangıç ${fmtDate(s.startDate)}`,
    );
    console.log(
      `        tutar ${fmtAmount(s.totalAmount)} | ödenen ${fmtAmount(s.amountPaid)} | ` +
        (missing > 0 ? `EKSİK ÖDEME ${fmtAmount(missing)}` : 'Ödeme Tamam'),
    );
  }

  console.log(`\nÖDEMELER (${payments.length})`);
  if (payments.length === 0) console.log('  (ödeme kaydı yok)');
  const subsById = new Map(subs.map((s) => [s.id, s]));
  const sorted = [...payments].sort((a, b) => {
    const key = (p) => (toDate(p.data.paymentDate) ?? toDate(p.data.dueDate) ?? toDate(p.data.createDate))?.getTime() ?? 0;
    return key(a) - key(b);
  });
  for (const payment of sorted) {
    const p = payment.data;
    let link;
    if (!p.subscriptionId) {
      link = 'PAKETSİZ (hiçbir pakete bağlı değil)';
    } else if (subsById.has(p.subscriptionId)) {
      const linked = subsById.get(p.subscriptionId);
      link = `${linked.data.packageName ?? '(adsız)'} [${shortId(linked.id)}] ` +
        `(${SUB_STATUS_NAMES[linked.data.status] ?? linked.data.status}, başl. ${fmtDate(linked.data.startDate)})`;
    } else {
      link = `SİLİNMİŞ PAKET [${shortId(p.subscriptionId)}]`;
    }
    console.log(
      `  [${shortId(payment.id)}] ${p.status ?? '(durumsuz)'} | ${fmtAmount(p.amount)} ₺ | ` +
        `${p.paymentType ?? '-'} | ödeme ${fmtDate(p.paymentDate)} | planlanan ${fmtDate(p.dueDate)}`,
    );
    console.log(`        bağlı paket: ${link}`);
  }
}

/**
 * Danışanlar Özet'in ödeme sütunlarını, düzeltme ÖNCESİ ve SONRASI mantıkla
 * hesaplar. İkisi farklıysa satır yanlış bir ödeme gösteriyor demektir.
 */
function printSummarySimulation(customer) {
  const { subs, payments } = customer;
  console.log('\nDANIŞANLAR ÖZET SİMÜLASYONU');
  const tabs = SUMMARY_TABS.filter((status) => subs.some((s) => s.data.status === status));
  if (tabs.length === 0) {
    console.log('  Bu danışan hiçbir özet sekmesinde listelenmiyor (aktif/dondurulmuş paketi yok).');
    return;
  }
  for (const status of tabs) {
    const sub = pickSummarySubscription(subs, status);
    console.log(`\n  Sekme "${SUB_STATUS_NAMES[status]}" → satırın paketi: ` +
      `${sub.data.packageName ?? '(adsız)'} [${shortId(sub.id)}], başl. ${fmtDate(sub.data.startDate)}`);

    const before = latestCompleted(payments);
    const after = latestCompleted(payments.filter((p) => p.data.subscriptionId === sub.id));

    console.log(`    ESKİ mantık (tüm paketlerin ödemeleri): ${describePaymentCells(before)}`);
    console.log(`    YENİ mantık (yalnız bu paket)         : ${describePaymentCells(after)}`);
    if ((before?.id ?? null) !== (after?.id ?? null)) {
      console.log('    >>> FARKLI: Özet, bu pakete ait OLMAYAN bir ödemeyi gösteriyordu.');
      if (before) {
        const link = before.data.subscriptionId
          ? `paket [${shortId(before.data.subscriptionId)}]`
          : 'PAKETSİZ';
        console.log(`        Gösterilen ödeme aslında ${link} kaydı.`);
      }
    } else {
      console.log('    >>> Aynı: bu satırda eski/yeni mantık aynı sonucu veriyor.');
    }

    const planned = payments.filter(
      (p) => p.data.subscriptionId === sub.id && p.data.status === PAYMENT_PLANNED,
    );
    if (planned.length > 0) {
      const dates = planned.map((p) => fmtDate(p.data.dueDate)).join(', ');
      console.log(`    Bu pakette ${planned.length} adet "Planlandı" ödeme var (tarih: ${dates}).`);
      console.log('    Planlanan ödemeler henüz gelmemiş para olduğu için özet sütunlarında gösterilmez.');
    }
  }
}

/** İki danışanı karşılaştırıp yalnızca gerçek farkları yazar. */
function printDifferences(customers) {
  if (customers.length < 2) return;
  console.log(`\n${'='.repeat(78)}`);
  console.log('FARKLAR');
  console.log('='.repeat(78));

  const facts = customers.map((customer) => {
    const activeSub =
      pickSummarySubscription(customer.subs, 'active') ??
      pickSummarySubscription(customer.subs, 'active_kt') ??
      pickSummarySubscription(customer.subs, 'frozen');
    const own = activeSub
      ? customer.payments.filter((p) => p.data.subscriptionId === activeSub.id)
      : [];
    return {
      name: fullName(customer.data),
      subCount: customer.subs.length,
      paymentCount: customer.payments.length,
      completedTotal: customer.payments.filter((p) => p.data.status === PAYMENT_COMPLETED).length,
      completedOnOtherPackages: customer.payments.filter(
        (p) => p.data.status === PAYMENT_COMPLETED && (!activeSub || p.data.subscriptionId !== activeSub.id),
      ).length,
      orphanPayments: customer.payments.filter((p) => !p.data.subscriptionId).length,
      completedOnActive: own.filter((p) => p.data.status === PAYMENT_COMPLETED).length,
      plannedOnActive: own.filter((p) => p.data.status === PAYMENT_PLANNED).length,
      amountPaid: activeSub ? Number(activeSub.data.amountPaid ?? 0) : null,
      totalAmount: activeSub ? Number(activeSub.data.totalAmount ?? 0) : null,
    };
  });

  const rows = [
    ['Toplam paket sayısı', (f) => f.subCount],
    ['Toplam ödeme kaydı', (f) => f.paymentCount],
    ['"Tamamlandı" ödeme (tümü)', (f) => f.completedTotal],
    ['  ...bu pakete ait', (f) => f.completedOnActive],
    ['  ...BAŞKA pakete ait', (f) => f.completedOnOtherPackages],
    ['Paketsiz ödeme', (f) => f.orphanPayments],
    ['"Planlandı" ödeme (bu paket)', (f) => f.plannedOnActive],
    ['Paket tutarı', (f) => (f.totalAmount === null ? '—' : fmtAmount(f.totalAmount))],
    ['Pakette ödenen (amountPaid)', (f) => (f.amountPaid === null ? '—' : fmtAmount(f.amountPaid))],
  ];

  const nameWidth = Math.max(...facts.map((f) => f.name.length), 12);
  const labelWidth = Math.max(...rows.map(([label]) => label.length));
  console.log(
    `\n${' '.repeat(labelWidth)}  ${facts.map((f) => f.name.padEnd(nameWidth)).join('  ')}`,
  );
  for (const [label, get] of rows) {
    const values = facts.map(get);
    const differs = new Set(values.map(String)).size > 1;
    console.log(
      `${label.padEnd(labelWidth)}  ${values.map((v) => String(v).padEnd(nameWidth)).join('  ')}` +
        (differs ? '  <-- FARKLI' : ''),
    );
  }
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.terms.length === 0) {
    console.error('Kullanım: node compare_customer_payments.js "Ecem Kurt" "Gizem Fatma Özer"');
    process.exit(1);
  }

  const projectId =
    args.project ||
    process.env.GOOGLE_CLOUD_PROJECT ||
    process.env.GCLOUD_PROJECT ||
    DEFAULT_PROJECT_ID;

  console.log(`Proje: ${projectId}   (bu script SADECE OKUR, hiçbir kayıt değiştirmez)\n`);

  admin.initializeApp({ credential: admin.credential.applicationDefault(), projectId });
  const db = admin.firestore();

  let userDocs;
  try {
    userDocs = await findCustomers(db, args.terms);
  } catch (e) {
    const msg = String(e && e.message ? e.message : e);
    console.error(`\nFirestore okunamadı: ${msg}`);
    if (/credential/i.test(msg)) {
      console.error('\nKimlik doğrulaması yapılmamış. Birini uygula:');
      console.error('  export GOOGLE_APPLICATION_CREDENTIALS=/tam/yol/serviceAccountKey.json');
      console.error('  ya da: gcloud auth application-default login\n');
    }
    process.exit(1);
  }

  if (userDocs.length === 0) {
    console.error('Hiçbir danışan bulunamadı.');
    process.exit(1);
  }

  const customers = [];
  for (const doc of userDocs) {
    const customer = await loadCustomer(db, doc);
    customers.push(customer);
    printCustomer(customer);
    printSummarySimulation(customer);
    console.log('');
  }

  printDifferences(customers);
}

main().catch((e) => {
  console.error('\nHata:', e);
  process.exit(1);
});
