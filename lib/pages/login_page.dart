import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ngy_app/pages/reset_password_page.dart';

import '../main.dart';
import '../providers/login_manager.dart';
import '../providers/user_provider.dart';
import 'kvkk_consent_page.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kullanıcı Girişi'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final screenSize = MediaQuery.of(context).size;
            // More nuanced device type detection
            final isLargeScreen = screenSize.width > 900;
            final isMediumScreen = screenSize.width > 600 && screenSize.width <= 900;
            final isSmallScreen = screenSize.width <= 600;
            
            return Center(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Consumer<LoginProvider>(
                    builder: (context, loginProvider, child) {
                      final errorMessage = loginProvider.errorMessage;
                      final isLoading = loginProvider.isLoading;

                      if (errorMessage.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _showErrorDialog(context, errorMessage);
                          loginProvider.clearError();
                        });
                      }

                      return _buildLoginForm(
                        context, 
                        loginProvider, 
                        isLoading, 
                        isLargeScreen, 
                        isMediumScreen, 
                        isSmallScreen
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLoginForm(
    BuildContext context, 
    LoginProvider loginProvider, 
    bool isLoading, 
    bool isLargeScreen,
    bool isMediumScreen,
    bool isSmallScreen
  ) {
    // Calculate responsive width based on screen size
    final screenWidth = MediaQuery.of(context).size.width;
    
    // Dynamic form width calculation based on screen category
    double formWidth;
    if (isLargeScreen) {
      formWidth = screenWidth * 0.35; // 35% of large screens
    } else if (isMediumScreen) {
      formWidth = screenWidth * 0.5; // 50% of medium screens
    } else {
      formWidth = screenWidth * 0.85; // 85% of small screens
    }
    
    // Set min/max constraints to avoid extremes
    formWidth = formWidth.clamp(300.0, 600.0);
    
    return Container(
      width: formWidth,
      padding: const EdgeInsets.all(20.0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.0),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 5,
            blurRadius: 7,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Company logo
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              'assets/ngy.png',
              width: 120,
              height: 120,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Hesabınıza Giriş Yapın',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 30),
          TextField(
            controller: loginProvider.emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              hintText: 'Emailinizi giriniz',
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: loginProvider.passwordController,
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Şifrenizi giriniz',
              labelText: 'Şifre',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.lock),
            ),
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () async {
                // If AUTO_LOGIN is true and user is already logged in, navigate directly
                if (AUTO_LOGIN && FirebaseAuth.instance.currentUser != null) {
                  if (context.mounted) {
                    await _navigateAfterLogin(context);
                  }
                  return;
                }

                // Otherwise, use form credentials to login
                final ok = await loginProvider.login(context);

                if (ok && context.mounted) {
                  await _navigateAfterLogin(context);
                }
              },
              style: ElevatedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Giriş Yap',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ResetPasswordPage(email: '')),
              );
            },
            child: const Text('Şifremi Unuttum'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hata'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  /// Navigates to the appropriate page after successful login.
  /// Checks KVKK consent and redirects to consent page if needed.
  Future<void> _navigateAfterLogin(BuildContext context) async {
    final userId = FirebaseAuth.instance.currentUser?.uid;
    if (userId == null) return;

    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final hasConsent = await userProvider.hasValidKvkkConsent(userId: userId);

    if (!context.mounted) return;

    if (hasConsent) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomePage()),
      );
    } else {
      // Redirect to KVKK consent page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const KvkkConsentPage()),
      );
    }
  }
}

