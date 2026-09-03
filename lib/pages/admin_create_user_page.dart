import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../models/logger.dart';
import '../models/user_model.dart';
import '../utils/date_formatter.dart';
import '../utils/dialog_utils.dart';
import '../widgets/app_bar_with_back.dart';

class _CapitalizeWordsFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text;
    if (text.isEmpty) return newValue;

    final buffer = StringBuffer();
    bool capitalizeNext = true;
    for (int i = 0; i < text.length; i++) {
      if (text[i] == ' ') {
        buffer.write(' ');
        capitalizeNext = true;
      } else if (capitalizeNext) {
        buffer.write(text[i].toUpperCase());
        capitalizeNext = false;
      } else {
        buffer.write(text[i].toLowerCase());
      }
    }

    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: newValue.selection,
    );
  }
}

final Logger logger = Logger.forClass(CreateUserPage);

class CreateUserPage extends StatefulWidget {
  const CreateUserPage({super.key});
  static const String tempPw = '123456';

  @override
  createState() => _CreateUserPageState();
}

class _CreateUserPageState extends State<CreateUserPage> {
  /// İki sütunlu düzene geçilecek en küçük genişlik.
  static const double _wideBreakpoint = 620;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _medicationsController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _tcNoController = TextEditingController();
  // Birth date is picked with a date widget, like the details tab does.
  DateTime? _birthDate;
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _dosyaNoController = TextEditingController();

  final ScrollController _scrollController = ScrollController();

  bool _isCreating = false;

  Future<void> createUser({
    required String name,
    required String email,
    String? password,
    required String surname,
    int? age,
    String? reference,
    String? notes,
    String? medicationsAndConditions,
    String? dosyaNo,
    String? phone,
    String? tcNo,
    DateTime? birthDate,
  }) async {
    if (name.isEmpty) {
      await DialogUtils.openError(context,
          title: 'Hata', message: 'Lütfen isim alanını doldurunuz.');
      return;
    }

    if (surname.isEmpty) {
      await DialogUtils.openError(context,
          title: 'Hata', message: 'Lütfen soyisim alanını doldurunuz.');
      return;
    }

    // E-posta opsiyoneldir: boş bırakılırsa kişinin adına göre
    // her seferinde benzersiz, geçici bir e-posta üretilir.
    if (email.isEmpty) {
      email = _generateTempEmail(name);
    }

    password ??= CreateUserPage.tempPw;

    setState(() => _isCreating = true);

    try {
      // Check if a user with the same email already exists
      final existingUserQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (existingUserQuery.docs.isNotEmpty) {
        if (!mounted) return;
        await DialogUtils.openError(
          context,
          title: 'Hata',
          message:
              'Bu e-posta adresiyle bir kullanıcı zaten mevcut. Lütfen farklı bir e-posta giriniz.',
        );
        return;
      }

      // Use a secondary FirebaseApp so the admin session is not replaced
      // by the newly created user's session.
      FirebaseApp secondaryApp;
      try {
        secondaryApp = Firebase.app('tempUserCreation');
      } catch (_) {
        secondaryApp = await Firebase.initializeApp(
          name: 'tempUserCreation',
          options: DefaultFirebaseOptions.currentPlatform,
        );
      }

      String userId;
      try {
        final secondaryAuth = FirebaseAuth.instanceFor(app: secondaryApp);
        final userCredential =
            await secondaryAuth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        final uid = userCredential.user?.uid;
        if (uid == null) {
          throw Exception('Firebase Authentication kullanıcı oluşturulamadı.');
        }
        userId = uid;

        await secondaryAuth.signOut();
      } finally {
        await secondaryApp.delete();
      }

      // Create a UserModel instance
      final newUser = UserModel(
        userId: userId,
        name: name,
        email: email,
        password: password,
        role: 'customer',
        createDate: DateTime.now(),
        createUser: 'admin',
        surname: surname,
        age: age,
        reference: reference,
        notes: notes,
        medicationsAndConditions: medicationsAndConditions,
        dosyaNo: dosyaNo,
        phone: phone,
        tcNo: tcNo,
        birthDate: birthDate,
      );

      // Store user data in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set(newUser.toMap());

      logger.info('User created: {}', [newUser]);

      if (!mounted) return;
      _resetForm();
      await DialogUtils.openInfo(
        context,
        title: 'Başarılı',
        message: 'Kullanıcı $name $surname başarıyla oluşturuldu.\n\n'
            'Giriş e-postası: $email\nŞifre: $password',
      );
    } catch (e) {
      logger.err('Kullanıcı oluşturulamadı: {}', [e.toString()]);
      if (!mounted) return;
      await DialogUtils.openError(context,
          title: 'Hata', message: 'Kullanıcı oluşturulamadı. Hata: $e');
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  /// Kayıt başarılı olduğunda formu boşaltır: aksi hâlde dolu kalan form,
  /// e-posta otomatik üretildiği için aynı kişiyi ikinci kez oluşturabilirdi.
  void _resetForm() {
    _nameController.clear();
    _surnameController.clear();
    _ageController.clear();
    _referenceController.clear();
    _notesController.clear();
    _medicationsController.clear();
    _emailController.clear();
    _phoneController.clear();
    _tcNoController.clear();
    _passwordController.clear();
    _dosyaNoController.clear();
    setState(() => _birthDate = null);
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
  }

  /// Geçici (opsiyonel) bir e-posta üretir. Aynı kişi için bile her çağrıda
  /// farklı olması için epoch (saniye) eklenir.
  /// Örn: "Meral" -> "meral_1712345678@gecicimail.com"
  String _generateTempEmail(String name) {
    final slug = _slugifyName(name);
    final safeSlug = slug.isNotEmpty ? slug : 'kullanici';
    final epochSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return '${safeSlug}_$epochSeconds@gecicimail.com';
  }

  /// İsmi Türkçe karakterlerden arındırıp küçük harfe çevirir, harf ve rakam
  /// dışındaki karakterleri (boşluk vb.) temizler.
  String _slugifyName(String name) {
    const turkishReplacements = {
      'ç': 'c',
      'Ç': 'c',
      'ğ': 'g',
      'Ğ': 'g',
      'ı': 'i',
      'İ': 'i',
      'I': 'i',
      'ö': 'o',
      'Ö': 'o',
      'ş': 's',
      'Ş': 's',
      'ü': 'u',
      'Ü': 'u',
    };

    final buffer = StringBuffer();
    for (final char in name.split('')) {
      buffer.write(turkishReplacements[char] ?? char);
    }

    return buffer.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _submit() {
    final reference = _referenceController.text.trim();
    final notes = _notesController.text.trim();
    final medications = _medicationsController.text.trim();
    final phone = _phoneController.text.trim();
    final tcNo = _tcNoController.text.trim();
    final dosyaNo = _dosyaNoController.text.trim();
    final password = _passwordController.text.trim();

    createUser(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: password.isNotEmpty ? password : null,
      surname: _surnameController.text.trim(),
      age: int.tryParse(_ageController.text.trim()),
      reference: reference.isNotEmpty ? reference : null,
      notes: notes.isNotEmpty ? notes : null,
      medicationsAndConditions: medications.isNotEmpty ? medications : null,
      dosyaNo: dosyaNo.isNotEmpty ? dosyaNo : null,
      phone: phone.isNotEmpty ? phone : null,
      tcNo: tcNo.isNotEmpty ? tcNo : null,
      birthDate: _birthDate,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(title: 'Kullanıcı Ekle'),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final bool wide = constraints.maxWidth >= _wideBreakpoint;

            return Scrollbar(
              controller: _scrollController,
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 840),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildIntroBanner(),
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: Icons.badge_outlined,
                          title: 'Kimlik Bilgileri',
                          children: [
                            _twoColumn(
                              wide,
                              _buildField(
                                controller: _dosyaNoController,
                                label: 'Dosya No',
                              ),
                              _buildField(
                                controller: _tcNoController,
                                label: 'TC No',
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _twoColumn(
                              wide,
                              _buildBirthDateField(),
                              _buildField(
                                controller: _phoneController,
                                label: 'Telefon Numarası',
                                keyboardType: TextInputType.phone,
                                icon: Icons.phone_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: Icons.person_outline,
                          title: 'Kişisel Bilgiler',
                          children: [
                            _twoColumn(
                              wide,
                              _buildField(
                                controller: _nameController,
                                label: 'İsim',
                                isRequired: true,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [_CapitalizeWordsFormatter()],
                              ),
                              _buildField(
                                controller: _surnameController,
                                label: 'Soyisim',
                                isRequired: true,
                                textCapitalization: TextCapitalization.words,
                                inputFormatters: [_CapitalizeWordsFormatter()],
                              ),
                            ),
                            const SizedBox(height: 12),
                            _twoColumn(
                              wide,
                              _buildField(
                                controller: _ageController,
                                label: 'Yaş',
                                keyboardType: TextInputType.number,
                                icon: Icons.cake_outlined,
                              ),
                              _buildField(
                                controller: _referenceController,
                                label: 'Referans',
                                icon: Icons.group_outlined,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: Icons.lock_outline,
                          title: 'Giriş Bilgileri',
                          children: [
                            _buildField(
                              controller: _emailController,
                              label: 'E-posta',
                              keyboardType: TextInputType.emailAddress,
                              icon: Icons.alternate_email,
                              helperText:
                                  'Girilmezse sistem otomatik bir mail üretir, sonradan değiştirilebilir.',
                            ),
                            const SizedBox(height: 12),
                            _buildField(
                              controller: _passwordController,
                              label: 'Şifre',
                              icon: Icons.key_outlined,
                              helperText:
                                  'Girilmezse şifre ${CreateUserPage.tempPw} olarak atanır.',
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        _buildSection(
                          icon: Icons.medical_information_outlined,
                          title: 'Sağlık ve Notlar',
                          children: [
                            _buildField(
                              controller: _medicationsController,
                              label: UserModel.medicationsLabel,
                              maxLines: 4,
                              hintText:
                                  'Örn: Tiroid (Euthyrox 50 mcg), demir eksikliği',
                            ),
                            const SizedBox(height: 12),
                            _buildField(
                              controller: _notesController,
                              label: 'Notlar',
                              maxLines: 4,
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        _buildSubmitButton(),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildIntroBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Yıldızlı (*) alanlar zorunludur. E-posta ve şifre boş bırakılırsa '
              'sistem otomatik atar; ikisi de sonradan değiştirilebilir.',
              style: TextStyle(fontSize: 12, color: Colors.grey[800]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required String title,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: Colors.deepPurple.shade400),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 20),
            ...children,
          ],
        ),
      ),
    );
  }

  /// Dar ekranda alt alta, geniş ekranda yan yana iki alan.
  Widget _twoColumn(bool wide, Widget left, Widget right) {
    if (!wide) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [left, const SizedBox(height: 12), right],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    bool isRequired = false,
    String? hintText,
    String? helperText,
    IconData? icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    TextCapitalization textCapitalization = TextCapitalization.none,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      textCapitalization: textCapitalization,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: isRequired ? '$label *' : label,
        hintText: hintText,
        helperText: helperText,
        helperMaxLines: 2,
        prefixIcon: icon == null ? null : Icon(icon, size: 20),
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.deepPurple.shade300, width: 2),
        ),
        alignLabelWithHint: maxLines > 1,
      ),
    );
  }

  /// Birth date input styled like the surrounding text fields, since a plain
  /// TextField cannot offer a calendar.
  Widget _buildBirthDateField() {
    return InkWell(
      onTap: _pickBirthDate,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Doğum Tarihi',
          filled: true,
          fillColor: Colors.grey.shade50,
          prefixIcon: const Icon(Icons.event_outlined, size: 20),
          suffixIcon: const Icon(Icons.calendar_today, size: 18),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
        ),
        child: Text(
          _birthDate != null
              ? DateFormatter.formatNumericDate(_birthDate!)
              : 'Tarih seçiniz',
          style: TextStyle(
            color: _birthDate != null ? null : Theme.of(context).hintColor,
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      height: 50,
      child: ElevatedButton.icon(
        onPressed: _isCreating ? null : _submit,
        icon: _isCreating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.person_add_alt_1),
        label: Text(
          _isCreating ? 'Oluşturuluyor...' : 'Kullanıcı Oluştur',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: ElevatedButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: Colors.green.shade600,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    );
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _birthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(1900),
      lastDate: now,
      // Opens straight on the keyboard entry the pencil icon used to lead to:
      // typing a birth date is faster than scrolling decades in the calendar.
      // The calendar stays one tap away via the picker's own toggle.
      initialEntryMode: DatePickerEntryMode.input,
    );
    if (picked != null && mounted) {
      setState(() => _birthDate = picked);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _medicationsController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _tcNoController.dispose();
    _passwordController.dispose();
    _dosyaNoController.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
