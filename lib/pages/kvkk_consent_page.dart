import 'dart:io' show exit;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/kvkk_consent_model.dart';
import '../providers/user_provider.dart';
import '../utils/dialog_utils.dart';

/// KVKK consent page shown after login for first-time users
/// or when KVKK version has been updated.
class KvkkConsentPage extends StatefulWidget {
  const KvkkConsentPage({super.key});

  @override
  State<KvkkConsentPage> createState() => _KvkkConsentPageState();
}

class _KvkkConsentPageState extends State<KvkkConsentPage> {
  // Checkboxes are NOT pre-checked by default
  bool _kvkkAcknowledged = false;
  bool _explicitConsentGiven = false;
  bool _isSaving = false;

  // KVKK Information Notice text
  static const String _kvkkInformationText = '''NGY APP – KVKK AYDINLATMA METNİ
(Sürüm: 1.0 | Son güncelleme: 13.01.2026)

Bu metin, 6698 sayılı Kişisel Verilerin Korunması Kanunu ("KVKK") kapsamında "aydınlatma yükümlülüğü"nü yerine getirmek amacıyla hazırlanmıştır.
İşbu metin, tek başına "açık rıza" değildir.

1) VERİ SORUMLUSU
Veri Sorumlusu: Diyetisyen Nilay Göktepe Yılmaz
Adres: Cubes Plaza, B Blok No:208, Çukurambar, Öğretmenler Cd. No:6, 06510 Çankaya/Ankara
E-posta (KVKK başvuru): [KVKK başvuru e-postan]
Telefon: [telefon]
(Var ise) KEP: [KEP adresi]

2) İŞLENEN KİŞİSEL VERİLER (Uygulama kullanımına göre)
NGY App'i kullanmanız kapsamında aşağıdaki kişisel veriler işlenebilir:

A) Hesap / Üyelik Verileri
- Giriş/oturum bilgileri, kullanıcı hesabı bilgileri, kullanıcı kimliği

B) Kimlik ve İletişim (kullanıcı tarafından sağlanırsa)
- Ad-soyad (varsa), e-posta, telefon (varsa)

C) Profil / Demografik Bilgiler (kullanıcı tarafından girilir)
- Yaş, boy

D) Takip Verileri (kullanıcı tarafından girilir)
- Ölçüm bilgileri (örn. kilo/beden ölçüsü vb. – kullanıcı girişine bağlı)
- Günlük su tüketimi
- Günlük adım sayısı

E) İçerik Verileri
- Öğün fotoğrafları (kamera/galeriden seçilerek yüklenir)
- Fotoğraflara ilişkin açıklamalar / notlar

F) Mesajlaşma (Chat) Verileri
- Kullanıcı–diyetisyen mesaj içerikleri
- Mesajlarla paylaşılan görseller (örn. öğün fotoğrafları) ve ek açıklamalar

G) Bildirim Verileri
- Push bildirim gönderebilmek için cihaz bildirim belirteci (FCM token) ve bildirim tercihleri
- Yemek hatırlatmaları için cihaz üzerinde planlanan bildirim ayarları (lokal bildirim)

Önemli Not (Özel Nitelikli Veri):
Yukarıdaki verilerden bazıları, içeriğine göre "sağlık verisi" niteliği taşıyabilir ve KVKK kapsamında "özel nitelikli kişisel veri" sayılabilir.
Bu durumda gerekli hallerde ayrıca Açık Rıza alınır.

3) KİŞİSEL VERİLERİN İŞLENME AMAÇLARI
Kişisel verileriniz aşağıdaki amaçlarla işlenir:
- Üyelik oluşturma, giriş/oturum yönetimi ve hesabınızın yürütülmesi
- Diyet/beslenme sürecinin yürütülmesi: ölçüm ve takip kayıtlarınızın oluşturulması, görüntülenmesi ve raporlanması
- Öğün fotoğrafı yükleme ve diyetisyen tarafından değerlendirme süreçlerinin yürütülmesi
- Kullanıcı ile diyetisyen arasındaki mesajlaşma/iletişim süreçlerinin yürütülmesi
- Yemek hatırlatmalarının ve uygulama bildirimlerinin iletilmesi (push ve/veya cihaz içi planlı bildirim)
- Destek taleplerinin yönetilmesi
- Mevzuattan doğan yükümlülüklerin yerine getirilmesi ve yetkili kurum/kuruluş taleplerinin yanıtlanması

4) KİŞİSEL VERİLERİN TOPLANMA YÖNTEMİ
Veriler;
- Uygulama ekranları üzerinden kullanıcı tarafından girilmesi,
- Kamera/galeriden fotoğraf seçilerek yüklenmesi,
- Mesajlaşma (chat) fonksiyonunun kullanılması,
- Push bildirimlerin iletilmesi için cihaz bildirim belirtecinin (token) oluşması
yollarıyla elektronik ortamda toplanır.

5) HUKUKİ SEBEPLER
Kişisel verileriniz KVKK'da öngörülen işleme şartlarına dayanılarak işlenir.
- Özel nitelikli olmayan kişisel veriler (örn. yaş, boy, su tüketimi, adım sayısı, hesap verileri): hizmetin sunulması için gerekli olması, hukuki yükümlülükler ve meşru menfaat gibi KVKK'daki işleme şartlarına dayanabilir.
- Özel nitelikli kişisel veriler (örn. sağlık niteliği taşıyabilecek ölçüm bilgileri ve chat içerikleri): KVKK'da öngörülen şartlar kapsamında işlenir; gerekli hallerde Açık Rıza alınır.

6) KİŞİSEL VERİLERİN AKTARILMASI (YURT İÇİ)
Kişisel verileriniz;
- Hizmetin sunulması kapsamında Veri Sorumlusu olan diyetisyen tarafından görüntülenir ve yönetilir.
- Yetkili kamu kurum ve kuruluşlarının talebi halinde, yalnızca talep ile sınırlı olacak şekilde ilgili kurum/kuruluşlarla paylaşılabilir.

7) HİZMET SAĞLAYICILAR (Firebase/Google) VE VERİ İŞLEYENLER
Uygulama altyapısında Google Firebase hizmetleri kullanılmaktadır:
- Kimlik doğrulama/oturum (Firebase Authentication)
- Veritabanı (Firebase Firestore)
- Görsel depolama (Firebase Storage)
- Push bildirim altyapısı (Firebase Cloud Messaging – FCM)

Bu kapsamda kişisel verileriniz, ilgili hizmetlerin sağlanması amacıyla hizmet sağlayıcı altyapısında işlenebilir.

iOS cihazlarda push bildirimlerin iletilmesi sürecinde Apple push altyapısı (APNs) da teknik olarak devreye girebilir.
Android cihazlarda bildirim iletimi süreçlerinde ilgili işletim sistemi / servis altyapıları kullanılabilir.

8) KİŞİSEL VERİLERİN YURT DIŞINA AKTARILMASI
Bulut altyapısı ve bildirim hizmetleri nedeniyle kişisel verileriniz yurt dışındaki sunucularda saklanabilir ve/veya işlenebilir.
Yurt dışına aktarım süreçleri, KVKK'nın yurt dışına aktarım hükümlerine uygun şekilde yürütülür.

9) SAKLAMA SÜRELERİ
Kişisel verileriniz;
- Hesabınız aktif olduğu sürece,
- Hizmetin sunulması için gerekli süre boyunca,
- Hukuki yükümlülükler ve olası uyuşmazlıklarda hakların tesisi/kullanılması/korunması için gerekli sürelerle sınırlı olarak
saklanır; süre sonunda silinir, yok edilir veya anonim hale getirilir.

10) İLGİLİ KİŞİ HAKLARI (KVKK m.11)
KVKK kapsamında veri sorumlusuna başvurarak;
- Kişisel verilerinizin işlenip işlenmediğini öğrenme,
- İşlenmişse bilgi talep etme,
- İşlenme amacını ve amaca uygun kullanılıp kullanılmadığını öğrenme,
- Yurt içinde/yurt dışında aktarım yapılan üçüncü kişileri bilme,
- Eksik/yanlış işlenmişse düzeltilmesini isteme,
- KVKK'da öngörülen şartlar çerçevesinde silinmesini veya yok edilmesini isteme,
- Düzeltme/silme/yok edilme işlemlerinin aktarım yapılan üçüncü kişilere bildirilmesini isteme,
- Münhasıran otomatik sistemler ile analiz edilmesi sonucu aleyhinize bir sonucun ortaya çıkmasına itiraz etme,
- Kanuna aykırı işleme nedeniyle zarara uğramanız halinde zararın giderilmesini talep etme
haklarına sahipsiniz.

11) BAŞVURU YÖNTEMİ
KVKK kapsamındaki taleplerinizi;
E-posta: [KVKK başvuru e-postan]
Adres: Cubes Plaza, B Blok No:208, Çukurambar, Öğretmenler Cd. No:6, 06510 Çankaya/Ankara
üzerinden iletebilirsiniz.

Başvurular, talebin niteliğine göre en kısa sürede ve en geç 30 gün içinde sonuçlandırılır.

12) DEĞİŞİKLİKLER
Bu metin, ihtiyaç halinde güncellenebilir. Güncel metin uygulama içinde yayınlanır.''';

  // Explicit Consent text for special category data
  static const String _explicitConsentText = '''NGY APP – ÖZEL NİTELİKLİ KİŞİSEL VERİLER İÇİN AÇIK RIZA METNİ
(Sürüm: 1.0 | Son güncelleme: 13.01.2026)

Veri Sorumlusu: Diyetisyen Nilay Göktepe Yılmaz
Adres: Cubes Plaza, B Blok No:208, Çukurambar, Öğretmenler Cd. No:6, 06510 Çankaya/Ankara
E-posta (KVKK başvuru): [KVKK başvuru e-postan]

KVKK Aydınlatma Metni'ni okudum ve anladım.

NGY App kapsamında, benim tarafımdan uygulamaya girilen ve/veya uygulama içi mesajlaşmalarda (chat) paylaşılan;
- ölçüm bilgilerimin (örn. kilo/beden ölçüsü vb.),
- günlük su tüketimi ve günlük adım sayısı bilgilerimin,
- öğün fotoğraflarımın ve açıklamalarımın,
- diyetisyenim ile yaptığım mesajlaşma içeriklerinin (sağlık niteliği taşıyabilecek bilgiler dahil)
diyet/beslenme sürecinin yürütülmesi, takip edilmesi, raporlanması ve diyetisyen tarafından değerlendirme/danışmanlık hizmetinin sunulması amaçlarıyla işlenmesine açık rıza veriyorum.

Bu verilerin, hizmetin sunulması kapsamında diyetisyen tarafından görüntülenebileceğini;
bulut altyapısı (Firebase) üzerinde saklanabileceğini ve işlenebileceğini biliyorum.

Açık rızamı dilediğim zaman geri alabileceğimi (geri alma öncesindeki işlemleri etkilemeksizin) biliyorum.''';

  Future<void> _handleContinue() async {
    if (!_kvkkAcknowledged || !_explicitConsentGiven) {
      if (mounted) {
        await DialogUtils.openInfo(
          context,
          title: 'Eksik Onay',
          message: 'Devam edebilmek için her iki onayı da vermeniz gerekmektedir.',
        );
      }
      return;
    }

    setState(() => _isSaving = true);

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid;
      if (userId == null) {
        if (mounted) {
          await DialogUtils.openError(
            context,
            title: 'Hata',
            message: 'Kullanıcı bulunamadı. Lütfen tekrar giriş yapın.',
          );
        }
        return;
      }

      final userProvider = Provider.of<UserProvider>(context, listen: false);
      await userProvider.saveKvkkConsent(
        userId: userId,
        kvkkAccepted: _kvkkAcknowledged,
        explicitConsentAccepted: _explicitConsentGiven,
      );

      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomePage()),
        );
      }
    } catch (e) {
      if (mounted) {
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message: 'Onay kaydedilemedi: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _handleExit() async {
    final confirmed = await DialogUtils.openConfirm(
      context,
      title: 'Çıkış',
      message: 'Onay vermeden uygulamayı kullanamayacaksınız. Çıkmak istediğinize emin misiniz?',
      confirmText: 'Evet, Çık',
      cancelText: 'Hayır',
    );

    if (confirmed) {
      await FirebaseAuth.instance.signOut();
      if (kIsWeb) {
        // On web, redirect to login page
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/');
        }
      } else {
        // On mobile/desktop, close the app
        SystemNavigator.pop();
      }
    }
  }

  void _showTextDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: double.maxFinite,
          height: MediaQuery.of(context).size.height * 0.6,
          child: Scrollbar(
            thumbVisibility: true,
            child: SingleChildScrollView(
              child: Text(
                content,
                style: const TextStyle(fontSize: 14, height: 1.5),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isLargeScreen = screenSize.width > 600;
    final contentWidth = isLargeScreen
        ? screenSize.width * 0.5
        : screenSize.width * 0.9;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KVKK Bilgilendirme ve Onay'),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: contentWidth.clamp(300.0, 600.0),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header icon and title
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.privacy_tip_outlined,
                            size: 48,
                            color: Theme.of(context).primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'KVKK Bilgilendirme ve Onay',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Information text
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: const Text(
                      'NGY App\'te; diyet sürecinizi takip edebilmeniz (yaş/boy, ölçüm, su tüketimi, adım sayısı gibi veriler), '
                      'öğün fotoğrafı yükleyebilmeniz ve diyetisyeninizle mesajlaşabilmeniz için bazı kişisel verileriniz işlenir. '
                      'Bildirim izni, yemek hatırlatmaları için ayrıca cihazınızdan istenir.',
                      style: TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Document links
                  _buildDocumentLink(
                    title: 'KVKK Aydınlatma Metni',
                    onTap: () => _showTextDialog(
                      'KVKK Aydınlatma Metni',
                      _kvkkInformationText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDocumentLink(
                    title: 'Özel Nitelikli Veri Açık Rıza Metni',
                    onTap: () => _showTextDialog(
                      'Özel Nitelikli Veri Açık Rıza Metni',
                      _explicitConsentText,
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Checkboxes - NOT pre-checked
                  _buildCheckboxTile(
                    value: _kvkkAcknowledged,
                    onChanged: (value) {
                      setState(() => _kvkkAcknowledged = value ?? false);
                    },
                    title: 'KVKK Aydınlatma Metni\'ni okudum.',
                  ),
                  const SizedBox(height: 8),
                  _buildCheckboxTile(
                    value: _explicitConsentGiven,
                    onChanged: (value) {
                      setState(() => _explicitConsentGiven = value ?? false);
                    },
                    title: 'Ölçüm ve sağlık bilgilerimin diyet sürecim için işlenmesini kabul ediyorum.',
                  ),
                  const SizedBox(height: 32),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isSaving ? null : _handleExit,
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            side: BorderSide(color: Colors.red.shade400),
                            foregroundColor: Colors.red.shade600,
                          ),
                          child: const Text('Uygulamadan Çık'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (_kvkkAcknowledged && _explicitConsentGiven && !_isSaving)
                              ? _handleContinue
                              : null,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Devam Et'),
                        ),
                      ),
                    ],
                  ),

                  // Version info
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      'Sürüm: $kvkkCurrentVersion',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentLink({
    required String title,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              color: Theme.of(context).primaryColor,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.open_in_new,
              size: 18,
              color: Theme.of(context).primaryColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckboxTile({
    required bool value,
    required ValueChanged<bool?> onChanged,
    required String title,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: value ? Theme.of(context).primaryColor : Colors.grey.shade300,
          ),
          borderRadius: BorderRadius.circular(8),
          color: value
              ? Theme.of(context).primaryColor.withOpacity(0.05)
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(fontSize: 14, height: 1.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
