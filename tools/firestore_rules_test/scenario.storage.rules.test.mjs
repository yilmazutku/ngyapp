import fs from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import 'firebase/compat/storage';

const ADMIN = '0MvvbZsjbmNPW4QYShRNSOOtkE43';
const MB = 1024 * 1024;
const GUN = '2026-10-13';
const GOZLEM = 'gözlem';
const bytes = (size = 2048) => new Uint8Array(size).fill(7);
const jpeg = { contentType: 'image/jpeg' };

async function run(rulesFile) {
  const env = await initializeTestEnvironment({
    projectId: 'demo-ngy',
    storage: { rules: fs.readFileSync(rulesFile, 'utf8'), host: '127.0.0.1', port: 9199 },
  });
  await env.clearStorage();
  const results = [];
  const check = async (step, name, expect, fn) => {
    let outcome;
    let detail = '';
    try { await fn(); outcome = 'ALLOW'; } catch (e) {
      const text = `${e.code ?? ''} ${e.message ?? e}`;
      if (/unauthorized|permission|403/i.test(text)) outcome = 'DENY';
      else if (/object-not-found/i.test(text)) outcome = 'NOT_FOUND';
      else { outcome = 'ERR'; detail = text.replace(/\s+/g, ' ').slice(0, 220); }
    }
    const ok = expect === GOZLEM ? outcome !== 'ERR' : outcome === expect;
    results.push({ step, name, expect, outcome, ok, detail });
  };
  const st = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage();
  const folder = (uid, meal) => `users/${uid}/mealPhotos/${GUN}/${meal}`;
  const D = 'danisanSil';
  const YABANCI = 'baskaDanisan';
  const foto = `${folder(D, 'dinner')}/1700000000001_IMG_1.jpg`;
  const thumb = `${folder(D, 'dinner')}/1700000000001_IMG_1_thumb.jpg`;
  const foto2 = `${folder(D, 'secondmid')}/1700000000002_IMG_2.jpg`;
  const thumb2 = `${folder(D, 'secondmid')}/1700000000002_IMG_2_thumb.png`;

  const urls = {};
  await check('7.1', 'Danışan öğün fotoğrafını ve küçük görselini kendi klasörüne yükler (hazırlık)', 'ALLOW', async () => {
    const s = st(D);
    for (const p of [foto, thumb, foto2, thumb2]) {
      await s.ref(p).put(bytes(), p.endsWith('.png') ? { contentType: 'image/png' } : jpeg);
      urls[p] = await s.ref(p).getDownloadURL();
    }
  });
  await check('7.1', 'Başka danışan bu danışanın öğün fotoğrafını silemez (refFromURL)', 'DENY', () => st(YABANCI).refFromURL(urls[foto]).delete());
  await check('7.1', 'Başka danışan bu danışanın küçük görselini silemez', 'DENY', () => st(YABANCI).refFromURL(urls[thumb]).delete());
  await check('7.1', 'Giriş yapmamış kullanıcı öğün fotoğrafını silemez', 'DENY', () => st(null).ref(foto2).delete());
  await check('7.1', 'Danışan kendi öğün fotoğrafını indirme adresinden siler (deleteFile: refFromURL.delete)', 'ALLOW', () => st(D).refFromURL(urls[foto]).delete());
  await check('7.1', 'Danışan kendi küçük görselini siler', 'ALLOW', () => st(D).refFromURL(urls[thumb]).delete());
  await check('7.1', 'Silinen fotoğraf ve küçük görsel artık yok (object-not-found)', 'ALLOW', async () => {
    for (const p of [foto, thumb]) {
      try { await st(D).ref(p).getDownloadURL(); throw new Error(`BEKLENMEYEN: ${p} hâlâ duruyor`); } catch (e) {
        if (!/object-not-found/i.test(`${e.code ?? ''} ${e.message ?? e}`)) throw e;
      }
    }
  });
  await check('7.1', 'Zaten silinmiş dosyayı tekrar silmek yetki değil "bulunamadı" hatası verir (ignoreStorageFailure yolu)', 'NOT_FOUND', () => st(D).refFromURL(urls[foto]).delete());
  await check('7.7', 'Danışan albümdeki ara öğün fotoğrafını ve png küçük görselini siler', 'ALLOW', async () => {
    await st(D).refFromURL(urls[foto2]).delete();
    await st(D).refFromURL(urls[thumb2]).delete();
  });

  await env.withSecurityRulesDisabled(async (ctx) => {
    await ctx.storage().ref(`users/${D}/dietSources/1/diyet.pdf`).put(bytes(), { contentType: 'application/pdf' });
    await ctx.storage().ref(`${folder(D, 'lunch')}/1700000000009_admin_thumb.jpg`).put(bytes(), jpeg);
  });
  await check('J', 'Danışan admin\'in yüklediği diyet dosyasının üstüne yazamaz', 'DENY', () => st(D).ref(`users/${D}/dietSources/1/diyet.pdf`).put(bytes(), { contentType: 'application/pdf' }));
  await check('J', 'Danışan admin\'in yüklediği diyet dosyasını silemez', 'DENY', () => st(D).ref(`users/${D}/dietSources/1/diyet.pdf`).delete());
  await check('7.11', 'Admin danışanın öğün fotoğrafını silebilir mi (uygulamada seçenek yok; kuralda admin sınırsız)', GOZLEM, () => st(ADMIN).ref(`${folder(D, 'lunch')}/1700000000009_admin_thumb.jpg`).delete());

  await check('J', 'Danışan 50 MB\'tan 1 bayt küçük öğün fotoğrafı yükleyebilir', 'ALLOW', () => st(D).ref(`${folder(D, 'lunch')}/sinir_alti.jpg`).put(bytes(50 * MB - 1), jpeg));
  await check('J', 'Danışan tam 50 MB öğün fotoğrafı yükleyebilmeli (J: "en fazla 50 MB")', 'ALLOW', () => st(D).ref(`${folder(D, 'lunch')}/sinir_tam.jpg`).put(bytes(50 * MB), jpeg));
  await check('J', 'Danışan 50 MB\'ı 1 bayt aşan dosyayı yükleyemez', 'DENY', () => st(D).ref(`${folder(D, 'lunch')}/sinir_ustu.jpg`).put(bytes(50 * MB + 1), jpeg));
  await check('J', 'Danışan mealPhotos dışına (kendi users klasöründe başka yola) yükleyemez', 'DENY', () => st(D).ref(`users/${D}/measurements/tanita_x.pdf`).put(bytes(), { contentType: 'application/pdf' }));
  await check('J', 'Danışan mealPhotos klasörüne görsel olmayan dosya (text/html) yükleyebilir mi', GOZLEM, () => st(D).ref(`${folder(D, 'lunch')}/sayfa.html`).put(bytes(), { contentType: 'text/html' }));
  await check('9.4', 'Sohbeti silinmiş danışan ilk öğün fotoğrafını ve küçük görselini yükler', 'ALLOW', async () => {
    await st('danisanYeniden').ref(`${folder('danisanYeniden', 'lunch')}/1700000000006_IMG_6.jpg`).put(bytes(), jpeg);
    await st('danisanYeniden').ref(`${folder('danisanYeniden', 'lunch')}/1700000000006_IMG_6_thumb.jpg`).put(bytes(), jpeg);
  });

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
