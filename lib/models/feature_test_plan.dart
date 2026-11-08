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
  openNotifications(Icons.notifications_outlined, 'Bildirim Merkezi'),
  openDocumentControl(Icons.fact_check_outlined, 'Doküman Kontrol');

  const FeatureTestShortcut(this.icon, this.label);

  final IconData icon;
  final String label;
}

enum FeatureTestTool {
  reminderCalculator(Icons.event_repeat_rounded, 'Hatırlatma hesaplayıcı'),
  upcomingReminders(Icons.pending_actions_rounded, 'Bekleyen hatırlatmalar'),
  notificationSimulator(Icons.notification_add_outlined, 'Bildirim simülatörü'),
  notificationStatus(Icons.insights_rounded, 'Anlık durum'),
  scanPreview(Icons.manage_search_rounded, 'Tarama önizlemesi'),
  birthdayPreview(Icons.cake_outlined, 'Doğum günü önizlemesi'),
  enterKeys(Icons.keyboard_alt_outlined, 'Enter deneme alanı'),
  timeMachine(Icons.fast_forward_rounded, 'Zaman makinesi');

  const FeatureTestTool(this.icon, this.label);

  final IconData icon;
  final String label;
}

enum FeatureTestSpeed {
  realTime(1, 'Gerçek zaman'),
  dayInFiveMinutes(288, '1 gün = 5 dk'),
  dayInMinute(1440, '1 gün = 1 dk'),
  dayInTenSeconds(8640, '1 gün = 10 sn');

  const FeatureTestSpeed(this.factor, this.label);

  final int factor;
  final String label;

  DateTime realTimeOf(DateTime simulated, DateTime start) {
    if (!simulated.isAfter(start)) return start;
    return start.add(Duration(
        microseconds: simulated.difference(start).inMicroseconds ~/ factor));
  }
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
  final List<FeatureTestTool> tools;

  const FeatureTestSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.color,
    this.note,
    required this.steps,
    this.shortcuts = const [],
    this.tools = const [],
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
    title: 'Dokümanlar: Kan Tahlili ve Hatırlatma',
    icon: Icons.bloodtype_outlined,
    color: Color(0xFFE53935),
    steps: [
      FeatureTestStep(
        'dok.sekme',
        'Daha önce doküman yüklenmiş bir danışanın Dokümanlar sekmesini açın.',
        'Üstte "Kan Tahlili (N)" ve "Diğer (N)" sekmeleri vardır. Kan tahlili sorusundan önce yüklenen bütün dokümanlar Diğer\'dedir; Diğer\'in başında "N dokümanın türü belirtilmemiş" notu, Kan Tahlili boşsa oraya yönlendiren "Diğer sekmesine git" düğmesi görünür.',
      ),
      FeatureTestStep(
        'dok.kalem',
        'Bir satırın en sağındaki kalem simgesinin üzerine gelin (telefonda basılı tutun).',
        '"Düzenle" yazısı çıkar; kalem, Sil düğmesinin sağındadır.',
      ),
      FeatureTestStep(
        'dok.evet',
        'Diğer\'deki eski bir kan tahlilinin kalemine basın ve "Bu bir kan tahlili mi?" sorusunda "Kan Tahlili sekmesine taşı"yı seçin.',
        '"Tahlilin Yapıldığı Tarih" kırmızı "Tarih seçin" olarak görünür; tarih seçilmeden "Kan Tahlili\'ne Taşı" düğmesi pasiftir. Altında 3 aylık takibin bu tarihe göre hesaplandığı, yükleme gününün kullanılmadığı yazar.',
      ),
      FeatureTestStep(
        'dok.tasi',
        'Tahlilin gerçekte yapıldığı tarihi (ör. 1 ay önce) seçip "Kan Tahlili\'ne Taşı"ya basın.',
        'Bilgi mesajı dosyanın taşındığını ve hatırlatma gününü yazar; dosya Diğer\'den kalkar, Kan Tahlili\'nde "Tahlil tarihi" ve "Hatırlatma" rozetleriyle görünür; sekme sayıları değişir; Detay\'daki kan değerleri kartı "Evet" olur.',
      ),
      FeatureTestStep(
        'dok.hayir',
        'Diğer\'de kan tahlili olmayan eski bir dokümanın kalemine basıp "Hayır"ı seçin ve Kaydet\'e basın.',
        'Doküman Diğer\'de kalır; "türü belirtilmemiş" notundaki sayı bir azalır (hepsi seçilince not kalkar).',
      ),
      FeatureTestStep(
        'kan.sec',
        'Kan Tahlili sekmesinde "Kan Tahlili Yükle" ile bir veya birkaç dosya seçin.',
        '"Kan Tahlili Yükle" penceresi dosyaları listeler; "Bu bir kan tahlili mi?" sorulmaz; tarih seçilmeden Yükle pasiftir; danışanın kayıtlı tahlil tarihleri tek dokunuşla seçilebilen çipler olarak görünür.',
      ),
      FeatureTestStep(
        'kan.isaret',
        'Tarihi seçin ve "3 ay sonra hatırlatıcı istiyor musunuz?" kutusuna bakın.',
        'Kutu işaretli gelir; hatırlatmaların günü ve saati yazar (3 ay dolmadan 1 gün önce ve 3 ayın dolduğu gün, 09:00).',
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
        'Bilgi mesajında tahlil tarihi ve hatırlatma günü yazar; listede "Tahlil tarihi" ve "Hatırlatma" rozetleri görünür; aşağıdaki "Bekleyen hatırlatmalar"da danışan seçilince iki "Bekliyor" hatırlatma (1 gün kala ve 3 ay doldu) görünür.',
      ),
      FeatureTestStep(
        'kan.detay',
        'Aynı danışanın Detay sekmesine bakın.',
        '"Danışanın kan değerleri dokümanı mevcut mu?" kartında "Evet" seçilidir.',
      ),
      FeatureTestStep(
        'dok.tarih',
        'Hatırlatmalı bir tahlilin kalemine basıp tarihini değiştirin ve Kaydet\'e basın (birlikte yüklenen birden çok dosyası olan bir tahlille deneyin).',
        'Pencerede "Aynı tarihli diğer N dosyaya da uygula" işaretli gelir; kaydedince bütün sayfalar yeni tarihe geçer; "Bekleyen hatırlatmalar"da eski tarihin hatırlatmaları kalkar, yeni tarihinkiler görünür.',
      ),
      FeatureTestStep(
        'kan.eskiyukle',
        'Aynı danışana, en yeni tahlilden daha eski tarihli bir kan tahlilini hatırlatıcı açık yükleyin.',
        'Bilgi mesajı, daha yeni tarihli tahlil olduğu için 3 ay hatırlatmasının kurulmadığını söyler; bekleyen hatırlatmalar değişmez; eski tahlilin satırında "Hatırlatma" rozeti çıkmaz (rozet yalnızca en yeni tahlilde görünür).',
      ),
      FeatureTestStep(
        'kan.yeniyukle',
        'Başka bir danışana 1 ay önceki tarihle hatırlatıcı açık, ardından bugünün tarihiyle hatırlatıcı kapalı birer kan tahlili yükleyin.',
        'İkinci yüklemeden sonra "Bekleyen hatırlatmalar"da o danışan seçilince ilk tahlilin iki hatırlatması artık görünmez.',
      ),
      FeatureTestStep(
        'kan.eski',
        'Kan tahlili olmayan bir danışana, tarihi 3 aydan eski (ör. 4 ay önce) bir kan tahlilini hatırlatıcı açık yükleyin.',
        'Pencerede "üzerinden 3 ay geçmiş" uyarısı çıkar; yükleyince zilin Sistem sekmesine "Kan tahlilinin üzerinden 3 ay geçti" hemen düşer; satırda turuncu "3 ay doldu" rozeti görünür.',
      ),
      FeatureTestStep(
        'kan.normal',
        'Diğer sekmesinde "Doküman Yükle" ile bir dosya yükleyin.',
        'Hiçbir soru sorulmadan yüklenir; Diğer\'de rozetsiz görünür, hatırlatma kurulmaz.',
      ),
      FeatureTestStep(
        'dok.geri',
        'İki kan tahlili olan bir danışanda en yeni tahlilin kalemine basın, "Diğer sekmesine taşı"yı seçip "Diğer\'e Taşı"ya basın.',
        'Dosya Diğer\'e geçer ve tahlil tarihi silinir; bilgi mesajı en yeni tahlilin artık bir önceki olduğunu ve 3 ay hatırlatmasının ona göre kurulduğunu söyler; Doküman Kontrol bu danışanı önceki tahlilin tarihiyle gösterir.',
      ),
      FeatureTestStep(
        'kan.sil',
        'Hatırlatmalı bir kan tahlili dosyasını silin.',
        'O tarihin başka dosyası yoksa onay mesajı hatırlatmanın da kalkacağını söyler; silince hatırlatmaları "Bekleyen hatırlatmalar"dan (danışan seçiliyken) kalkar.',
      ),
      FeatureTestStep(
        'dok.son',
        'Danışanın son kan tahlilini silin ya da Diğer\'e taşıyın.',
        '"Kan Tahlili Kalmadı" sorusu çıkar; "Hayır" olarak işaretlenirse Detay\'daki kart "Hayır" olur, "Evet" kalsın denirse değişmez.',
      ),
    ],
    shortcuts: [
      FeatureTestShortcut.openUsers,
      FeatureTestShortcut.openNotifications,
    ],
    tools: [
      FeatureTestTool.reminderCalculator,
      FeatureTestTool.upcomingReminders,
    ],
  ),
  FeatureTestSection(
    id: 'teslim',
    title: 'Bildirimin Gelmesi (uygulama açık / kapalı)',
    icon: Icons.notifications_active_outlined,
    color: Color(0xFF5E35B1),
    note:
        'Simülatörün kurduğu bildirimler yalnızca sizin hesabınıza gelir, diğer adminler görmez; zilde "DENEME" etiketiyle görünür. Hesabınızın açık olduğu bütün cihazlara gelir. Android, uygulama arka plandayken bildirimi birkaç dakika geciktirebilir.',
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
      FeatureTestStep(
        'teslim.danisansil',
        'Silinecek bir deneme danışanı için simülatörle 5 dk sonraya "Kan tahlili · 3 ay doldu" kurun, sonra danışanı Kullanıcı Yönetimi\'nden silin.',
        '5 dakika dolunca bu bildirim gelmez; silinen danışanın bekleyen hatırlatmaları da silinmiştir.',
      ),
      FeatureTestStep(
        'teslim.cikis',
        'Süresi dolmamış bir deneme bildirimi kurup hesaptan çıkış yapın.',
        'Süre dolunca bu cihaza sistem bildirimi gelmez; yeniden girince bildirim zilde görünür ve şeritle duyurulur.',
      ),
    ],
    shortcuts: [FeatureTestShortcut.openNotifications],
    tools: [FeatureTestTool.notificationSimulator],
  ),
  FeatureTestSection(
    id: 'zaman',
    title: 'Zaman Makinesi (hızlandırılmış bildirim testi)',
    icon: Icons.fast_forward_rounded,
    color: Color(0xFF00838F),
    note:
        'Danışan seçtiğiniz tarihte eklenmiş (ve isterseniz kan tahlili seçtiğiniz tarihte yapılmış) gibi kabul edilir; zaman çizelgesi uygulamanın gerçek kurallarıyla hesaplanır ve bildirimler seçtiğiniz hızla kurulur. Danışanın kaydı değişmez; bildirimler yalnızca size gelir ve "DENEME" etiketlidir.',
    steps: [
      FeatureTestStep(
        'zaman.liste',
        'Eklenmeyi "5 gün önce", kan tahlilini "Yok", hızı "1 gün = 1 dk" seçip "Başlat"a basın.',
        'Çizelgedeki "listesine girer" satırında yazan sürede (birkaç dakika) zile "DENEME" etiketli "Kan tahlili eksik danışanlar (1)" düşer.',
      ),
      FeatureTestStep(
        'zaman.gecmis',
        'Eklenmeyi "10 gün önce" seçip başlatın.',
        'Liste hemen düşer; çizelgenin altında Doküman Kontrol durumu "İlk kan tahlili yüklenmedi" yazar.',
      ),
      FeatureTestStep(
        'zaman.tahlil',
        'Kan tahlilini "2 gün sonra 3 ay doluyor" seçip başlatın.',
        '"Kan tahlili yarın 3 ayı dolduruyor" ve ardından "Kan tahlilinin üzerinden 3 ay geçti" çizelgedeki sürelerde düşer.',
      ),
      FeatureTestStep(
        'zaman.kapali',
        'Başlattıktan hemen sonra uygulamayı arka plana alın ya da kapatın.',
        'Süreler dolunca telefonda ve Mac\'te sistem bildirimi gelir; Windows\'ta uygulamaya dönünce şerit çıkar.',
      ),
      FeatureTestStep(
        'zaman.gercek',
        'Gerçek bir danışan seçip başlatın; düşen hatırlatmadaki "Danışanı aç"a basın.',
        'Seçilen danışanın sayfası açılır; danışanın kendi kayıtları değişmemiştir.',
      ),
      FeatureTestStep(
        'zaman.sil',
        '"Deneme bildirimlerini sil"e basın.',
        'Henüz düşmemiş olanlar dahil bütün deneme bildirimleri kalkar.',
      ),
    ],
    shortcuts: [FeatureTestShortcut.openNotifications],
    tools: [FeatureTestTool.timeMachine],
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
      FeatureTestStep(
        'zil.acikken',
        'Simülatörde 10 sn seçip bildirimi kurun; hemen "Bildirim Merkezi"ni Sohbet sekmesinde açın ve gelen bildirime dokunun.',
        'Merkez açık kalır ve Sistem sekmesine geçer; bildirim okundu olur.',
      ),
    ],
    shortcuts: [
      FeatureTestShortcut.openNotifications,
      FeatureTestShortcut.openChats,
    ],
    tools: [FeatureTestTool.notificationStatus],
  ),
  FeatureTestSection(
    id: 'tarama',
    title: 'Günlük Kan Tahlili Taraması',
    icon: Icons.assignment_late_outlined,
    color: Color(0xFFF57C00),
    note:
        'Tarama normalde günde bir kez, saat 09:00\'dan sonra uygulaması açık olan ilk admin cihazında kendiliğinden yapılır. Önizleme hiçbir şeyi değiştirmez; "Gerçek taramayı çalıştır" bu kuralı atlayıp hemen tarar ve listeyi bütün adminlere gönderir.',
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
    tools: [FeatureTestTool.scanPreview],
  ),
  FeatureTestSection(
    id: 'dokuman',
    title: 'Doküman Kontrol',
    icon: Icons.fact_check_outlined,
    color: Color(0xFFC62828),
    steps: [
      FeatureTestStep(
        'dokuman.ac',
        'Ana sayfadaki "Doküman Kontrol" simgesine basın.',
        'Doküman Kontrol sayfası açılır.',
      ),
      FeatureTestStep(
        'dokuman.kontrol',
        '"Kan tahlillerini kontrol et"e basın.',
        'İlerleme gösterilir; bitince bütün danışanlar listelenir. En üstte "Gecikmiş" olanlar (3 ayı dolan ya da 1 haftadır ilk tahlili yüklenmeyen), en çok geciken en üstte.',
      ),
      FeatureTestStep(
        'dokuman.kart',
        '"Durum" çiplerine ("Gecikmiş (N)", "Yaklaşan (N)" vb.) basın ve aramayı deneyin.',
        'Liste seçilen duruma ve yazılan isme göre süzülür; "Tümü" yeniden hepsini gösterir.',
      ),
      FeatureTestStep(
        'dokuman.ac2',
        'Bir satıra basın.',
        'Danışanın sayfası açılır.',
      ),
      FeatureTestStep(
        'dokuman.yukle',
        'Gecikmiş bir danışana bugünün tarihiyle kan tahlili yükleyip yeniden kontrol edin.',
        'Danışan "Güncel"e geçer; 3 ayın dolacağı tarih ve kalan gün yazar.',
      ),
      FeatureTestStep(
        'dokuman.tarihsiz',
        'Detay\'da "Evet" seçili ama tarihli kan tahlili yüklenmemiş bir danışana bakın.',
        '"Tarihi bilinmiyor" grubunda görünür.',
      ),
    ],
    shortcuts: [
      FeatureTestShortcut.openDocumentControl,
      FeatureTestShortcut.openUsers,
    ],
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
    tools: [FeatureTestTool.birthdayPreview],
  ),
  FeatureTestSection(
    id: 'enter',
    title: 'Sohbette Enter ile Gönderme',
    icon: Icons.keyboard_return_rounded,
    color: Color(0xFF1E88E5),
    note:
        'Deneme alanı sohbetteki yazı kutusunun tuş kurallarının aynısını kullanır; kimseye mesaj gitmez.',
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
    tools: [FeatureTestTool.enterKeys],
  ),
];
