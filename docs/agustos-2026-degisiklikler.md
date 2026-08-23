# Ağustos 2026 — Değişikliklerin Kullanıcıya Etkisi

Bu döküman, 1–21 Ağustos 2026 arasında yapılan 28 commit'in **son kullanıcı
(danışan ve diyetisyen) açısından ne anlama geldiğini** teknik olmayan bir dille
anlatır. Commit'ler kronolojik sıradadır.

---

## 1. Blog ve BKİ Hesaplama sayfaları — girişsiz erişim (`cebe804`, 2 Ağustos)

- Uygulamaya **giriş yapmadan** kullanılabilen iki yeni sayfa eklendi: **Blog** ve
  **BKİ Hesaplama**. İkisine de login ekranındaki butonlardan ulaşılıyor.
- **BKİ Hesaplama**: yaş, kilo ve boy girilince vücut kitle indeksi, hangi
  kategoride olunduğu ve ideal kilo aralığı hesaplanıyor. Henüz danışan olmayan
  biri de kullanabiliyor.
- **Duyurular ikiye ayrıldı**: diyetisyen bir yazıyı eklerken "Nerede
  Gösterilsin?" ile yazının Duyurular'da mı, Blog'da mı, yoksa ikisinde birden mi
  görüneceğini seçiyor.
- **Eski duyurular etkilenmedi** — daha önce girilmiş tüm duyurular eskisi gibi
  yalnızca Duyurular sayfasında görünmeye devam ediyor.
- Duyurular ve Blog listeleri **kompakt görünüme** geçti: başlık (2 satır) +
  küçük görsel. Tek ekranda daha fazla yazı görünüyor.

## 2. BKİ sonuçları yaşa göre hesaplanıyor (`de27e47`, 2 Ağustos)

- İdeal BKİ artık herkes için aynı değil, **yaş grubuna göre** değişiyor:
  19-24 yaş → 19-24, 25-34 → 20-25, 35-44 → 21-26, 45-54 → 22-27,
  55-64 → 23-28, 65+ → 24-29.
- Sonuç kartında sırasıyla **İdeal BKİ Aralığı**, **İdeal BKİ** ve
  **İdeal Kilo Aralığı** gösteriliyor. İdeal kilo, kişinin kendi boyu ve yaşına
  göre hesaplanıyor.

## 3. Sonuçlara tek bir "İdeal Kilo" değeri eklendi (`32b1a9b`, 2 Ağustos)

- Aralığın yanı sıra, "senin için ideal kilo kaç kg?" sorusuna tek rakamla cevap
  veren **İdeal Kilo** satırı eklendi (yaşa göre ortalama ideal BKİ × boy²).

## 4. Saat seçimi artık yazarak yapılıyor (`74fca7e`, 2 Ağustos)

- Uygulamadaki **tüm saat seçicileri** (randevu ekleme, randevu düzenleme,
  etkinlik düzenleme, zaman dilimi yönetimi) artık doğrudan **klavyeden saat
  yazma** modunda açılıyor. Yuvarlak kadranı çevirme derdi kalktı.
- Her yerde **24 saat formatı** zorunlu. Önceden iki ekran farklı davranıyor ve
  AM/PM soruyordu; artık tutarlı.

## 5. "Ödeme Alınacak" — planlanan ödeme desteği (`c62d322`, 2 Ağustos)

- Paket eklerken "Ödeme Alındı mı?" seçeneğinin altına **"Ödeme Alınacak mı?"**
  eklendi. İkisi birbirini dışlıyor (aynı anda ikisi işaretlenemez).
- İşaretlenince bir tarih alanı çıkıyor. Kaydedince sistem otomatik olarak
  **"Planlandı" durumunda bir ödeme kaydı** oluşturuyor; tutarı paket ücreti,
  vadesi girilen tarih. Ödeme türü (nakit/kart) tahsil edilene kadar boş kalıyor.
- **Paket düzenlemede**: planlanan ödeme varsa kutu işaretli geliyor ve tarihi
  değiştirilebiliyor; değişiklik ödeme kaydına da yansıyor.
- Planlanan ödeme dururken "Ödeme Alındı" işaretlenemiyor (karışıklık önleniyor).
- Planlanan ödeme kaydı bu ekrandan **asla silinmiyor**; paket ücreti değişirse
  planlanan tutar da otomatik güncelleniyor.

## 6. Sohbette WhatsApp gibi fotoğraf galerisi + okunur butonlar (`3bac76b`, 4 Ağustos)

- Diyetisyen, sohbet ekranında **danışanın adına dokununca** o danışanın gönderdiği
  **tüm fotoğrafları tek sayfada** görüyor (satırda 5 fotoğraf, en yenisi en altta,
  sayfa otomatik en alta kaydırılıyor).
- Fotoğrafa dokununca büyüyor; **öğün tipi ve yükleme tarih/saati** görünüyor.
  Öğünler renk ve ikonla ayrışıyor (kahvaltı turuncu, öğle yeşil, akşam lacivert,
  ara öğün mor).
- Diyetisyenin kendi gönderdiği fotoğraflar bu galeriye karışmıyor.
- **"Toplu Seç"** (Tüm Sohbetler) ve **"Toplu Ekle"** (paketler) butonları artık
  sadece ikon değil, **yazılı buton** — ne işe yaradığı bakınca anlaşılıyor.
- Paket ekleme penceresi **genişletildi**; uzun seçenek isimleri artık kırpılmıyor,
  özellikle telefonda form daha rahat.
- "Ödeme Alınacak" tarihi artık bugüne değil, **paket başlangıç tarihine** göre
  otomatik doluyor.

## 7. Planlanan ödeme tarihi takvimden seçiliyor (`0fb9a9b`, 7 Ağustos)

- "Ödemenin Alınacağı Tarih" elle `gg.aa.yyyy` yazmak yerine, başlangıç tarihi
  gibi **takvimden** seçiliyor. Yanlış format yüzünden alınan hata mesajları bitti.

## 8. Paket adı zorunlu olmaktan çıktı (`da283b5`, 11 Ağustos)

- Paket adı boş bırakılabiliyor; "Lütfen bir paket adı girin" uyarısı kalktı.
  Hızlı paket girişi mümkün.

## 9. "Planım" sayfası iyileştirmeleri (`2b3e79e`, 12 Ağustos)

- Her öğünün altında **"Yüklendi ✓" (yeşil) / "Yüklü Değil ✗" (kırmızı)** durumu
  görünüyor. Bu durum işaret kutusundan **bağımsız** — gerçekten fotoğraf yüklenip
  yüklenmediğini gösteriyor, danışan "yükledim sanmıştım" karışıklığı yaşamıyor.
- Fotoğraf makinesi ikonunun soluna **"Yükle"** yazısı eklendi; ikonun ne yaptığı
  belli.
- Yeni **"Bugün Yüklediğim Fotoğraflar"** butonu: o günün fotoğrafları öğün öğün
  gruplanmış ayrı bir sayfada. Hiç yükleme yoksa boş durum mesajı çıkıyor.

## 10. "Ödeme Alınan Tarih" + masaüstü kısayolu ve ikonu (`5e90a54`, 13 Ağustos)

- Paket eklerken "Ödeme Alındı" seçilince artık **"Ödeme Alınan Tarih"** takvimden
  seçilebiliyor (varsayılan paket başlangıç tarihi). Önceden ödeme tarihi zorunlu
  olarak paket başlangıç tarihi kaydediliyordu; geriye dönük girişler artık doğru.
- Paket düzenlemede bu tarih **salt okunur** (kilit ikonlu) gösteriliyor; değişiklik
  ödemeler sekmesinden yapılıyor.
- Windows kurulumunda masaüstü kısayolu artık **"NGY App"** adıyla geliyor (eskiden
  "IlkApp"); masaüstü uygulaması **mobildeki ile aynı ikonu** kullanıyor.

## 11. Büyük paket: İletişim, tarif PDF'i, sohbet reaksiyonları, login, özet sadeleştirme (`e96a2ff`, 16 Ağustos)

Bu commit birden fazla özelliği birlikte getiriyor:

- **İletişim (i) butonu**: Login ekranına bilgi butonu eklendi. Açılan pencerede
  LinkedIn, Instagram, adres, telefon, WhatsApp, e-posta ve web sitesi var; her
  satıra dokununca ilgili uygulama açılıyor (arama, WhatsApp, harita, mail…).
  Bilgiler koda gömülü değil, ayarlanabilir bir dosyadan okunuyor.
- **"tarifi ektedir" desteği**: Diyet listesinde `*tarifi ektedir` ifadesi geçiyorsa,
  diyetisyen diyeti içeri aktarırken uyarılıyor ve **tarif PDF'ini ekliyor**.
  Danışan "Planım"da o ifadeye dokununca tarif PDF'i açılıyor. İfade büyük/küçük
  harf ve Türkçe i/ı farklarına toleranslı; sadece ifadenin kendisi link oluyor,
  satırın geri kalanı normal metin kalıyor. Diyetisyen tarafında da diyet ekranının
  üstünde PDF'e giden bir bant görünüyor.
- **WhatsApp tarzı reaksiyonlar**: Sohbette mesaja **uzun basınca** 👍 / ❤️
  bırakılabiliyor. Reaksiyon mesajın altında küçük bir rozet olarak görünüyor; aynı
  emojiyi birden fazla kişi bıraktıysa yanında sayı çıkıyor. Aynı emojiye tekrar
  basmak reaksiyonu kaldırıyor.
- **Reaksiyon bildirimi**: Diyetisyen bir mesaja reaksiyon bıraktığında danışana
  bildirim gidiyor: *"bir mesajınıza 👍 ifadesi bıraktı"*. Reaksiyon **kaldırmak**
  bildirim göndermiyor; bildirim yalnızca danışanın kendi mesajlarına bırakılan
  reaksiyonlarda çıkıyor.
- **Login ekranı yeniden düzenlendi**: logo ve form alanı ekran yüksekliğini oranlı
  paylaşıyor; küçük ekranlarda form kendi içinde kayıyor, hiçbir şey ekrandan
  taşmıyor. E-posta ve şifre alanlarına ikon ve açıklama metni eklendi.
- **Danışanlar Özet sadeleşti**: "Paket Adı" ve "Notlar (Paket Bilgisi)" sütunları
  kaldırıldı, sütun aralıkları daraltıldı — tablo yatayda daha az kaydırma
  gerektiriyor. "Ödeme Alınan Tarih" başlığı **"Ödeme Tarihi"** oldu. "Paket Tipi"
  sütunu artık görüşme tipini de gösteriyor: *3 Aylık Yüzyüze*, *1 Aylık Online*,
  hibrit için *Y+O*.
- **Paket adı** girilmesi zorunlu olmaktan tamamen çıktı.
- **Uygulama ikonları** Android, iOS ve macOS için yenilendi.

## 12. Otomatik paket adı + randevu çakışma uyarısı (`d0ad5e8`, 16 Ağustos)

- **Paket adı artık otomatik**: paket tipi ve başlangıç tarihinden üretiliyor
  (ör. `3Aylık_5HaziranBaşlangıç`). Alan **salt okunur**; tarih veya paket tipi
  değişince isim kendiliğinden güncelleniyor. İsimlendirme tüm paketlerde tutarlı.
- **Çakışma uyarısı**: Yeni bir randevu veya etkinlik mevcut bir görüşmeyle
  çakışıyorsa uyarı çıkıyor — *"Bu saatte mevcut görüşme(ler) var: • 123-Ayşe Yılmaz
  (09:30-10:00)"*. Uyarı **engelleyici değil**: "Devam Et" ile bilerek üst üste
  randevu verilebiliyor, "İptal" ile vazgeçilebiliyor.
- **Randevu takviminde** aynı saatte başlayan randevular üst üste binmek yerine
  yan yana kolonlarda gösteriliyor.
- İletişim penceresine **Gizlilik Politikası** ve **Veri İşleme Politikası**
  satırları eklendi (uygulama mağazası şartı).

## 13. Info butonu köşeye, iletişim yazıları tam görünüyor (`ff6dff0`, 16 Ağustos)

- (i) butonu üstteki başlık çubuğundan alınıp **sağ alt köşeye yeşil yuvarlak
  buton** olarak taşındı — başparmakla daha kolay erişiliyor.
- İletişim penceresindeki uzun metinler (özellikle adres) artık **"…" ile
  kesilmiyor**, alt satıra sarıyor. Adresin tamamı okunabiliyor.

## 14. Randevu takvimi Google Calendar gibi çalışıyor (`4c8cd26`, 16 Ağustos)

- Çakışan/birbirini kapsayan randevular **ve etkinlikler** artık tek bir yerleşim
  mantığıyla **yan yana kolonlara** bölünüyor; hiçbir kutu diğerinin üstünü
  kapatmıyor.
- Aynı saatte başlayanlar eşit genişlikte yan yana; biri diğerini kapsıyorsa
  (uzun bir görüşmenin içine kısa bir randevu düşüyorsa) uzun olan solda kalıyor,
  kısa olan sağa kayıyor.
- **Etkinlikler de bu yerleşime dahil edildi** — önceden ayrı bir tam genişlik
  katmanındaydı ve randevuların üstünü kapatıyordu.
- Hem masaüstü haftalık görünümde hem mobil tek-gün görünümünde geçerli.

## 15. Randevu takvimi birleştirme düzeltmesi (`0da6511`, 17 Ağustos)

- Yukarıdaki kolon yerleşimi ile "Tartım" kartı yüksekliği gibi diğer geliştirmeler
  **tek sürümde birleştirildi**. İkisi birden çalışıyor; birleştirme sırasında
  hiçbir özellik kaybolmadı.

## 16. TC/Doğum tarihi, "Tartım" randevusu, tam sayı ödeme, saat kutuları (`90775be`, 17 Ağustos)

- Danışan kişisel bilgilerine **TC No** ve **Doğum Tarihi** eklendi. Doğum tarihi
  elle yazılmıyor, **takvimden** seçiliyor.
- Yeni randevu tipi **"Tartım"**:
  - Varsayılan süresi **5 dakika**.
  - Takvimde çok kısa göründüğü için kartına **okunabilir bir minimum yükseklik**
    veriliyor (kayıtlı süresi değişmiyor).
  - **Paket seans hakkından düşmüyor**: tamamlansa da yakılsa da paketin görüşme
    sayacı artmıyor. Randevu tipi sonradan değiştirilse bile sayaçlar doğru
    kalıyor.
- **Ödeme tutarları artık tam sayı**: kuruş/virgül girilemiyor; `20000.0` yerine
  `20000` görünüyor, "Kalan ödeme" de yuvarlak gösteriliyor.
- Randevu ekleme/düzenlemede **saat iki kutuya (SS : DD) yazılıyor**, tarih ayrı
  bir takvimden seçiliyor. Tarih ve saat girişi birbirinden ayrıldı.
- Randevu tarihindeki **±1 yıl sınırı kaldırıldı** — geçmişe dönük kayıt ve uzağa
  erteleme artık mümkün.
- Sayfa adı **"Admin Randevuları" → "Danışan Randevuları"** oldu.
- "Dosya NO" yazımı **"Dosya No"** olarak düzeltildi.

## 17. Gerçek iletişim bilgileri ve politika bağlantıları (`75b1d9f`, 17 Ağustos)

- Örnek (dummy) bilgiler gerçekleriyle değiştirildi: telefon ve WhatsApp
  `+90 533 284 43 33`, e-posta `dytnilaygoktepe@gmail.com`, gerçek LinkedIn ve
  Instagram hesapları, web sitesi.
- Politika satırları **"Gizlilik/Veri İşleme Politikası"** ve **"Kullanım
  Koşulları"** olarak adlandırıldı ve gerçekten yayınlanmış sayfalara bağlandı.
  Artık tıklayan kullanıcı çalışan bir sayfaya gidiyor.

## 18. Kod birleştirme (`f0a574b`, 17 Ağustos)

- `master` dalının birleştirilmesi. Son kullanıcıya **doğrudan bir etkisi yok**;
  o güne kadarki tüm değişikliklerin aynı sürümde toplanmasını sağlıyor.

## 19. Logo/ikon düzeltmesi (`fb08e0d`, 17 Ağustos)

- Uygulama ikonu **tüm platformlarda** (Android, iOS, macOS, Windows) düzeltildi.
- İkon dosyaları küçültüldü (ör. ana görsel 151 KB → 35 KB) — **kurulum boyutu
  düştü**, ikonlar daha hızlı yükleniyor.
- Kullanılmayan eski ikon dosyaları temizlendi.

## 20. PDF yüklemeleri hızlandı, Windows çökmesi giderildi (`093ab69`, 18 Ağustos)

- Tanita raporu, tahlil/belge ve tarif PDF yüklemeleri artık dosyayı **diskten
  akıtarak** gönderiyor; önce tüm dosyayı belleğe alıp bir de kopyalamıyor.
- **Sonuç**: yükleme belirgin şekilde hızlandı ve Windows'ta büyük ya da çok sayıda
  PDF yüklenirken görülen **ara sıra çökme** sorunu giderildi.
- Dosya başına **50 MB** sınırı kondu; sınırı aşan dosyada net bir mesaj çıkıyor,
  sessizce başarısız olmuyor.

## 21. Yükleme zaman aşımı 2 dakikaya indi (`dc041c3`, 18 Ağustos)

- Bir dosya 2 dakikada tamamlanmazsa kullanıcı sonsuza kadar beklemiyor: yükleme
  iptal ediliyor ve **"2 dakika içinde tamamlanamadı, lütfen tekrar deneyin"**
  mesajı gösteriliyor (önceden 15 dakika bekleniyordu).
- Toplu yüklemelerde **hangi dosyanın tamamlanmadığı** sonuç özetinde belirtiliyor,
  kullanıcı sadece o dosyayı tekrar deneyebiliyor.

## 22. "Geciken Ödemeler" kuralı düzeltildi + danışan sayacı (`5784df7`, 20 Ağustos)

- **Geciken ödeme artık gün bazlı**: bugüne planlanmış bir ödeme, günü daha
  bitmeden gecikmiş sayılmıyor — "Planlanan/Gelecek" olarak görünüyor. Sadece
  **dün ve öncesi** geciken kabul ediliyor.
- Bu kural tek bir yerden yönetiliyor, dolayısıyla **her yerde tutarlı**:
  diyetisyenin "Ödeme Yönetimi" sayfasındaki Geciken sekmesi, sayacı ve
  istatistikleri; ödeme kartındaki kırmızı "gecikmiş" vurgusu; danışanın kendi
  ekranındaki geciken gösterimi ve sıralaması.
- Danışanlar Özet sayfasında her sekmenin sol üstüne **"Toplam Danışan Sayısı"**
  rozeti eklendi — o sekmede kaç danışan listelendiği tek bakışta görünüyor.
- Login ekranındaki info butonu **tam köşeye** oturtuldu (önceki ~16 px boşluk
  kaldırıldı).

## 23. Ölçüm grafiği: "Son Ölçüm" ve "Toplam Değişim" (`8933ac4`, 20 Ağustos)

- Grafiğin sağındaki **haftalık fark** kaldırıldı — tek haftalık dalgalanma yanıltıcı
  olabiliyordu.
- Yerine, her parametre kartının üstünde büyük ve dikkat çekici **"Son Ölçüm"**
  değeri gösteriliyor.
- Altında **"Toplam Değişim"** bandı var: **ilk ölçümden bugüne** toplam fark.
  Düşüş **yeşil**, artış **turuncu**. En az iki ölçüm olduğunda görünüyor.
- Danışan "başladığımdan beri ne kadar yol aldım?" sorusunun cevabını doğrudan
  görüyor.

## 24. Seans sayımı düzeltildi (`3b11beb`, 21 Ağustos)

- Danışanlar Özet'teki **seans sütunları** artık sadece **gerçekten gerçekleşmiş**
  randevuları sayıyor: durumu **"Yapıldı"** veya **"Yakıldı"** olanlar.
- **Ertelenmiş, henüz planlanmış ve iptal edilmiş** randevular artık seans olarak
  görünmüyor. Önceden bunlar da seans sayılıyor, danışan hak ettiğinden az seansı
  kalmış gibi görünüyordu.
- Ertelenen bir randevu yeni tarihinde "Yapıldı" işaretlenince normal şekilde
  seans olarak görünüyor. Ayrı **"Ertelenenler"** sütunu değişmedi.

## 25. Yeni "6 Aylık" paket tipi (`4ef12c2`, 21 Ağustos)

- Üçüncü bir paket süresi eklendi: **6 Aylık** (varsayılan 6 görüşme).
- Bu tip yalnızca **"Aktif/Kilo Takip"** paketlerinde seçilebiliyor; diğer paket
  durumlarında listede hiç görünmüyor.
- Daha önce kaydedilmiş bir 6 Aylık paketin durumu sonradan değişse bile kayıt
  bozulmuyor, tipi olduğu gibi görünmeye devam ediyor (veri kaybı yok).

## 26. Birleştirme (`79f2826`, 21 Ağustos)

- PDF akıtma iyileştirmesi, seans sayımı düzeltmesi ve 6 Aylık paket tipi
  **tek sürümde** toplandı. Kullanıcıya doğrudan yeni bir etkisi yok.

## 27. Kilo Takip paketlerinde tek seçenek: 6 Aylık (`3259b2d`, 21 Ağustos)

- Kural **iki yönlü** hale getirildi: **Kilo Takip** durumu seçilince **tek geçerli
  paket süresi 6 Aylık**; otomatik seçiliyor ve görüşme sayısı da kendiliğinden
  doluyor. Diğer tüm durumlarda yalnızca 1 Aylık / 3 Aylık seçilebiliyor.
- **Paket düzenlemede**, durum Kilo Takip iken paket tipi **kilitli** (değiştirilemez)
  — mevcut bir Kilo Takip paketi yanlışlıkla başka bir süreye çevrilemiyor.
- Diğer durumlarda paket tipi 1/3 Aylık arasında düzenlenebilir kalıyor.

## 28. Birleştirme (`527c72b`, 21 Ağustos)

- Kilo Takip → 6 Aylık kuralı ve düzenleme kilidi **tek sürümde** toplandı.
  Kullanıcıya doğrudan yeni bir etkisi yok.

---

# Kısa Özet (Brief)

## Danışanın (son kullanıcının) doğrudan gördükleri

1. **Girmeden kullanılabilen Blog ve BKİ Hesaplama sayfaları** — yaşa göre ideal
   BKİ, ideal kilo ve ideal kilo aralığı.
2. **Planım sayfasında öğün başına "Yüklendi ✓ / Yüklü Değil ✗"** durumu ve
   "Yükle" yazılı buton.
3. **"Bugün Yüklediğim Fotoğraflar"** sayfası — günün fotoğrafları öğün öğün.
4. **Diyet listesindeki "*tarifi ektedir" ifadesi tıklanabilir** — dokununca tarif
   PDF'i açılıyor.
5. **Sohbette WhatsApp gibi 👍 / ❤️ reaksiyonlar** ve diyetisyen reaksiyon
   bıraktığında gelen bildirim.
6. **Ölçüm sayfasında "Son Ölçüm" ve "Toplam Değişim"** — başlangıçtan bugüne
   toplam fark (düşüş yeşil, artış turuncu).
7. **Login ekranında sağ alt köşede yeşil (i) butonu** — telefon, WhatsApp,
   Instagram, LinkedIn, adres, e-posta, web sitesi, gizlilik/kullanım koşulları.
   Bilgiler gerçek, bağlantılar çalışıyor.
8. **Bugüne planlanan ödeme artık "gecikmiş" görünmüyor** — sadece dün ve öncesi
   geciken sayılıyor.
9. **PDF yüklemeleri çok daha hızlı**, takılırsa 2 dakikada "tekrar deneyin"
   mesajı geliyor (sonsuz bekleme yok).
10. **Yenilenen ve düzeltilen uygulama ikonu**, daha küçük kurulum boyutu.

## Diyetisyenin (yönetici kullanıcının) gördükleri

11. **Sohbette danışanın adına dokununca tüm fotoğrafları tek sayfada** — öğün tipi,
    tarih ve saatiyle.
12. **Randevu takvimi Google Calendar gibi** — çakışan randevu ve etkinlikler yan
    yana, hiçbiri diğerini kapatmıyor.
13. **Çakışma uyarısı** — aynı saate randevu girilirken kimlerle çakıştığı
    listeleniyor; engellemiyor, "Devam Et" denebiliyor.
14. **Yeni "Tartım" randevu tipi** — 5 dakika, takvimde okunur, **paket seans
    hakkından düşmüyor**.
15. **Seans sayımı düzeltildi** — sadece "Yapıldı" ve "Yakıldı" randevular seans
    sayılıyor; ertelenen/planlanan/iptal edilen sayılmıyor.
16. **Paket adı otomatik** oluşuyor (ör. `3Aylık_5HaziranBaşlangıç`), elle yazılmıyor.
17. **"Ödeme Alınacak" (planlanan ödeme)** — ileri tarihli ödeme planlanabiliyor;
    tutar paketle senkron kalıyor, kayıt yanlışlıkla silinmiyor.
18. **"Ödeme Alınan Tarih" seçilebiliyor** — geriye dönük ödeme girişleri doğru
    tarihe yazılıyor.
19. **Ödeme tutarları tam sayı** — kuruş yok, `20000.0` yerine `20000`.
20. **Yeni "6 Aylık" paket tipi** — sadece Kilo Takip paketlerinde, orada da tek
    seçenek; düzenlemede kilitli.
21. **Danışanlar Özet sadeleşti** — gereksiz sütunlar kaldırıldı, "Paket Tipi"
    görüşme tipini de gösteriyor (3 Aylık Yüzyüze / 1 Aylık Online / Y+O),
    her sekmede **"Toplam Danışan Sayısı"** rozeti.
22. **Danışan kartında TC No ve Doğum Tarihi** alanları.
23. **Saat girişi kolaylaştı** — kadran yerine yazarak, her yerde 24 saat formatı;
    randevuda tarih ve saat ayrı ayrı.
24. **Randevu tarihindeki ±1 yıl sınırı kaldırıldı** — geçmiş kayıt ve uzağa
    erteleme mümkün.
25. **Duyuru/Blog ayrımı** — bir yazının nerede görüneceği seçilebiliyor.
26. **"Toplu Seç" / "Toplu Ekle" butonları yazılı** hale geldi.
27. **Tarif PDF'i ekleme akışı** — diyet içeri aktarılırken "tarifi ektedir" ifadesi
    otomatik yakalanıyor ve PDF isteniyor.
28. **Windows masaüstü kısayolu "NGY App"** adıyla ve mobil ile aynı ikonla geliyor.
