import 'package:flutter/material.dart';

enum FeatureTestResult {
  passed('passed', 'Geçti'),
  failed('failed', 'Hatalı'),
  skipped('skipped', 'Atlandı');

  const FeatureTestResult(this.value, this.label);

  final String value;
  final String label;

  static FeatureTestResult? fromValue(Object? value) {
    for (final FeatureTestResult result in values) {
      if (result.value == value) return result;
    }
    return null;
  }
}

enum FeatureTestFilter {
  all('all', 'Tümü'),
  open('open', 'Yapılmadı'),
  failed('failed', 'Hatalı');

  const FeatureTestFilter(this.value, this.label);

  final String value;
  final String label;

  static FeatureTestFilter fromValue(Object? value) {
    for (final FeatureTestFilter filter in values) {
      if (filter.value == value) return filter;
    }
    return all;
  }

  bool matches(FeatureTestResult? result) {
    switch (this) {
      case FeatureTestFilter.all:
        return true;
      case FeatureTestFilter.open:
        return result == null;
      case FeatureTestFilter.failed:
        return result == FeatureTestResult.failed;
    }
  }
}

enum FeatureTestShortcut {
  openUsers(Icons.people_alt_outlined, 'Kullanıcı Yönetimi'),
  openSummary(Icons.table_chart_outlined, 'Danışanlar Özet'),
  openAppointments(Icons.calendar_month_outlined, 'Randevu Yönetimi'),
  openChats(Icons.forum_outlined, 'Tüm Sohbetler'),
  openNotifications(Icons.notifications_outlined, 'Bildirim Merkezi');

  const FeatureTestShortcut(this.icon, this.label);

  final IconData icon;
  final String label;
}

enum FeatureTestTool {
  reminderCalculator(Icons.event_repeat_rounded, 'Hatırlatma hesaplayıcı'),
  notificationSimulator(
      Icons.notification_add_outlined, 'Bildirim simülatörü'),
  notificationStatus(Icons.insights_rounded, 'Anlık durum'),
  scanPreview(Icons.manage_search_rounded, 'Tarama önizlemesi'),
  birthdayPreview(Icons.cake_outlined, 'Doğum günü önizlemesi'),
  enterKeys(Icons.keyboard_alt_outlined, 'Enter deneme alanı');

  const FeatureTestTool(this.icon, this.label);

  final IconData icon;
  final String label;
}

String featureTestPlatformLabel(TargetPlatform platform) {
  switch (platform) {
    case TargetPlatform.android:
      return 'Android';
    case TargetPlatform.iOS:
      return 'iPhone / iPad';
    case TargetPlatform.macOS:
      return 'macOS';
    case TargetPlatform.windows:
      return 'Windows';
    case TargetPlatform.linux:
      return 'Linux';
    case TargetPlatform.fuchsia:
      return 'Fuchsia';
  }
}

class FeatureTestStep {
  final String id;
  final String action;
  final String expected;
  final Set<TargetPlatform> platforms;
  final bool isCustom;

  const FeatureTestStep(
    this.id,
    this.action,
    this.expected, {
    this.platforms = const {},
    this.isCustom = false,
  });

  bool appliesTo(TargetPlatform platform) =>
      platforms.isEmpty || platforms.contains(platform);
}

class FeatureTestSection {
  final String id;
  final String title;
  final IconData icon;
  final Color color;
  final String? note;
  final List<FeatureTestStep> steps;
  final List<FeatureTestShortcut> shortcuts;
  final FeatureTestTool? tool;

  const FeatureTestSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.note,
    required this.steps,
    this.shortcuts = const [],
    this.tool,
  });
}

const List<FeatureTestSection> featureTestSections = [
  FeatureTestSection(
    id: 'kilo',
    title: 'Kilo Takibe Geçiş Tarihi',
    icon: Icons.monitor_weight_outlined,
    color: Color(0xFF00897B),
    steps: [
      FeatureTestStep(
        'kilo.ekle',
        'Bir danışana yeni paket ekleyin, Paket Tipi olarak "Aktif/Kilo Takip" seçin.',
        '"Kilo Takibe Geçiş Tarihi" satırı bugünün tarihiyle görünür ve tarih değiştirilebilir.',
      ),
      FeatureTestStep(
        'kilo.kart',
        'Paketi kaydedip danışanın Paket sekmesindeki karta bakın.',
        'Kartta "Kilo Takibe Geçiş: <tarih>" satırı görünür.',
      ),
      FeatureTestStep(
        'kilo.eski',
        'Tarihi girilmemiş eski bir Kilo Takip paketini düzenleyin.',
        'Bugünün tarihi önerilir, altında turuncu "kayıtlı bir tarih yok" notu çıkar; tarih seçince not kalkar ve kaydedilir.',
      ),
      FeatureTestStep(
        'kilo.ozet',
        'Danışanlar Özet sayfasında "Aktif / Kilo Takip" sekmesini açın.',
        '"Kilo Takibe Geçiş Tarihi" sütunu görünür; tarihi girilmemiş danışanlarda turuncu "Girilmemiş" yazar.',
      ),
      FeatureTestStep(
        'kilo.haftalik',
        'Aynı sayfada "Aktif / Haftalık" ve "Dondurulmuş" sekmelerine bakın.',
        'Bu sekmelerde kilo takibe geçiş sütunu yoktur.',
      ),
    ],
    shortcuts: [FeatureTestShortcut.openUsers, FeatureTestShortcut.openSummary],
  ),
  FeatureTestSection(
    id: 'kan',
    title: 'Kan Tahlili Yükleme ve Hatırlatma',
    icon: Icons.bloodtype_outlined,
    color: Color(0xFFE53935),
    steps: [
      FeatureTestStep(
        'kan.sec',
        'Bir danışanın Dokümanlar sekmesinde "Tahlil Ekle" ile bir veya birkaç dosya seçin.',
        '"Doküman Yükle" penceresi açılır ve seçilen dosyaları listeler.',
      ),
      FeatureTestStep(
        'kan.isaret',
        '"Bu bir kan tahlili mi?" kutusunu işaretleyin.',
        'Tahlil tarihi ve "3 ay sonra hatırlatıcı istiyor musunuz?" seçenekleri açılır; hatırlatmaların günü ve saati yazar (3 ay dolmadan 1 gün önce ve 3 ayın dolduğu gün, 09:00).',
      ),
      FeatureTestStep(
        'kan.hesap',
        'Aşağıdaki hesaplayıcıda pencerede seçtiğiniz tarihi seçin.',
        'Hesaplayıcı penceredeki hatırlatma günlerinin ve saatlerinin aynısını gösterir.',
      ),
      FeatureTestStep(
        'kan.ayson',
        'Hesaplayıcıda "30 Kasım" ve "31 Ağustos" gibi ay sonu tarihlerini deneyin.',
        'Hatırlatma günü 3 ay sonrasının aynı günüdür; o ay daha kısaysa ayın son günüdür (31 Ağustos → 30 Kasım, 30 Kasım → 28 Şubat ya da artık yılda 29 Şubat).',
      ),
      FeatureTestStep(
        'kan.yukle',
        'Yükle\'ye basın.',
        'Bilgi mesajında tahlil tarihi ve hatırlatma günü yazar; listede "Kan tahlili" ve "Hatırlatma" rozetleri görünür.',
      ),
      FeatureTestStep(
        'kan.detay',
        'Aynı danışanın Detay sekmesine bakın.',
        '"Danışanın kan değerleri dokümanı mevcut mu?" kartında "Evet" seçilidir.',
      ),
      FeatureTestStep(
        'kan.eski',
        'Tahlil tarihi olarak 3 aydan eski bir gün (ör. 4 ay önce) seçip hatırlatıcı açıkken bir kan tahlili daha yükleyin.',
        'Pencerede "üzerinden 3 ay geçmiş" uyarısı çıkar; yükleyince zilin Sistem sekmesine "Kan tahlilinin üzerinden 3 ay geçti" hemen düşer.',
      ),
      FeatureTestStep(
        'kan.normal',
        'Kutuyu işaretlemeden normal bir doküman yükleyin.',
        'Rozet çıkmaz, hatırlatma kurulmaz.',
      ),
      FeatureTestStep(
        'kan.sil',
        'Hatırlatmalı bir kan tahlili dosyasını silin.',
        'Onay mesajı hatırlatmanın da kalkacağını söyler; o tarihin başka dosyası kalmadıysa bekleyen hatırlatma silinir.',
      ),
    ],
    shortcuts: [
      FeatureTestShortcut.openUsers,
      FeatureTestShortcut.openNotifications,
    ],
    tool: FeatureTestTool.reminderCalculator,
  ),
  FeatureTestSection(
    id: 'teslim',
    title: 'Bildirimin Gelmesi (uygulama açık / kapalı)',
    icon: Icons.notifications_active_outlined,
    color: Color(0xFF5E35B1),
    note: 'Simülatörün kurduğu bildirimler yalnızca sizin hesabınıza gelir, diğer adminler görmez; zilde "DENEME" etiketiyle görünür. Hesabınızın açık olduğu bütün cihazlara gelir. Android, uygulama arka plandayken bildirimi birkaç dakika geciktirebilir.',
    steps: [
      FeatureTestStep(
        'teslim.acik',
        'Simülatörde bir tür ve süre seçip "Bildirimi kur"a basın; uygulamayı açık tutun.',
        'Süre dolunca mor bildirim şeridi çıkar (Android\'de telefonun kendi bildirimi); zilin sayısı artar.',
      ),
      FeatureTestStep(
        'teslim.kapali',
        'Yine kurun, sonra uygulamayı arka plana alın ya da tamamen kapatın.',
        'Süre dolunca telefonda ve Mac\'te sistem bildirimi gelir. Windows\'ta sistem bildirimi yoktur; uygulamaya dönünce şerit çıkar.',
      ),
      FeatureTestStep(
        'teslim.dokun',
        'Gelen bildirime ya da mor şeride dokunun.',
        'Bildirim merkezi "Sistem" sekmesinde açılır ve bildirim okundu olur (kırmızı nokta kalkar).',
      ),
      FeatureTestStep(
        'teslim.turler',
        'Simülatörde bir danışan seçip "Kan tahlili · 1 gün kala" ve "Kan tahlili · 3 ay doldu" türlerini kurun.',
        'Satırlar gerçek hatırlatmalarla aynı görünür (turuncu ve kırmızı simge); "Danışanı aç" çipi danışanın sayfasını açar.',
      ),
      FeatureTestStep(
        'teslim.cihaz',
        'Aynı hesabın açık olduğu başka bir cihaza (ör. bilgisayar) bakın.',
        'Kurulan bildirim orada da zile düşer.',
      ),
      FeatureTestStep(
        'teslim.tekrar',
        'Uygulamayı kapatıp yeniden açın.',
        'Daha önce gösterilmiş bildirim için şerit tekrar çıkmaz.',
      ),
      FeatureTestStep(
        'teslim.sil',
        'Süresi dolmamış bir deneme bildirimi kurup "Deneme bildirimlerini sil"e basın.',
        'Deneme bildirimleri zilden kalkar; silinen bildirim süresi dolunca da gelmez.',
      ),
    ],
    shortcuts: [FeatureTestShortcut.openNotifications],
    tool: FeatureTestTool.notificationSimulator,
  ),
  FeatureTestSection(
    id: 'zil',
    title: 'Zil ve Bildirim Merkezi',
    icon: Icons.notifications_none_rounded,
    color: Color(0xFF8E24AA),
    steps: [
      FeatureTestStep(
        'zil.yer',
        'Ana sayfada sağ üstteki "Bildirimler" ziline bakın.',
        'Okunmamış bildirim varsa kırmızı sayı rozeti görünür; danışan hesabında zil yoktur.',
      ),
      FeatureTestStep(
        'zil.ac',
        'Zile basın.',
        'Geniş ekranda zilin altında panel, telefonda tam sayfa açılır; "Sohbet" sekmesi seçili gelir.',
      ),
      FeatureTestStep(
        'zil.foto',
        'Bir test danışanının hesabıyla sohbetten öğün fotoğrafı yükleyin.',
        'Fotoğraf Sohbet sekmesinde küçük resmi, öğünü ve saatiyle görünür; solunda kırmızı nokta vardır.',
      ),
      FeatureTestStep(
        'zil.sohbet',
        'Sohbet sekmesindeki bildirime basın.',
        'Sohbet o fotoğrafın mesajında açılır; geri dönünce kırmızı nokta kalkar.',
      ),
      FeatureTestStep(
        'zil.dun',
        'Ertesi gün Sohbet sekmesine bakın.',
        'Yalnızca o günün öğün fotoğrafları listelenir.',
      ),
      FeatureTestStep(
        'zil.sistem',
        '"Sistem" sekmesine geçin.',
        'Bildirimler Bugün / Dün / Bu Hafta / Daha Eski diye gruplanır; okunmamışların solunda kırmızı nokta vardır.',
      ),
      FeatureTestStep(
        'zil.okundu',
        'Bir sistem bildirimine basın, sonra "Tümünü okundu say"a basın.',
        'Basılan bildirim okundu olur; ardından hepsi okundu olur ve aşağıdaki anlık durumda okunmamış sayısı 0\'a iner.',
      ),
      FeatureTestStep(
        'zil.danisan',
        'Bir kan tahlili hatırlatmasındaki "Danışanı aç" çipine basın.',
        'Danışanın sayfası açılır.',
      ),
    ],
    shortcuts: [
      FeatureTestShortcut.openNotifications,
      FeatureTestShortcut.openChats,
    ],
    tool: FeatureTestTool.notificationStatus,
  ),
  FeatureTestSection(
    id: 'tarama',
    title: 'Günlük Kan Tahlili Taraması',
    icon: Icons.assignment_late_outlined,
    color: Color(0xFFF57C00),
    note: 'Tarama normalde günde bir kez, saat 09:00\'dan sonra uygulaması açık olan ilk admin cihazında kendiliğinden yapılır. Önizleme hiçbir şeyi değiştirmez; "Gerçek taramayı çalıştır" bu kuralı atlayıp hemen tarar ve listeyi bütün adminlere gönderir.',
    steps: [
      FeatureTestStep(
        'tarama.detay',
        'Bir danışanın Detay sekmesinde "Danışanın kan değerleri dokümanı mevcut mu?" kartında Evet ve Hayır\'a basın.',
        'Seçim hemen kaydedilir (altta bilgi mesajı çıkar); sayfadan çıkıp girince korunur.',
      ),
      FeatureTestStep(
        'tarama.onizle',
        'Önizlemede gün "Bugün" iken "Önizle"ye basın.',
        'Listeye girecek danışanlar ve 1 haftası dolmamış yeni danışanlar (listeye girecekleri günle) ayrı ayrı görünür.',
      ),
      FeatureTestStep(
        'tarama.yeni',
        'Yeni bir danışan ekleyin; önizlemeyi "Bugün" ve "8 gün sonra" için tekrarlayın.',
        'Detay\'da "Hayır" seçilidir; bugün bekleyenler arasında, 8 gün sonrası için listede görünür.',
      ),
      FeatureTestStep(
        'tarama.evet',
        'Listedeki bir danışanı "Evet" yapıp önizlemeyi yenileyin.',
        'Danışan listeden çıkar.',
      ),
      FeatureTestStep(
        'tarama.bana',
        '"Önizlemeyi bana bildir"e basın.',
        'Zilin Sistem sekmesine "DENEME" etiketli "Kan tahlili eksik danışanlar (N)" düşer; isim çipleri danışanın sayfasını açar, 6\'dan fazla isim varsa "+N daha" çıkar.',
      ),
      FeatureTestStep(
        'tarama.gercek',
        '"Gerçek taramayı çalıştır"a basın.',
        'Kaç danışanın listelendiği yazar ve "Son tarama" güncellenir; Sistem sekmesindeki bugünün listesi bu sonuca göre güncellenir.',
      ),
      FeatureTestStep(
        'tarama.otomatik',
        'Ertesi gün uygulamayı saat 09:00\'dan sonra açıp bu sayfaya bakın.',
        '"Son tarama" o günün tarihine döner (tarama kendiliğinden bir kez yapılır); yeni liste gelince önceki günün listesi okunmuş sayılır.',
      ),
    ],
    shortcuts: [FeatureTestShortcut.openUsers],
    tool: FeatureTestTool.scanPreview,
  ),
  FeatureTestSection(
    id: 'dg',
    title: 'Takvimde Doğum Günleri',
    icon: Icons.cake_outlined,
    color: Color(0xFFD81B60),
    steps: [
      FeatureTestStep(
        'dg.onizle',
        'Önizlemede "Yaklaşan doğum günleri" listesinden bir güne basın.',
        'O gün doğan danışanlar takvimdeki gibi pembe "DG: Ad Soyad" etiketiyle görünür; etiketin üzerinde durunca kaç yaşına girdiği yazar.',
      ),
      FeatureTestStep(
        'dg.tarih',
        'Bir danışanın doğum tarihini bugünün gün ve ayına ayarlayın (Detay > Düzenle).',
        'Kayıt güncellenir; önizlemeyi yenileyince "Bugün" için görünür.',
      ),
      FeatureTestStep(
        'dg.takvim',
        'Randevu Yönetimi\'ni açın (açıksa "Yenile"ye basın).',
        'Bugünün tarihinin hemen altında pembe "DG: Ad Soyad" etiketi görünür.',
      ),
      FeatureTestStep(
        'dg.hafta',
        'Geniş ekranda haftalık görünüme bakın.',
        'Doğum günü olan günün başlığı uzar; saat çizgileri bütün günlerde hizalı kalır.',
      ),
      FeatureTestStep(
        'dg.telefon',
        'Telefonda günlük görünüme bakın.',
        'Etiket gün başlığının ("Bugün" rozetinin) altında görünür.',
      ),
      FeatureTestStep(
        'dg.renk',
        'Ayarlar > Randevu Arkaplan Renkleri > "Doğum Günü (DG)" rengini değiştirip kaydedin, sonra bu sayfayı yeniden açın.',
        'Önizlemedeki ve takvimdeki etiketin rengi değişir; "Varsayılan"a dönünce yeniden pembe olur.',
      ),
    ],
    shortcuts: [
      FeatureTestShortcut.openUsers,
      FeatureTestShortcut.openAppointments,
    ],
    tool: FeatureTestTool.birthdayPreview,
  ),
  FeatureTestSection(
    id: 'enter',
    title: 'Sohbette Enter ile Gönderme',
    icon: Icons.keyboard_return_rounded,
    color: Color(0xFF1E88E5),
    note: 'Deneme alanı sohbetteki yazı kutusunun tuş kurallarının aynısını kullanır; kimseye mesaj gitmez.',
    steps: [
      FeatureTestStep(
        'enter.alan',
        'Deneme alanına bir şey yazıp Enter\'a basın.',
        'Bilgisayarda ve iPad/Mac klavyesinde "Gönderildi" kaydı düşer ve kutu boşalır; Android\'de ve ekran klavyesinde Enter yeni satır açar.',
      ),
      FeatureTestStep(
        'enter.shift',
        'Deneme alanında yazarken Shift+Enter\'a basın.',
        'Gönderilmez, yeni satıra geçer.',
      ),
      FeatureTestStep(
        'enter.esc',
        '"Yanıt modu"nu açıp deneme alanındayken Esc\'e basın.',
        'Yanıt şeridi kapanır ve "Yanıt iptal edildi" kaydı düşer.',
      ),
      FeatureTestStep(
        'enter.windows',
        'Windows\'ta gerçek bir sohbette mesaj yazıp Enter\'a basın.',
        'Mesaj gider; Shift+Enter yeni satır açar.',
        platforms: {TargetPlatform.windows},
      ),
      FeatureTestStep(
        'enter.mac',
        'Mac\'te (masaüstü uygulaması ya da App Store\'dan kurulan iPad sürümü) gerçek bir sohbette deneyin.',
        'Enter gönderir, Shift+Enter yeni satır açar.',
        platforms: {TargetPlatform.macOS, TargetPlatform.iOS},
      ),
      FeatureTestStep(
        'enter.ipad',
        'iPad\'de donanım klavyesiyle, iPhone\'da ekran klavyesiyle deneyin.',
        'iPad klavyesinde Enter gönderir; ekran klavyesinde Enter her zamanki gibi yeni satırdır.',
        platforms: {TargetPlatform.iOS},
      ),
    ],
    shortcuts: [FeatureTestShortcut.openChats],
    tool: FeatureTestTool.enterKeys,
  ),
];
