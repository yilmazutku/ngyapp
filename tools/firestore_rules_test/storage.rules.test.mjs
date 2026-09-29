// storage.rules dosyasını Storage emülatöründe uygulamanın gerçek
// yüklemeleriyle dener: danışanın öğün fotoğrafı ve küçük görseli, kendi
// fotoğrafını silmesi, admin'in yüklediği dosyalar (diyet, tanita, tahlil,
// dekont, haber, ödeme), eski sürümlerin sohbet fotoğrafları ve yetkisiz
// erişim denemeleri. Kural değiştikten sonra çalıştırılır:
//   cd tools/firestore_rules_test && npm install && npm test
// Emülatör açıkken birden çok kural dosyası yan yana karşılaştırılabilir:
//   node storage.rules.test.mjs eski.rules ../../storage.rules
import fs from 'node:fs';
import { initializeTestEnvironment } from '@firebase/rules-unit-testing';
import 'firebase/compat/storage';

const ADMIN = '0MvvbZsjbmNPW4QYShRNSOOtkE43';
const MB = 1024 * 1024;
const jpeg = (size = 2048) => new Uint8Array(size).fill(7);
const image = { contentType: 'image/jpeg' };
const pdf = { contentType: 'application/pdf' };

async function run(rulesFile) {
  const env = await initializeTestEnvironment({
    projectId: 'demo-ngy',
    storage: {
      rules: fs.readFileSync(rulesFile, 'utf8'),
      host: '127.0.0.1',
      port: 9199,
    },
  });
  await env.clearStorage();
  const results = [];
  const check = async (name, expectAllowed, fn) => {
    let allowed;
    try {
      await fn();
      allowed = true;
    } catch (e) {
      const text = `${e.code ?? ''} ${e}`;
      allowed = /unauthorized|permission|403/i.test(text) ? false : `ERR:${text}`;
    }
    results.push({ name, expectAllowed, allowed, ok: allowed === expectAllowed });
  };
  const st = (uid) =>
    (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage();
  const seed = (fn) => env.withSecurityRulesDisabled((ctx) => fn(ctx.storage()));
  const meal = 'users/c1/mealPhotos/2026-09-29/lunch';

  await seed(async (s) => {
    await s.ref('users/c1/dietSources/1/diyet.docx').put(jpeg(), pdf);
    await s.ref('users/c1/measurements/tanita_1.pdf').put(jpeg(), pdf);
    await s.ref('users/c1/tests/test_1.pdf').put(jpeg(), pdf);
    await s.ref('users/c1/dekont/1').put(jpeg(), image);
    await s.ref('chats/c1/old.jpg').put(jpeg(), image);
    await s.ref('news/n.jpg').put(jpeg(), image);
  });

  // Danışanın uygulamada yaptıkları.
  await check('U1 customer uploads meal photo', true, () => st('c1').ref(`${meal}/1_a.jpg`).put(jpeg(), image));
  await check('U2 customer uploads its thumbnail', true, () => st('c1').ref(`${meal}/1_a_thumb.jpg`).put(jpeg(), image));
  await check('U3 getDownloadURL of own photo', true, () => st('c1').ref(`${meal}/1_a.jpg`).getDownloadURL());
  await check('U4 backfill thumbnail (png)', true, () => st('c1').ref(`${meal}/1_a_thumb.png`).put(jpeg(), { contentType: 'image/png' }));
  await check('U5 customer deletes own meal photo', true, () => st('c1').ref(`${meal}/1_a.jpg`).delete());
  await check('U6 uncompressed desktop photo (20 MB)', true, () => st('c1').ref(`${meal}/2_big.png`).put(jpeg(20 * MB), { contentType: 'image/png' }));
  await check('U7 customer reads own diet/tanita/test/dekont', true, async () => {
    await st('c1').ref('users/c1/dietSources/1/diyet.docx').getDownloadURL();
    await st('c1').ref('users/c1/measurements/tanita_1.pdf').getDownloadURL();
    await st('c1').ref('users/c1/tests/test_1.pdf').getDownloadURL();
    await st('c1').ref('users/c1/dekont/1').getDownloadURL();
  });
  await check('U8 old app: own chat image upload', true, () => st('c1').ref('chats/c1/new.jpg').put(jpeg(), image));
  await check('U9 old app: users/{uid}/chatPhotos upload', true, () => st('c1').ref('users/c1/chatPhotos/2026-09-29/x.jpg').put(jpeg(), image));
  await check('U10 customer reads own old chat image', true, () => st('c1').ref('chats/c1/old.jpg').getDownloadURL());
  await check('U11 signed-in reads news image', true, () => st('c1').ref('news/n.jpg').getDownloadURL());

  // Danışanın yapmaması gerekenler.
  await check('X1 other customer uploads into c1 meal photos', false, () => st('c2').ref(`${meal}/x.jpg`).put(jpeg(), image));
  await check('X2 other customer reads c1 files', false, () => st('c2').ref('users/c1/tests/test_1.pdf').getDownloadURL());
  await check('X3 customer overwrites own tanita report', false, () => st('c1').ref('users/c1/measurements/tanita_1.pdf').put(jpeg(), pdf));
  await check('X4 customer replaces own dekont', false, () => st('c1').ref('users/c1/dekont/1').put(jpeg(), image));
  await check('X5 customer deletes own diet file', false, () => st('c1').ref('users/c1/dietSources/1/diyet.docx').delete());
  await check('X6 customer deletes own test result', false, () => st('c1').ref('users/c1/tests/test_1.pdf').delete());
  await check('X7 customer uploads random file into own folder', false, () => st('c1').ref('users/c1/other/big.bin').put(jpeg(), pdf));
  await check('X8 meal photo over 50 MB', false, () => st('c1').ref(`${meal}/huge.jpg`).put(jpeg(51 * MB), image));
  await check('X9 other customer writes into c1 chat', false, () => st('c2').ref('chats/c1/x.jpg').put(jpeg(), image));
  await check('X10 customer uploads news image', false, () => st('c1').ref('news/x.jpg').put(jpeg(), image));
  await check('X11 customer uploads to payments/', false, () => st('c1').ref('payments/p1_1').put(jpeg(), image));
  await check('X12 signed-out reads meal photo via SDK', false, () => st(null).ref(`${meal}/1_a_thumb.jpg`).getDownloadURL());

  // Admin'in yaptıkları.
  await check('A1 admin uploads diet/tanita/test/dekont for c1', true, async () => {
    await st(ADMIN).ref('users/c1/dietRecipes/2/tarif.pdf').put(jpeg(), pdf);
    await st(ADMIN).ref('users/c1/measurements/tanita_2.pdf').put(jpeg(), pdf);
    await st(ADMIN).ref('users/c1/tests/test_2.pdf').put(jpeg(), pdf);
    await st(ADMIN).ref('users/c1/dekont/2').put(jpeg(), image);
  });
  await check('A2 admin uploads news + payments receipt', true, async () => {
    await st(ADMIN).ref('news/a.jpg').put(jpeg(), image);
    await st(ADMIN).ref('payments/p1_2').put(jpeg(), image);
  });
  await check('A3 admin backfills c1 thumbnail', true, () => st(ADMIN).ref(`${meal}/2_big_thumb.jpg`).put(jpeg(), image));
  await check('A4 admin deletes chat images (deleteChat)', true, () => st(ADMIN).ref('chats/c1/old.jpg').delete());
  await check('A5 admin deletes c1 meal photo', true, () => st(ADMIN).ref(`${meal}/2_big.png`).delete());

  await env.cleanup();
  return results;
}

const files = process.argv.slice(2);
const all = {};
for (const f of files) all[f] = await run(f);
const names = all[files[0]].map((r) => r.name);
let failed = 0;
for (let i = 0; i < names.length; i++) {
  const cols = files.map((f) => {
    const r = all[f][i];
    const shown = r.allowed === true ? 'ALLOW' : r.allowed === false ? 'deny ' : r.allowed;
    return `${f}: ${shown}${r.ok ? '' : ' (!)'}`;
  });
  const last = all[files[files.length - 1]][i];
  if (!last.ok) failed++;
  console.log(`${last.ok ? 'OK ' : 'BAD'} ${names[i].padEnd(48)} expect=${last.expectAllowed ? 'ALLOW' : 'deny '} | ${cols.join(' | ')}`);
}
console.log(failed ? `\n${failed} unexpected result(s) with ${files[files.length - 1]}` : `\nAll expectations met with ${files[files.length - 1]}`);
process.exit(failed ? 1 : 0);
