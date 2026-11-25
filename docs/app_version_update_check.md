# Uygulama Sürüm Güncelleme Kontrolü

Uygulama her açılışta "daha yeni bir sürüm var mı?" kontrolü yapar ve gerekiyorsa
kullanıcıyı **App Store**'a veya **Google Play**'e yönlendirir.

> **Sadece mobil.** Kontrol yalnızca **iOS** ve **Android**'de çalışır.
> **Windows ve macOS**'ta hiç devreye girmez: karşılaştırma yapılmaz, Firestore
> okunmaz, uyarı veya engelleme ekranı gösterilmez. Bu build'ler elle kuruluyor,
> yönlendirilecek bir mağaza listelemesi yok. Ayrıntı için aşağıdaki
> "5. Platform sınırı".

İlgili dosyalar:

| Dosya | Görevi |
| --- | --- |
| `lib/models/app_update_info.dart` | Firestore dökümanını okur, sürüm karşılaştırmasını yapar, mağaza adresini üretir |
| `lib/providers/app_update_provider.dart` | Firestore'dan `admininput/appVersion` dökümanını çeker; kurulu sürümü `package_info_plus` ile okur |
| `lib/widgets/app_update_gate.dart` | Kontrolü tetikler, uyarıyı/engelleme ekranını gösterir, mağazayı açar; `MaterialApp.builder`'da, gezginin (Navigator) üstünde durur |
| `lib/constants/app_constants.dart` | `AppUpdateConstants` (paket adı, App Store id, metinler) |
| `test/app_update_info_test.dart`, `test/app_update_gate_test.dart` | Karar mantığının ve ekranın testleri (iOS, Android, masaüstü) |

---

## 1. Firestore dökümanı

Kontrol, `admininput/appVersion` dökümanına bakar. **Döküman yoksa hiçbir şey
olmaz** — uygulama bugünkü gibi çalışmaya devam eder.

Alanların hepsi opsiyoneldir:

| Alan | Tip | Anlamı |
| --- | --- | --- |
| `isCheckVersion` | boolean | Ana anahtar. `false` ise uygulama bu özellik hiç eklenmemiş gibi davranır: karşılaştırma yok, uyarı yok, engelleme yok. Alan yoksa `true` kabul edilir. Konsolda tipi **boolean** kalmalı: metin olarak yazılmış `"false"` kontrolü kapatmaz. |
| `latestVersion` | string | Yayınlanan en yeni sürüm, ör. `"1.0.4"`. Bundan eskisini kullananlara **kapatılabilir** uyarı çıkar. iOS ve Android'in ikisini de etkiler. |
| `minSupportedVersion` | string | Çalışmasına izin verilen en eski sürüm. Bundan eskisini kullananlar **güncelleyene kadar** uygulamayı kullanamaz. iOS ve Android'in ikisini de etkiler. |
| `iosLatestVersion` / `androidLatestVersion` | string | Mağazaya özel `latestVersion`; ortak alanı ezer. Biri hâlâ incelemedeyken diğeri yayına çıktıysa ya da yalnızca bir mağaza hedefleniyorsa kullanılır. |
| `iosMinSupportedVersion` / `androidMinSupportedVersion` | string | Mağazaya özel `minSupportedVersion`. |
| `iosAppId` | string | App Store numarası. **Adres (URL) değil, yalnızca rakamlar:** `6756973059`. Mağaza adresini uygulama bundan kendisi kurar: önce `itms-apps://itunes.apple.com/app/id6756973059` (App Store uygulaması), açılmazsa `https://apps.apple.com/app/id6756973059`. |
| `androidPackageName` | string | Play Store listing id'si. Varsayılan `com.utkuyilmaz.ngy_app`. |
| `message` | string | Varsayılan metin yerine gösterilecek kendi yazınız. |

Sürüm alanları konsolda **string** tipinde girilir. Sayı tipindeki ya da
`1.0.x` gibi sayı olmayan bir değer yok sayılır: yazım hatası kimseyi
kilitlemez, ama o alan da işe yaramaz. Boş metin (`""`) alan hiç yokmuş gibi
sayılır.

Önerilen hâl (yalnızca iOS'u 1.0.4'e zorlar, Android'e dokunmaz):

```json
{
  "isCheckVersion": true,
  "iosAppId": "6756973059",
  "iosLatestVersion": "1.0.4",
  "iosMinSupportedVersion": "1.0.4"
}
```

App Store'a çıkan 1.0.4, iOS uygulamasının UIScene yaşam döngüsüne geçtiği ilk
sürüm (25 Kasım 2026'dan sonraki build'ler; TestFlight'taki 3–5 Kasım tarihli
eski 1.0.4 build'lerinde bu düzeltme yok). Xcode 27 (iOS 27 SDK) ile derlenmiş
önceki build'ler (mağazadaki 1.0.3 dahil) iOS 27'de açılır açılmaz kapanıyor;
iOS 27'deki kullanıcıya bu uyarı da gösterilemez, uygulamayı ancak App Store'dan
güncelleyerek açabilir. Bu yüzden 1.0.4 mağazada yayına çıkınca
`iosMinSupportedVersion` 1.0.4 yapılır: iOS 26'daki kullanıcılar iOS 27'ye
geçmeden güncellemiş olur.

Kontrolü tamamen kapatmak için tek yapılacak `isCheckVersion`'ı `false` yapmak;
uygulama sürümü yeniden yayınlamaya gerek kalmadan eski davranışına döner.

Sürümler `1.0.10 > 1.0.9` olacak şekilde sayısal karşılaştırılır; `+11` gibi
build numaraları yok sayılır (mağaza kullanıcıya sürüm adını gösterir, build'i
değil).

### Android

Kasım 2026 itibarıyla Google Play'de `com.utkuyilmaz.ngy_app` için herkese açık
bir sayfa yok. Ortak `latestVersion` / `minSupportedVersion` alanları Android'i
de etkiler ve kullanıcıyı açılmayan bir Play sayfasına gönderir; zorunlu
güncellemede Android kullanıcısı çıkışsız kalır. Uygulama Play'de yayına
çıkana kadar yalnızca `ios...` alanları kullanılır.

## 2. Firestore kuralı

Kurallar `firestore.rules`'da ve Firebase Console'da aynı tutulur. Kontrol login
ekranında da çalıştığı için yalnızca bu döküman herkese açık; `admininput`
altındaki diğer her şey girişli kullanıcıya açık:

```
match /admininput/appVersion {
  allow read: if true;
}

match /admininput/{document=**} {
  allow read: if isAuth();
}
```

İki blok çakışmıyor: Firestore'da eşleşen `allow` kuralları **VEYA**'lanır, yani
daha dar olan blok geniş olanı ezmez, sadece ek izin verir. Yazma için ayrı
kural gerekmiyor; en üstteki `match /{document=**} { allow read, write: if
isAdmin(); }` bloğu admin yazmalarını zaten karşılıyor.

Dışarı açılan veri: sürüm numaraları, App Store id'si, paket adı ve uyarı
metni. Hepsi zaten mağaza listelemesinden görülebilen bilgiler; kişisel veri
yok.

## 3. Yeni sürüm çıkarken yapılacaklar

1. `pubspec.yaml` içindeki `version:` alanını yükselt. Kontrol, kurulu
   uygulamanın sürümünü (`package_info_plus`: iOS'ta
   `CFBundleShortVersionString`, Android'de `versionName`) okur; bu sürüm
   `pubspec.yaml`'dan gelir, başka bir yerde elle güncellenecek sabit yok.
2. Build mağazada **yayına çıktıktan ve mağaza sayfasında yeni sürüm
   göründükten sonra** Firestore'daki `iosLatestVersion`'ı (Play'de yayındaysa
   `androidLatestVersion`'ı ya da ortak `latestVersion`'ı) güncelle. Önce
   güncellenirse kullanıcılar mağazada olmayan bir sürüme yönlendirilir; zorunlu
   güncellemede mağazada "Güncelle" yerine "Aç" görüp ekranda kalırlar.
3. Zorunlu güncelleme gerekiyorsa `iosMinSupportedVersion`'ı (ya da ilgili
   alanı) da yeni sürüme yükselt.
4. `isCheckVersion`'ın `true` olduğundan emin ol.

Değişiklik kullanıcıya bir sonraki açılışta yansır: arka planda açık duran
uygulama, kapatılıp yeniden açılana kadar denetlenmez. Zorunlu güncelleme
ekranındaki kullanıcı ise uygulamaya her dönüşünde yeniden denetlenir; yönetici
zorunluluğu kaldırırsa yeniden başlatmadan uygulamaya döner.

### 5 Kasım 2026 öncesi build'ler (mağazadaki 1.0.3 dahil)

- 5 Kasım 2026'dan önce derlenen build'ler sürümü elle tutulan bir sabitten
  okuyordu; mağazadaki 1.0.3 ve TestFlight'taki eski 1.0.4 build'leri dahil
  hepsi kendini **1.0.2** olarak bildirir. Sonraki build'ler sürümü
  `package_info_plus` ile gerçekten okur ve mağazaya 1.0.4 olarak çıkar (repoda
  bir süre 1.0.5 ve 1.0.6 yazan sürüm, mağazada 1.0.3'ten sonra yayına çıkan
  olmadığı için 1.0.4'e çekildi). Bu yüzden:
  - En düşük sürüm 1.0.2'den büyük olduğu sürece eski build'lerin hepsi
    engellenir; mağazadaki 1.0.4 kurulunca engel kalkar.
  - Mağazada 1.0.4 yayına çıkmadan en yeni ya da en düşük sürüme `1.0.3` ya da
    `1.0.4` yazılmaz: 1.0.3 kullananlara mağazada daha yenisi yokken güncelleme
    söylenir, zorunluysa çıkışsız kalırlar.
- Bu build'lerde App Store numarası uygulamanın içinde boştu: Firestore'da
  `iosAppId: "6756973059"` yoksa kontrol iOS'ta **sessiz kalır** (kullanıcıya
  hiçbir yere gitmeyen bir buton göstermemek için).
- Kontrol 21 Eylül 2026'da eklendi; ondan önce derlenmiş build'leri kullananlara
  hiçbir uyarı gösterilemez.

## 4. iOS notu

`AppUpdateConstants.iosAppId` App Store numarasını (`6756973059`) tutar;
Firestore dökümanındaki `iosAppId` alanı onu ezer, alan yoksa ya da boşsa bu
sabit kullanılır. 5 Kasım 2026 öncesi build'ler için yukarıdaki nota bakın. Android
tarafı paket adı bilindiği için ek ayar istemez; ama Play'de yayında değilken
Android'i hedefleyen alanlar kullanılmaz (bkz. "Android").

## 5. Platform sınırı (sadece iOS/Android)

Tek kaynak: `AppUpdateProvider.isSupported` → `defaultTargetPlatform` Android
ya da iOS (web hariç). Testlerde `TargetPlatformVariant` /
`debugDefaultTargetPlatformOverride` ile her platform denenir.

Kontrol iki ayrı yerde bu bayrağa bakar, böylece masaüstünde bir uyarıya giden
hiçbir kod yolu kalmaz:

1. **`AppUpdateGate`** — masaüstünde `child`'ı olduğu gibi döndürür; lifecycle
   observer eklemez, ilk frame sonrası kontrolü hiç planlamaz, `Stack`/engelleme
   katmanı kurmaz. Yani widget ağaca girse bile tamamen şeffaftır.
2. **`AppUpdateProvider.checkForUpdate`** — masaüstünde Firestore'a gitmeden
   `null` döner. Widget dışından çağrılsa bile sonuç değişmez.

macOS'ta `defaultTargetPlatform` macOS olduğu için kontrol kapalıdır. Apple
Silicon Mac'lerde "Designed for iPad" olarak çalışan iOS build'i ise iOS
verir; o gerçekten bir App Store uygulaması olduğu için kontrolün çalışması
doğrudur.

## 6. Ekranın yeri ve oturumun etkilenmemesi

`AppUpdateGate`, `MaterialApp.builder`'da gezginin (Navigator) üstünde durur.
Zorunlu güncelleme ekranı o an açık olan her sayfayı ve diyaloğu örter:
denetim bitmeden açılmış bir sayfa (ör. açılışta hemen girilen Sohbet) da
ekranın altında kalır, klavye odağı alttaki uygulamadan alınır. Mağaza
açılamazsa hata diyalog yerine ekranın kendisinde yazar (diyalog ekranın altında
kalırdı). İsteğe bağlı güncelleme penceresi gezginin anahtarıyla açılır.

Kasım 2026'daki bu düzeltmeden önceki build'lerde (mağazadaki 1.0.3 dahil)
ekran ana sayfa rotasındaydı: denetim bitmeden açılan sayfa ekranın üstünde
kalıyor, kullanıcı ancak ana sayfaya dönünce engelleniyordu.

Kontrol, Firebase Auth'a hiç dokunmaz: kullanıcıyı okumaz, çıkış yaptırmaz ve
auth stream'inin önüne geçmez. Gezgin ve ilk sayfası `AuthWrapper` hemen
kurulur; kontrol arka planda dönerken oturum her zamanki gibi geri yüklenir.
Zorunlu güncelleme ekranı açıkken bile alttaki uygulama ağacı ayakta kalır;
bildirime basınca açılacak sayfa ilk denetim bitene ve engel kalkana kadar
bekletilir (`NotificationTapGate`).

Kontrolün başarısız olduğu her durum (ağ yok, döküman yok, okuma izni yok,
6 saniyelik zaman aşımı, bozuk veri, `isCheckVersion: false`) "güncelleme yok"
olarak sonuçlanır; hiçbiri kullanıcıyı uygulamanın önünde bekletmez.
