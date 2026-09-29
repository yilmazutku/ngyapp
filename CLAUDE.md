# Çalışma Kuralları

## Git akışı
- Geliştirme her zaman bir feature branch üzerinde yapılır, `master`'a doğrudan commit atılmaz.
- İş bitince branch `master`'a merge edilir ve `master` push edilir.
- **Merge + push bittikten sonra feature branch silinmeye çalışılmaz; olduğu gibi bırakılır** (ne yerelde ne `origin`'de silme denenir).
- Commit notları Türkçe, maddeler hâlinde ve açıklayıcı yazılır; kullanıcının isteği de commit notuna eklenir.
- **Merge/push yapmadan önce `master`'ın değişip değişmediğine bakılır** (`git fetch origin master`). Merge yapan başka bir agent varsa karışılmaz; onun işi bitene kadar beklenir, sonra güncel `master` üzerinden merge edilir.

## Kod
- **Her görevin en başında `.cursor/rules/` altındaki kural dosyaları okunur; kodlama bu kurallara göre yapılır.** Kurallar okunmadan koda başlanmaz.
- Proje kuralları `.cursor/rules/` altındadır; her değişiklikten önce geçerli olanlar okunur.
- **Var olan widget'lar yeterliyse yenisi tanımlanmaz, var olan kullanılır.** Yeni widget ya da yardımcı yazmadan önce `lib/widgets`, `lib/utils`, `lib/services` ve ilgili sayfalarda benzeri aranır; neredeyse yeterliyse genişletilir, sayfaya özel bir widget başka yerde gerekiyorsa ortak dosyaya taşınır (bkz. `.cursor/rules/reuse_existing.mdc`).
- Değişiklikten sonra `flutter analyze lib` çalıştırılır: hata bırakılmaz, dokunulan dosyalarda yeni uyarı bırakılmaz.
- Firestore ve Storage güvenlik kuralları `firestore.rules` ve `storage.rules`'dadır ve Firebase Console'dakilerle aynı tutulur. Yazılan alan, koleksiyon ya da Storage yolu değişirse (ör. danışanın yeni bir yere dosya yüklemesi) kurallar da gözden geçirilir; kural değişince `tools/firestore_rules_test` içinde `npm install && npm test` ile emülatörde denenir (Java gerekir).
- `flutter analyze` çalışırken `analysis_options.yaml`, `pubspec.lock` ve `lib/l10n/app_localizations.dart` (gen-l10n çıktısı) dosyalarını değiştirebiliyor; bunlar commit'e dahil edilmez.

## Test
- Sayfanın kendisi yerine aynı mantığın bir kopyasıyla (platform taklidiyle, `debugDefaultTargetPlatformOverride`) yazılan testlerde başka platformlar deneniyorsa **iOS da mutlaka denenir**; iOS listeden çıkarılmaz.
