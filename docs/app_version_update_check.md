# Uygulama Sürüm Güncelleme Kontrolü

Uygulama her açılışta "daha yeni bir sürüm var mı?" kontrolü yapar ve gerekiyorsa
kullanıcıyı **App Store**'a veya **Google Play**'e yönlendirir.

İlgili dosyalar:

| Dosya | Görevi |
| --- | --- |
| `lib/models/app_update_info.dart` | Firestore dökümanını okur, sürüm karşılaştırmasını yapar, mağaza adresini üretir |
| `lib/providers/app_update_provider.dart` | Firestore'dan `admininput/appVersion` dökümanını çeker |
| `lib/widgets/app_update_gate.dart` | Kontrolü tetikler, uyarıyı/engelleme ekranını gösterir, mağazayı açar |
| `lib/constants/app_constants.dart` | `AppConstants.appVersion` ve `AppUpdateConstants` (paket adı, App Store id, metinler) |

---

## 1. Firestore dökümanı

Kontrol, `admininput/appVersion` dökümanına bakar. **Döküman yoksa hiçbir şey
olmaz** — uygulama bugünkü gibi çalışmaya devam eder. Özelliği açmak için
dökümanı oluşturmak yeterlidir.

Alanların hepsi opsiyoneldir:

| Alan | Tip | Anlamı |
| --- | --- | --- |
| `enabled` | bool | `false` ise kontrol tamamen kapanır. Varsayılan açık. |
| `latestVersion` | string | Yayınlanan en yeni sürüm, ör. `"1.0.2"`. Bundan eskisini kullananlara **kapatılabilir** uyarı çıkar. |
| `minSupportedVersion` | string | Çalışmasına izin verilen en eski sürüm. Bundan eskisini kullananlar **güncelleyene kadar** uygulamayı kullanamaz. |
| `iosLatestVersion` / `androidLatestVersion` | string | Mağazaya özel `latestVersion`. Biri hâlâ incelemedeyken diğeri yayına çıktıysa kullanılır; ortak alanı ezer. |
| `iosMinSupportedVersion` / `androidMinSupportedVersion` | string | Mağazaya özel `minSupportedVersion`. |
| `iosAppId` | string | App Store numarası (`apps.apple.com/app/id...` içindeki rakamlar). |
| `androidPackageName` | string | Play Store listing id'si. Varsayılan `com.utkuyilmaz.ngy_app`. |
| `message` | string | Varsayılan metin yerine gösterilecek kendi yazınız. |

Örnek:

```json
{
  "latestVersion": "1.0.2",
  "minSupportedVersion": "1.0.0",
  "iosAppId": "1234567890"
}
```

Sürümler `1.0.10 > 1.0.9` olacak şekilde sayısal karşılaştırılır; `+11` gibi
build numaraları yok sayılır (mağaza kullanıcıya sürüm adını gösterir, build'i
değil).

## 2. Firestore kuralı

Kontrolün **giriş yapmamış** kullanıcılarda da çalışması için bu dökümanın
herkese açık okunabilir olması gerekir. Aksi hâlde login ekranındaki bir
kullanıcı için okuma reddedilir ve kontrol sessizce atlanır (uygulama yine de
normal çalışır, sadece uyarı çıkmaz).

```
match /admininput/appVersion {
  allow read: if true;
  allow write: if <admin koşulu>;
}
```

## 3. Yeni sürüm çıkarken yapılacaklar

1. `pubspec.yaml` içindeki `version:` alanını yükselt.
2. **`AppConstants.appVersion`'ı da aynı değere getir.** Kontrol bu sabiti
   karşılaştırır; burası unutulursa güncel kullanıcılara da "güncelleyin"
   uyarısı çıkmaya devam eder.
3. Build mağazada yayına çıktıktan **sonra** Firestore'daki `latestVersion`'ı
   güncelle. Önce güncellenirse kullanıcılar mağazada olmayan bir sürüme
   yönlendirilir.
4. Zorunlu güncelleme gerekiyorsa `minSupportedVersion`'ı ayrıca yükselt.

## 4. iOS notu

`AppUpdateConstants.iosAppId` şu an boş. App Store numarası bu sabite ya da
Firestore dökümanındaki `iosAppId` alanına girilene kadar kontrol **iOS'ta
sessiz kalır** — kullanıcıya hiçbir yere gitmeyen bir buton göstermemek için.
Android tarafı paket adı bilindiği için ek ayar istemez.

## 5. Oturumun etkilenmemesi

Kontrol, Firebase Auth'a hiç dokunmaz: kullanıcıyı okumaz, çıkış yaptırmaz ve
auth stream'inin önüne geçmez. `AppUpdateGate`, `AuthWrapper`'ı hemen kurar ve
kontrol arka planda dönerken oturum her zamanki gibi geri yüklenir. Zorunlu
güncelleme ekranı açıkken bile alttaki uygulama ağacı ayakta kalır.

Kontrolün başarısız olduğu her durum (ağ yok, döküman yok, okuma izni yok,
6 saniyelik zaman aşımı, bozuk veri) "güncelleme yok" olarak sonuçlanır; hiçbiri
kullanıcıyı uygulamanın önünde bekletmez.
