// lib/services/notification_tap_gate.dart

/// Bildirime basınca açılacak sayfayı uygulama hazır olana kadar bekletir
/// (bkz. `FcmService`).
///
/// Bildirimin açtığı sayfalar (sohbet, duyurular) kök navigator'da ilk
/// sayfanın üstüne açılır. İlk sayfa o sırada KVKK onayı ya da zorunlu
/// güncelleme ekranıysa kullanıcı onay vermeden ya da güncellemeden sohbete
/// girebilirdi. Bu yüzden bildirim yalnızca ana sayfa açıkken ([homeShown];
/// ana sayfa yalnızca KVKK onayı geçerli kullanıcıya gösterilir) ve
/// güncelleme ekranı engellemiyorken ([setUpdateBlocking]) açılır. Hazır
/// değilken basılan bildirim (yalnızca sonuncusu) bekletilir, uygulama hazır
/// olunca açılır; oturum kapanınca [clearPending] onu atar.
class NotificationTapGate {
  /// Bildirimin verisiyle ilgili sayfayı açar.
  final void Function(Map<String, dynamic> data) onOpen;

  NotificationTapGate({required this.onOpen});

  /// Açık ana sayfalar. Aynı anda birden fazla olabilir: girişten sonra ana
  /// sayfa yeni bir rotayla açılırken eskisi geçiş bitene kadar durur.
  final Set<Object> _homePages = {};

  bool _updateBlocking = false;

  Map<String, dynamic>? _pending;

  /// Bildirim şimdi açılabilir mi.
  bool get isReady => _homePages.isNotEmpty && !_updateBlocking;

  /// Bildirime basıldı: hazırsa hemen açılır, değilse bekletilir.
  void open(Map<String, dynamic> data) {
    _pending = data;
    _openPending();
  }

  /// [page] ana sayfası açıldı. Sayfa açılabilsin diye ilk karesinden sonra
  /// çağrılır.
  void homeShown(Object page) {
    _homePages.add(page);
    _openPending();
  }

  /// [page] ana sayfası kapandı.
  void homeGone(Object page) => _homePages.remove(page);

  /// Güncelleme ekranı (ya da sonucu beklenen sürüm denetimi) uygulamayı
  /// engelliyor mu; engel kalkınca bekleyen bildirim açılır.
  void setUpdateBlocking(bool blocking) {
    _updateBlocking = blocking;
    _openPending();
  }

  /// Bekleyen bildirimi atar.
  void clearPending() => _pending = null;

  void _openPending() {
    final Map<String, dynamic>? pending = _pending;
    if (pending == null || !isReady) return;
    _pending = null;
    onOpen(pending);
  }
}
