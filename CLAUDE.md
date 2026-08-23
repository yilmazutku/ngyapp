# Çalışma Kuralları

## Git akışı
- Geliştirme her zaman bir feature branch üzerinde yapılır, `master`'a doğrudan commit atılmaz.
- İş bitince branch `master`'a merge edilir ve `master` push edilir.
- **Merge'den sonra feature branch hem yerelde hem `origin`'de silinir.** Merge edilmiş `claude/*` dalları repoda bırakılmaz.
- Commit notları Türkçe, maddeler hâlinde ve açıklayıcı yazılır; kullanıcının isteği de commit notuna eklenir.

## Kod
- Proje kuralları `.cursor/rules/` altındadır; her değişiklikten önce geçerli olanlar okunur.
- Değişiklikten sonra `flutter analyze lib` çalıştırılır: hata bırakılmaz, dokunulan dosyalarda yeni uyarı bırakılmaz.
- `flutter analyze` çalışırken `analysis_options.yaml` ve `pubspec.lock` dosyalarını değiştirebiliyor; bunlar commit'e dahil edilmez.
