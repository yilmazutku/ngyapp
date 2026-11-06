import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/admin_notifications_provider.dart';
import '../providers/blood_test_provider.dart';
import '../services/notification_service.dart';
import '../tabs/admin_images_page.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../widgets/home_button.dart';
import '../widgets/labeled_action_button.dart';
import 'admin_appointments_page.dart';
import 'admin_chat_page.dart';
import 'admin_notifications_page.dart';
import 'danisanlar_ozet_page.dart';

class FeatureTestPage extends StatefulWidget {
  const FeatureTestPage({super.key});

  static const String title = 'Yeni Özellik Testleri';

  @override
  State<FeatureTestPage> createState() => _FeatureTestPageState();
}

class _TestStep {
  final String id;
  final String action;
  final String expected;

  const _TestStep(this.id, this.action, this.expected);
}

enum _TestTool {
  openSummary(Icons.table_chart_outlined, 'Danışanlar Özet'),
  openUsers(Icons.people_alt_outlined, 'Kullanıcı Yönetimi'),
  openAppointments(Icons.calendar_month_outlined, 'Randevu Yönetimi'),
  openChats(Icons.forum_outlined, 'Tüm Sohbetler'),
  openNotifications(Icons.notifications_outlined, 'Bildirim Merkezi'),
  testNotification(Icons.alarm_add_rounded, '1 dk sonra deneme hatırlatması'),
  removeTestNotifications(
      Icons.delete_sweep_outlined, 'Deneme bildirimlerini sil'),
  scanNow(Icons.manage_search_rounded, 'Taramayı şimdi çalıştır');

  const _TestTool(this.icon, this.label);

  final IconData icon;
  final String label;

  bool get isPrimary => this == testNotification || this == scanNow;
}

class _TestSection {
  final String title;
  final IconData icon;
  final Color color;
  final String? note;
  final List<_TestStep> steps;
  final List<_TestTool> tools;

  const _TestSection({
    required this.title,
    required this.icon,
    required this.color,
    this.note,
    required this.steps,
    required this.tools,
  });
}

const List<_TestSection> _sections = [
  _TestSection(
    title: 'Kilo Takibe Geçiş Tarihi',
    icon: Icons.monitor_weight_outlined,
    color: Color(0xFF00897B),
    steps: [
      _TestStep(
        'kilo.ekle',
        'Bir danışana yeni paket ekleyin, Paket Tipi olarak "Aktif/Kilo Takip" seçin.',
        '"Kilo Takibe Geçiş Tarihi" satırı bugünün tarihiyle görünür ve tarih değiştirilebilir.',
      ),
      _TestStep(
        'kilo.kart',
        'Paketi kaydedip danışanın Paket sekmesindeki karta bakın.',
        'Kartta "Kilo Takibe Geçiş: <tarih>" satırı görünür.',
      ),
      _TestStep(
        'kilo.eski',
        'Tarihi girilmemiş eski bir Kilo Takip paketini düzenleyin.',
        'Bugünün tarihi önerilir, altında turuncu "kayıtlı bir tarih yok" notu çıkar; tarih seçince not kalkar ve kaydedilir.',
      ),
      _TestStep(
        'kilo.ozet',
        'Danışanlar Özet sayfasında "Aktif / Kilo Takip" sekmesini açın.',
        '"Kilo Takibe Geçiş Tarihi" sütunu görünür; tarihi girilmemiş danışanlarda turuncu "Girilmemiş" yazar.',
      ),
      _TestStep(
        'kilo.haftalik',
        'Aynı sayfada "Aktif / Haftalık" ve "Dondurulmuş" sekmelerine bakın.',
        'Bu sekmelerde kilo takibe geçiş sütunu yoktur.',
      ),
    ],
    tools: [_TestTool.openUsers, _TestTool.openSummary],
  ),
  _TestSection(
    title: 'Kan Tahlili Yükleme ve Hatırlatma',
    icon: Icons.bloodtype_outlined,
    color: Color(0xFFE53935),
    steps: [
      _TestStep(
        'kan.sec',
        'Bir danışanın Dokümanlar sekmesinde "Tahlil Ekle" ile bir veya birkaç dosya seçin.',
        '"Doküman Yükle" penceresi açılır ve seçilen dosyaları listeler.',
      ),
      _TestStep(
        'kan.isaret',
        '"Bu bir kan tahlili mi?" kutusunu işaretleyin.',
        'Tahlil tarihi ve "3 ay sonra hatırlatıcı istiyor musunuz?" seçenekleri açılır; hatırlatmaların günü ve saati (1 gün önce ve 3 ayın dolduğu gün, 09:00) yazar.',
      ),
      _TestStep(
        'kan.yukle',
        'Yükle\'ye basın.',
        'Bilgi mesajında tahlil tarihi ve hatırlatma günü yazar; listede "Kan tahlili" ve "Hatırlatma" rozetleri görünür.',
      ),
      _TestStep(
        'kan.detay',
        'Aynı danışanın Detay sekmesine bakın.',
        '"Danışanın kan değerleri dokümanı mevcut mu?" kartında "Evet" seçilidir.',
      ),
      _TestStep(
        'kan.eski',
        'Tahlil tarihi olarak 3 aydan eski bir gün (ör. 4 ay önce) seçip hatırlatıcı açıkken bir kan tahlili daha yükleyin.',
        'Pencerede "üzerinden 3 ay geçmiş" uyarısı çıkar; yükleyince zilin Sistem sekmesine "Kan tahlilinin üzerinden 3 ay geçti" hemen düşer.',
      ),
      _TestStep(
        'kan.normal',
        'Kutuyu işaretlemeden normal bir doküman yükleyin.',
        'Rozet çıkmaz, hatırlatma kurulmaz.',
      ),
      _TestStep(
        'kan.sil',
        'Hatırlatmalı bir kan tahlili dosyasını silin.',
        'Onay mesajı hatırlatmanın da kalkacağını söyler; o tarihin başka dosyası kalmadıysa bekleyen hatırlatma silinir.',
      ),
    ],
    tools: [_TestTool.openUsers, _TestTool.openNotifications],
  ),
  _TestSection(
    title: 'Bildirimin Gelmesi (uygulama açık / kapalı)',
    icon: Icons.notifications_active_outlined,
    color: Color(0xFF5E35B1),
    note: 'Deneme hatırlatması yalnızca sizin hesabınıza gelir, diğer adminler görmez. Hesabınızın açık olduğu bütün cihazlara gelir.',
    steps: [
      _TestStep(
        'teslim.acik',
        '"1 dk sonra deneme hatırlatması"na basın ve uygulamayı açık tutun.',
        '1 dakika sonra mor bildirim şeridi çıkar (Android\'de telefonun kendi bildirimi); zilin sayısı artar.',
      ),
      _TestStep(
        'teslim.kapali',
        'Tekrar kurun, sonra uygulamayı arka plana alın ya da tamamen kapatın.',
        '1 dakika sonra telefonda ve Mac\'te sistem bildirimi gelir (Windows\'ta yalnızca uygulama açıkken gelir).',
      ),
      _TestStep(
        'teslim.dokun',
        'Gelen bildirime ya da mor şeride dokunun.',
        'Bildirim merkezi "Sistem" sekmesinde açılır ve deneme bildirimi okundu olur (kırmızı nokta kalkar).',
      ),
      _TestStep(
        'teslim.cihaz',
        'Aynı hesabın açık olduğu başka bir cihaza (ör. bilgisayar) bakın.',
        'Deneme hatırlatması orada da zile düşer.',
      ),
      _TestStep(
        'teslim.tekrar',
        'Uygulamayı kapatıp yeniden açın.',
        'Daha önce gösterilmiş bildirim için şerit tekrar çıkmaz.',
      ),
    ],
    tools: [
      _TestTool.testNotification,
      _TestTool.removeTestNotifications,
      _TestTool.openNotifications,
    ],
  ),
  _TestSection(
    title: 'Zil ve Bildirim Merkezi',
    icon: Icons.notifications_none_rounded,
    color: Color(0xFF8E24AA),
    steps: [
      _TestStep(
        'zil.yer',
        'Ana sayfada sağ üstteki "Bildirimler" ziline bakın.',
        'Okunmamış bildirim varsa kırmızı sayı rozeti görünür; danışan hesabında zil yoktur.',
      ),
      _TestStep(
        'zil.ac',
        'Zile basın.',
        'Bilgisayarda zilin altında panel, telefonda tam sayfa açılır; "Sohbet" sekmesi seçili gelir.',
      ),
      _TestStep(
        'zil.foto',
        'Simge\'nin ya da bir test danışanın hesabıyla sohbetten öğün fotoğrafı yükleyin.',
        'Fotoğraf Sohbet sekmesinde küçük resmi, öğünü ve saatiyle görünür; solunda kırmızı nokta vardır.',
      ),
      _TestStep(
        'zil.sohbet',
        'Sohbet sekmesindeki bildirime basın.',
        'Sohbet o fotoğrafın mesajında açılır; geri dönünce kırmızı nokta kalkar.',
      ),
      _TestStep(
        'zil.dun',
        'Ertesi gün Sohbet sekmesine bakın.',
        'Yalnızca o günün öğün fotoğrafları listelenir.',
      ),
      _TestStep(
        'zil.sistem',
        '"Sistem" sekmesine geçin.',
        'Bildirimler Bugün / Dün / Bu Hafta / Daha Eski diye gruplanır; okunmamışların solunda kırmızı nokta vardır.',
      ),
      _TestStep(
        'zil.okundu',
        'Bir sistem bildirimine basın, sonra "Tümünü okundu say"a basın.',
        'Basılan bildirim okundu olur; ardından hepsi okundu olur ve zilin sayısı düşer.',
      ),
      _TestStep(
        'zil.danisan',
        'Hatırlatmadaki "Danışanı aç" çipine basın.',
        'Danışanın sayfası açılır.',
      ),
    ],
    tools: [_TestTool.openNotifications, _TestTool.openChats],
  ),
  _TestSection(
    title: 'Günlük Kan Tahlili Taraması',
    icon: Icons.assignment_late_outlined,
    color: Color(0xFFF57C00),
    note: 'Tarama normalde günde bir kez, saat 09:00\'dan sonra uygulaması açık olan ilk admin cihazında kendiliğinden yapılır. Buradaki düğme bu kuralı atlayıp hemen tarar.',
    steps: [
      _TestStep(
        'tarama.detay',
        'Bir danışanın Detay sekmesinde "Danışanın kan değerleri dokümanı mevcut mu?" kartında Evet ve Hayır\'a basın.',
        'Seçim hemen kaydedilir (altta bilgi mesajı çıkar); sayfadan çıkıp girince korunur.',
      ),
      _TestStep(
        'tarama.calistir',
        '"Taramayı şimdi çalıştır"a basın.',
        'Kaç danışanın listelendiği yazar; zilin Sistem sekmesine "Kan tahlili eksik danışanlar (N)" düşer ve isimler çip olarak görünür.',
      ),
      _TestStep(
        'tarama.cip',
        'Listedeki bir isim çipine basın.',
        'Danışanın sayfası açılır.',
      ),
      _TestStep(
        'tarama.evet',
        'Listedeki bir danışanı "Evet" yapın ve taramayı tekrar çalıştırın.',
        'Danışan listeden çıkar.',
      ),
      _TestStep(
        'tarama.yeni',
        'Yeni bir danışan ekleyin.',
        'Detay\'da "Hayır" seçilidir; eklendiği günden 1 hafta geçmeden listede çıkmaz.',
      ),
      _TestStep(
        'tarama.otomatik',
        'Ertesi gün uygulamayı saat 09:00\'dan sonra açın.',
        'Tarama kendiliğinden bir kez yapılır; yeni liste gelince önceki günün listesi okunmuş sayılır.',
      ),
    ],
    tools: [_TestTool.scanNow, _TestTool.openUsers],
  ),
  _TestSection(
    title: 'Takvimde Doğum Günleri',
    icon: Icons.cake_outlined,
    color: Color(0xFFD81B60),
    steps: [
      _TestStep(
        'dg.tarih',
        'Bir danışanın doğum tarihini bugünün gün ve ayına ayarlayın (Detay > Düzenle).',
        'Kayıt başarıyla güncellenir.',
      ),
      _TestStep(
        'dg.takvim',
        'Randevu Yönetimi\'ni açın (açıksa "Yenile"ye basın).',
        'Bugünün tarihinin hemen altında pembe "DG: Ad Soyad" etiketi görünür; üzerine gelince girdiği yaş yazar.',
      ),
      _TestStep(
        'dg.hafta',
        'Bilgisayarda haftalık görünüme bakın.',
        'Doğum günü olan günün başlığı uzar; saat çizgileri bütün günlerde hizalı kalır.',
      ),
      _TestStep(
        'dg.telefon',
        'Telefonda günlük görünüme bakın.',
        'Etiket gün başlığının ("Bugün" rozetinin) altında görünür.',
      ),
      _TestStep(
        'dg.renk',
        'Ayarlar > Randevu Arkaplan Renkleri > "Doğum Günü (DG)" rengini değiştirip kaydedin.',
        'Takvimdeki etiketin rengi değişir.',
      ),
    ],
    tools: [_TestTool.openUsers, _TestTool.openAppointments],
  ),
  _TestSection(
    title: 'Sohbette Enter ile Gönderme',
    icon: Icons.keyboard_return_rounded,
    color: Color(0xFF1E88E5),
    steps: [
      _TestStep(
        'enter.windows',
        'Windows\'ta bir sohbette mesaj yazıp Enter\'a basın.',
        'Mesaj gider.',
      ),
      _TestStep(
        'enter.shift',
        'Mesaj yazarken Shift+Enter\'a basın.',
        'Mesaj gitmez, yeni satıra geçer.',
      ),
      _TestStep(
        'enter.mac',
        'Mac\'te (masaüstü uygulaması ya da App Store\'dan kurulan iPad sürümü) aynısını deneyin.',
        'Enter gönderir, Shift+Enter yeni satır açar.',
      ),
      _TestStep(
        'enter.ipad',
        'iPad\'de klavyeyle, iPhone\'da ekran klavyesiyle deneyin.',
        'iPad klavyesinde Enter gönderir; ekran klavyesinde Enter her zamanki gibi yeni satırdır.',
      ),
      _TestStep(
        'enter.esc',
        'Bir mesajı yanıtlarken Esc\'e basın.',
        'Yanıt iptal olur.',
      ),
    ],
    tools: [_TestTool.openChats],
  ),
];

class _FeatureTestPageState extends State<FeatureTestPage> {
  static const String _prefsKey = 'featureTestChecklist.v1';
  static const String _resetLabel = 'Sıfırla';

  final Set<String> _done = {};

  int get _total => _sections.fold(0, (sum, s) => sum + s.steps.length);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final List<String> saved = prefs.getStringList(_prefsKey) ?? const [];
      if (!mounted) return;
      setState(() => _done.addAll(saved));
    } catch (e) {
      return;
    }
  }

  Future<void> _save() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _done.toList());
    } catch (e) {
      return;
    }
  }

  void _toggle(String id) {
    setState(() {
      if (!_done.remove(id)) _done.add(id);
    });
    _save();
  }

  Future<void> _reset() async {
    final bool confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Listeyi Sıfırla',
      message: 'Bütün işaretler kaldırılacak. Devam etmek istiyor musunuz?',
      confirmText: _resetLabel,
      cancelText: 'Vazgeç',
    );
    if (!confirmed || !mounted) return;
    setState(_done.clear);
    _save();
  }

  Future<void> _runTool(_TestTool tool) async {
    switch (tool) {
      case _TestTool.openSummary:
        await _push(const DanisanlarOzetPage());
      case _TestTool.openUsers:
        await _push(const AdminUsersPage());
      case _TestTool.openAppointments:
        await _push(const AdminAppointmentsPage());
      case _TestTool.openChats:
        await Navigator.of(context).push(AdminChatListPage.route());
      case _TestTool.openNotifications:
        await openAdminNotificationCenter(context);
      case _TestTool.testNotification:
        await _scheduleTestNotification();
      case _TestTool.removeTestNotifications:
        await _removeTestNotifications();
      case _TestTool.scanNow:
        await _scanNow();
    }
  }

  Future<void> _push(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _scheduleTestNotification() async {
    final AdminNotificationsProvider notifications =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    final DateTime fireAt = DateTime.now().add(const Duration(minutes: 1));
    try {
      await notifications.addTestNotification(fireAt: fireAt);
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Deneme hatırlatması ${DateFormatter.formatTime(fireAt)} civarında '
          'düşecek. Uygulamayı açık tutun ya da arka plana alın.',
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Deneme hatırlatması kurulamadı: $e',
      );
    }
  }

  Future<void> _removeTestNotifications() async {
    final AdminNotificationsProvider notifications =
        Provider.of<AdminNotificationsProvider>(context, listen: false);
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    try {
      final int removed = await notifications.removeTestNotifications();
      messenger.showSnackBar(SnackBar(
        content: Text(removed == 0
            ? 'Silinecek deneme bildirimi yok.'
            : '$removed deneme bildirimi silindi.'),
      ));
    } catch (e) {
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Deneme bildirimleri silinemedi: $e',
      );
    }
  }

  Future<void> _scanNow() async {
    final String? uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final BloodTestProvider bloodTests =
        Provider.of<BloodTestProvider>(context, listen: false);
    final LoadingDialog loading =
        DialogUtils.openLoading(context, message: 'Danışanlar taranıyor...');
    try {
      final int? count = await bloodTests.runDailyScan(
        uid: uid,
        now: DateTime.now(),
        force: true,
      );
      loading.close();
      if (!mounted) return;
      await DialogUtils.openInfo(
        context,
        title: 'Tarama tamamlandı',
        message: (count ?? 0) == 0
            ? 'Kan tahlili eksik danışan bulunmadı.'
            : '$count danışanın kan tahlili eksik. Zildeki "Sistem" '
                'sekmesinde "Kan tahlili eksik danışanlar" bildirimine bakın.',
      );
    } catch (e) {
      loading.close();
      if (!mounted) return;
      await DialogUtils.openError(
        context,
        title: 'Hata',
        message: 'Tarama yapılamadı: $e',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(FeatureTestPage.title),
        actions: const [HomeButton()],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _ProgressHeader(
                done: _done.length,
                total: _total,
                onReset: _done.isEmpty ? null : _reset,
              ),
              const SizedBox(height: 16),
              for (final _TestSection section in _sections) ...[
                _SectionCard(
                  section: section,
                  done: _done,
                  onToggle: _toggle,
                  onTool: _runTool,
                ),
                const SizedBox(height: 14),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ProgressHeader extends StatelessWidget {
  final int done;
  final int total;
  final VoidCallback? onReset;

  const _ProgressHeader({
    required this.done,
    required this.total,
    required this.onReset,
  });

  String get _platformLabel {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'Android';
      case TargetPlatform.iOS:
        return 'iOS / iPadOS';
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

  @override
  Widget build(BuildContext context) {
    final bool allDone = done >= total;
    final bool localNotifications = NotificationService().isSupported;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF8E54E9), Color(0xFFA16AEC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF8E54E9).withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                allDone ? Icons.verified_rounded : Icons.fact_check_outlined,
                color: Colors.white,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  allDone ? 'Bütün testler tamam' : 'Test Kontrol Listesi',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (onReset != null)
                LabeledActionButton(
                  dense: true,
                  icon: Icons.restart_alt_rounded,
                  label: _FeatureTestPageState._resetLabel,
                  foregroundColor: Colors.white,
                  onPressed: onReset,
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Her adımı uygulamada yapın; beklenen sonucu görünce kutuyu '
            'işaretleyin. İşaretler bu cihazda saklanır.',
            style: TextStyle(color: Colors.white, fontSize: 14, height: 1.35),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 10,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                '$done / $total adım tamam',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              _HeaderChip(
                icon: Icons.devices_rounded,
                text: 'Bu cihaz: $_platformLabel',
              ),
              _HeaderChip(
                icon: localNotifications
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_off_outlined,
                text: localNotifications
                    ? 'Sistem bildirimi var'
                    : 'Yalnızca uygulama içi şerit',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _HeaderChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final _TestSection section;
  final Set<String> done;
  final ValueChanged<String> onToggle;
  final ValueChanged<_TestTool> onTool;

  const _SectionCard({
    required this.section,
    required this.done,
    required this.onToggle,
    required this.onTool,
  });

  @override
  Widget build(BuildContext context) {
    final int completed =
        section.steps.where((step) => done.contains(step.id)).length;
    final bool sectionDone = completed == section.steps.length;
    final Color color = section.color;
    final String? note = section.note;

    return Card(
      elevation: 1.5,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: sectionDone
              ? Colors.green.shade300
              : color.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: color.withValues(alpha: 0.07),
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(section.icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    section.title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sectionDone ? Colors.green.shade600 : color,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (sectionDone) ...[
                        const Icon(Icons.check_rounded,
                            size: 14, color: Colors.white),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        '$completed/${section.steps.length}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (note != null)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      note,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: Colors.grey.shade800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          for (int i = 0; i < section.steps.length; i++)
            _StepTile(
              index: i + 1,
              step: section.steps[i],
              done: done.contains(section.steps[i].id),
              color: color,
              onTap: () => onToggle(section.steps[i].id),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final _TestTool tool in section.tools)
                  tool.isPrimary
                      ? FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: color),
                          onPressed: () => onTool(tool),
                          icon: Icon(tool.icon, size: 18),
                          label: Text(tool.label),
                        )
                      : OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: color,
                            side: BorderSide(
                                color: color.withValues(alpha: 0.5)),
                          ),
                          onPressed: () => onTool(tool),
                          icon: Icon(tool.icon, size: 18),
                          label: Text(tool.label),
                        ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepTile extends StatelessWidget {
  final int index;
  final _TestStep step;
  final bool done;
  final Color color;
  final VoidCallback onTap;

  const _StepTile({
    required this.index,
    required this.step,
    required this.done,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 16, 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: done,
              activeColor: Colors.green.shade600,
              onChanged: (_) => onTap(),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$index. ${step.action}',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: done ? Colors.grey.shade500 : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: 'Beklenen: ',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: done ? Colors.grey.shade500 : color,
                            ),
                          ),
                          TextSpan(text: step.expected),
                        ],
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.35,
                        color: done
                            ? Colors.grey.shade500
                            : Colors.grey.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
