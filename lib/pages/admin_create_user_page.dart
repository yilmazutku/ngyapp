import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../firebase_options.dart';
import '../models/logger.dart';
import '../models/user_model.dart';
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
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _surnameController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _referenceController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _dosyaNoController = TextEditingController();

  Future<void> createUser({
    required String name,
    required String email,
    String? password,
    required String surname,
    int? age,
    String? reference,
    String? notes,
    String? dosyaNo,
    String? phone,
  }) async {
    if (name.isEmpty) {
      _showMessageDialog('Hata', 'Lütfen isim alanını doldurunuz.');
      return;
    }

    if (surname.isEmpty) {
      _showMessageDialog('Hata', 'Lütfen soyisim alanını doldurunuz.');
      return;
    }

    // E-posta opsiyoneldir: boş bırakılırsa kişinin adına göre
    // her seferinde benzersiz, geçici bir e-posta üretilir.
    if (email.isEmpty) {
      email = _generateTempEmail(name);
    }

    password ??= CreateUserPage.tempPw;

    try {
      // Check if a user with the same email already exists
      final existingUserQuery = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .get();

      if (existingUserQuery.docs.isNotEmpty) {
        _showMessageDialog(
          'Hata',
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
        dosyaNo: dosyaNo,
        phone: phone,
      );

      // Store user data in Firestore
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .set(newUser.toMap());

      _showMessageDialog('Başarılı', 'Kullanıcı $name başarıyla oluşturuldu.');
      logger.info('User created: {}', [newUser]);
    } catch (e) {
      logger.err('Kullanıcı oluşturulamadı: {}', [e.toString()]);
      _showMessageDialog('Hata', 'Kullanıcı oluşturulamadı. Hata: $e');
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

    return buffer
        .toString()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _showMessageDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Tamam'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Kullanıcı Ekle',
      ),
      body: Padding(
        padding: const EdgeInsets.all(8.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _dosyaNoController,
                decoration: const InputDecoration(
                  labelText: 'Dosya NO (Opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'İsim Giriniz',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                inputFormatters: [_CapitalizeWordsFormatter()],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _surnameController,
                decoration: const InputDecoration(
                  labelText: 'Soyisim Giriniz',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                inputFormatters: [_CapitalizeWordsFormatter()],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(
                  labelText: 'Şifre Giriniz',
                  border: OutlineInputBorder(),
                ),
                obscureText: false,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(
                  labelText: 'E-posta (Opsiyonel)',
                  helperText:
                      'Girilmezse sistem otomatik bir mail girer, değiştirilebilir.',
                  helperMaxLines: 2,
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Telefon Numarası (Opsiyonel)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ageController,
                decoration: const InputDecoration(
                  labelText: 'Yaş Giriniz (Opsiyonel)',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _referenceController,
                decoration: const InputDecoration(
                  labelText: 'Referans Giriniz (Opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: 'Notlar (Opsiyonel)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton(
                onPressed: () {
                  final name = _nameController.text.trim();
                  final surname = _surnameController.text.trim();
                  final age = int.tryParse(_ageController.text.trim());
                  final reference = _referenceController.text.trim();
                  final notes = _notesController.text.trim();
                  final email = _emailController.text.trim();
                  final phone = _phoneController.text.trim();
                  final dosyaNo = _dosyaNoController.text.trim();
                  final password = _passwordController.text.trim().isNotEmpty
                      ? _passwordController.text.trim()
                      : null;

                  createUser(
                    name: name,
                    email: email,
                    password: password,
                    surname: surname,
                    age: age,
                    reference: reference.isNotEmpty ? reference : null,
                    notes: notes.isNotEmpty ? notes : null,
                    dosyaNo: dosyaNo.isNotEmpty ? dosyaNo : null,
                    phone: phone.isNotEmpty ? phone : null,
                  );
                },
                child: const Text('Kullanıcı Oluştur'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _surnameController.dispose();
    _ageController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _dosyaNoController.dispose();
    super.dispose();
  }
}