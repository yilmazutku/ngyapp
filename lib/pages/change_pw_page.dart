import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/logger.dart';
import '../services/fcm_service.dart';
import '../widgets/app_bar_with_back.dart';

final Logger log = Logger.forClass(ChangePasswordPage);

class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key});

  @override
  createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _currentPasswordController = TextEditingController();
  final TextEditingController _newPasswordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  String _statusMessage = '';

  Future<void> reauthenticateAndChangePassword(String email, String currentPassword, String newPassword) async {
    User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      setState(() {
        _statusMessage = 'Giriş yapmış bir kullanıcı bulunmuyor.';
      });
      return;
    }

    try {
      // Re-authenticate the user
      AuthCredential credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      log.info('User re-authenticated successfully.');

      // Update the password
      await user.updatePassword(newPassword);
      log.info('Password updated successfully.');

      // Remove FCM token and sign the user out
      await FcmService().removeFcmToken();
      await FirebaseAuth.instance.signOut();
      log.info('User signed out. Redirect to login page.');

      setState(() {
        _statusMessage = 'Şifre başarıyla değiştirildi. Lütfen tekrar giriş yapınız..';
      });

      // Here you would typically navigate to the login page.
      // Navigator.of(context).pushReplacementNamed('/login');

    } catch (e) {
      setState(() {
        _statusMessage = 'Şifre değiştirilemedi. Lütfen destek isteyiniz.';
      });
      log.info('Failed to update password: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const AppBarWithBack(
        title: 'Şifre Değiştir',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'E-posta Adresiniz',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _currentPasswordController,
              decoration: const InputDecoration(
                labelText: 'Mevcut Şifreniz',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newPasswordController,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifreniz',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmPasswordController,
              decoration: const InputDecoration(
                labelText: 'Yeni Şifrenizi Tekrar Girin',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                final email = _emailController.text.trim();
                final currentPassword = _currentPasswordController.text.trim();
                final newPassword = _newPasswordController.text.trim();
                final confirmPassword = _confirmPasswordController.text.trim();

                if (email.isEmpty || currentPassword.isEmpty || newPassword.isEmpty || confirmPassword.isEmpty) {
                  setState(() {
                    _statusMessage = 'Lütfen tüm alanları doldurun.';
                  });
                  return;
                }

                if (newPassword != confirmPassword) {
                  setState(() {
                    _statusMessage = 'Yeni şifreler eşleşmiyor.';
                  });
                  return;
                }

                await reauthenticateAndChangePassword(email, currentPassword, newPassword);
              },
              child: const Text('Şifreyi Değiştir'),
            ),
            const SizedBox(height: 20),
            Text(
              _statusMessage,
              style: TextStyle(
                color: _statusMessage.contains('başarıyla') ? Colors.green : Colors.red,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
}
