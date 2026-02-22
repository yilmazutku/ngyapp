import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../main.dart';
import '../models/kvkk_consent_model.dart';
import '../providers/user_provider.dart';
import '../services/fcm_service.dart';
import '../services/meal_reminder_service.dart';
import '../services/notification_service.dart';
import '../utils/dialog_utils.dart';
import 'login_page.dart';

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
  bool _isEnglish = false; // Turkish is default

  // KVKK Information Notice text - Turkish
  static const String _kvkkInformationTextTr = '''NGY APP – KVKK AYDINLATMA METNİ
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

  // KVKK Information Notice text - English
  static const String _kvkkInformationTextEn = '''NGY APP – PRIVACY POLICY
(Version: 1.0 | Last updated: January 13, 2026)

This document has been prepared to fulfill the "disclosure obligation" under the Turkish Personal Data Protection Law No. 6698 ("KVKK") and is compliant with GDPR principles.
This document alone does not constitute "explicit consent."

1) DATA CONTROLLER
Data Controller: Dietitian Nilay Göktepe Yılmaz
Address: Cubes Plaza, B Block No:208, Çukurambar, Öğretmenler Cd. No:6, 06510 Çankaya/Ankara, Turkey
Email (Privacy inquiries): dytnilaygoktepe@gmail.com
Phone: +90 533 284 43 33

2) PERSONAL DATA COLLECTED (Based on app usage)
The following personal data may be processed when you use NGY App:

A) Account / Membership Data
- Login/session information, user account details, user ID

B) Identity and Contact Information (if provided by user)
- Name (if provided), email, phone number (if provided)

C) Profile / Demographic Information (entered by user)
- Age, height

D) Tracking Data (entered by user)
- Measurement information (e.g., weight/body measurements – depends on user input)
- Daily water consumption
- Daily step count

E) Content Data
- Meal photos (uploaded from camera/gallery)
- Descriptions/notes related to photos

F) Messaging (Chat) Data
- User-dietitian message contents
- Images shared in messages (e.g., meal photos) and additional descriptions

G) Notification Data
- Device notification token (FCM token) and notification preferences for push notifications
- Local notification settings for meal reminders scheduled on the device

Important Note (Sensitive Data):
Some of the above data may constitute "health data" depending on its content and may be considered "sensitive personal data" under KVKK/GDPR.
In such cases, separate Explicit Consent will be obtained when necessary.

3) PURPOSES OF PROCESSING PERSONAL DATA
Your personal data is processed for the following purposes:
- Creating membership, login/session management, and maintaining your account
- Managing the diet/nutrition process: creating, viewing, and reporting your measurement and tracking records
- Managing meal photo upload and dietitian evaluation processes
- Facilitating messaging/communication between user and dietitian
- Delivering meal reminders and app notifications (push and/or local scheduled notifications)
- Managing support requests
- Fulfilling legal obligations and responding to requests from authorized institutions/organizations

4) METHODS OF COLLECTING PERSONAL DATA
Data is collected electronically through:
- User input via application screens
- Photos selected and uploaded from camera/gallery
- Use of the messaging (chat) function
- Generation of device notification tokens for push notification delivery

5) LEGAL BASIS
Your personal data is processed based on the processing conditions stipulated in KVKK and GDPR:
- Non-sensitive personal data (e.g., age, height, water consumption, step count, account data): May be based on necessity for service provision, legal obligations, and legitimate interest.
- Sensitive personal data (e.g., measurement information and chat contents that may be health-related): Processed under conditions stipulated in KVKK/GDPR; Explicit Consent is obtained when necessary.

6) DOMESTIC TRANSFER OF PERSONAL DATA
Your personal data:
- Is viewed and managed by the dietitian as the Data Controller within the scope of service provision
- May be shared with relevant institutions/organizations only to the extent of the request, upon request by authorized public institutions

7) SERVICE PROVIDERS (Firebase/Google) AND DATA PROCESSORS
Google Firebase services are used in the application infrastructure:
- Authentication/session (Firebase Authentication)
- Database (Firebase Firestore)
- Image storage (Firebase Storage)
- Push notification infrastructure (Firebase Cloud Messaging – FCM)

In this context, your personal data may be processed in the service provider's infrastructure for the purpose of providing the relevant services.

On iOS devices, Apple's push infrastructure (APNs) may also be technically involved in the push notification delivery process.
On Android devices, relevant operating system/service infrastructures may be used in notification delivery processes.

8) INTERNATIONAL TRANSFER OF PERSONAL DATA
Due to cloud infrastructure and notification services, your personal data may be stored and/or processed on servers located abroad.
International transfer processes are conducted in accordance with KVKK's international transfer provisions and GDPR requirements.

9) RETENTION PERIODS
Your personal data is retained:
- As long as your account is active
- For the duration necessary for service provision
- For periods limited to legal obligations and establishment/exercise/protection of rights in potential disputes
After the retention period, data is deleted, destroyed, or anonymized.

10) DATA SUBJECT RIGHTS (KVKK Article 11 / GDPR)
You have the right to:
- Learn whether your personal data is being processed
- Request information if your data has been processed
- Learn the purpose of processing and whether it is used in accordance with its purpose
- Know the third parties to whom your data is transferred domestically/internationally
- Request correction if your data is incomplete or incorrectly processed
- Request deletion or destruction under conditions stipulated in KVKK/GDPR
- Request notification of correction/deletion/destruction operations to third parties
- Object to results arising against you through analysis exclusively by automated systems
- Claim compensation for damages in case of unlawful processing

11) HOW TO SUBMIT REQUESTS
You can submit your requests under KVKK/GDPR through:
Email: dytnilaygoktepe@gmail.com
Address: Cubes Plaza, B Block No:208, Çukurambar, Öğretmenler Cd. No:6, 06510 Çankaya/Ankara, Turkey

Requests are processed as soon as possible and within 30 days at the latest.

12) CHANGES
This document may be updated as needed. The current version is published within the application.''';

  // Explicit Consent text for special category data - Turkish
  static const String _explicitConsentTextTr = '''NGY APP – ÖZEL NİTELİKLİ KİŞİSEL VERİLER İÇİN AÇIK RIZA METNİ
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

  // Explicit Consent text for special category data - English
  static const String _explicitConsentTextEn = '''NGY APP – EXPLICIT CONSENT FOR SENSITIVE PERSONAL DATA
(Version: 1.0 | Last updated: January 13, 2026)

Data Controller: Dietitian Nilay Göktepe Yılmaz
Address: Cubes Plaza, B Block No:208, Çukurambar, Öğretmenler Cd. No:6, 06510 Çankaya/Ankara, Turkey
Email (Privacy inquiries): dytnilaygoktepe@gmail.com

I have read and understood the Privacy Policy.

Within the scope of NGY App, I give explicit consent for the processing of the following data entered by me into the application and/or shared in in-app messaging (chat):
- My measurement information (e.g., weight/body measurements, etc.)
- My daily water consumption and daily step count information
- My meal photos and descriptions
- My messaging contents with my dietitian (including information that may be health-related)

for the purposes of managing, tracking, reporting the diet/nutrition process, and providing evaluation/consultancy services by the dietitian.

I acknowledge that this data may be viewed by the dietitian within the scope of service provision;
and may be stored and processed on cloud infrastructure (Firebase).

I understand that I may withdraw my explicit consent at any time (without affecting the lawfulness of processing prior to withdrawal).''';

  String get _kvkkInformationText =>
      _isEnglish ? _kvkkInformationTextEn : _kvkkInformationTextTr;

  String get _explicitConsentText =>
      _isEnglish ? _explicitConsentTextEn : _explicitConsentTextTr;

  Future<void> _handleContinue() async {
    if (!_kvkkAcknowledged || !_explicitConsentGiven) {
      if (mounted) {
        await DialogUtils.openInfo(
          context,
          title: _isEnglish ? 'Missing Consent' : 'Eksik Onay',
          message: _isEnglish
              ? 'You must provide both consents to continue.'
              : 'Devam edebilmek için her iki onayı da vermeniz gerekmektedir.',
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
            title: _isEnglish ? 'Error' : 'Hata',
            message: _isEnglish
                ? 'User not found. Please log in again.'
                : 'Kullanıcı bulunamadı. Lütfen tekrar giriş yapın.',
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
          title: _isEnglish ? 'Error' : 'Hata',
          message: _isEnglish
              ? 'Failed to save consent: $e'
              : 'Onay kaydedilemedi: $e',
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
      title: _isEnglish ? 'Exit' : 'Çıkış',
      message: _isEnglish
          ? 'You cannot use the app without providing consent. Are you sure you want to exit?'
          : 'Onay vermeden uygulamayı kullanamayacaksınız. Çıkmak istediğinize emin misiniz?',
      confirmText: _isEnglish ? 'Yes, Exit' : 'Evet, Çık',
      cancelText: _isEnglish ? 'No' : 'Hayır',
    );

    if (confirmed) {
      // Cancel all local notifications before signing out
      await NotificationService().cancelAllNotifications();
      await MealReminderService().cancelAllMealReminders();
      // Remove FCM token before signing out to stop push notifications
      await FcmService().removeFcmToken();
      await FirebaseAuth.instance.signOut();
      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const LoginPage()),
          (route) => false,
        );
      }
    }
  }

  void _showTextDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (dialogContext) => _TextViewDialog(
        title: title,
        content: content,
        closeButtonText: _isEnglish ? 'Close' : 'Kapat',
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
        title: Text(_isEnglish ? 'Privacy Information & Consent' : 'KVKK Bilgilendirme ve Onay'),
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
                  // Language toggle buttons
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildLanguageButton(
                            label: 'Türkçe',
                            isSelected: !_isEnglish,
                            onTap: () {
                              if (_isEnglish) {
                                setState(() => _isEnglish = false);
                              }
                            },
                          ),
                          _buildLanguageButton(
                            label: 'English',
                            isSelected: _isEnglish,
                            onTap: () {
                              if (!_isEnglish) {
                                setState(() => _isEnglish = true);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

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
                        Text(
                          _isEnglish ? 'Privacy Information & Consent' : 'KVKK Bilgilendirme ve Onay',
                          style: const TextStyle(
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
                    child: Text(
                      _isEnglish
                          ? 'In NGY App, some of your personal data is processed to track your diet process (data such as age/height, measurements, water consumption, step count), '
                            'to upload meal photos, and to message your dietitian. '
                            'Notification permission is requested separately from your device for meal reminders.'
                          : 'NGY App\'te; diyet sürecinizi takip edebilmeniz (yaş/boy, ölçüm, su tüketimi, adım sayısı gibi veriler), '
                            'öğün fotoğrafı yükleyebilmeniz ve diyetisyeninizle mesajlaşabilmeniz için bazı kişisel verileriniz işlenir. '
                            'Bildirim izni, yemek hatırlatmaları için ayrıca cihazınızdan istenir.',
                      style: const TextStyle(fontSize: 14, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Document links
                  _buildDocumentLink(
                    title: _isEnglish ? 'Privacy Policy' : 'KVKK Aydınlatma Metni',
                    onTap: () => _showTextDialog(
                      _isEnglish ? 'Privacy Policy' : 'KVKK Aydınlatma Metni',
                      _kvkkInformationText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildDocumentLink(
                    title: _isEnglish ? 'Explicit Consent for Sensitive Data' : 'Özel Nitelikli Veri Açık Rıza Metni',
                    onTap: () => _showTextDialog(
                      _isEnglish ? 'Explicit Consent for Sensitive Data' : 'Özel Nitelikli Veri Açık Rıza Metni',
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
                    title: _isEnglish ? 'I have read the Privacy Policy.' : 'KVKK Aydınlatma Metni\'ni okudum.',
                  ),
                  const SizedBox(height: 8),
                  _buildCheckboxTile(
                    value: _explicitConsentGiven,
                    onChanged: (value) {
                      setState(() => _explicitConsentGiven = value ?? false);
                    },
                    title: _isEnglish
                        ? 'I consent to the processing of my measurement and health data for my diet process.'
                        : 'Ölçüm ve sağlık bilgilerimin diyet sürecim için işlenmesini kabul ediyorum.',
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
                          child: Text(_isEnglish ? 'Exit App' : 'Uygulamadan Çık'),
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
                              : Text(_isEnglish ? 'Continue' : 'Devam Et'),
                        ),
                      ),
                    ],
                  ),

                  // Version info
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _isEnglish ? 'Version: $kvkkCurrentVersion' : 'Sürüm: $kvkkCurrentVersion',
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

  Widget _buildLanguageButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey.shade700,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

/// Dialog widget for displaying KVKK text documents with proper scroll handling
class _TextViewDialog extends StatefulWidget {
  final String title;
  final String content;
  final String closeButtonText;

  const _TextViewDialog({
    required this.title,
    required this.content,
    required this.closeButtonText,
  });

  @override
  State<_TextViewDialog> createState() => _TextViewDialogState();
}

class _TextViewDialogState extends State<_TextViewDialog> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.6,
        child: Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          child: SingleChildScrollView(
            controller: _scrollController,
            child: Text(
              widget.content,
              style: const TextStyle(fontSize: 14, height: 1.5),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.closeButtonText),
        ),
      ],
    );
  }
}
