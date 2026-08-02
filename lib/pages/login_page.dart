import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:ngy_app/pages/reset_password_page.dart';

import '../main.dart';
import '../news/blog_page.dart';
import '../providers/login_manager.dart';
import '../providers/user_provider.dart';
import 'bmi_calculator_page.dart';
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
            
            return SingleChildScrollView(
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
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Responsive logo size based on screen size
    double logoSize;
    if (isLargeScreen) {
      logoSize = 200;
    } else if (isMediumScreen) {
      logoSize = 180;
    } else {
      logoSize = 150;
    }
    
    // Responsive horizontal padding
    double horizontalPadding;
    if (isLargeScreen) {
      horizontalPadding = 48;
    } else if (isMediumScreen) {
      horizontalPadding = 36;
    } else {
      horizontalPadding = 24;
    }
    
    return Container(
      width: double.infinity,
      constraints: BoxConstraints(
        minHeight: screenHeight - MediaQuery.of(context).padding.top - kToolbarHeight,
      ),
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Company logo - bigger and centered
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: Image.asset(
                'assets/ngy.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text(
            'Hesabınıza Giriş Yapın',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 40),
          TextField(
            controller: loginProvider.emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              hintText: 'Emailinizi giriniz',
              labelText: 'Email',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.email),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: loginProvider.passwordController,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Şifrenizi giriniz',
              labelText: 'Şifre',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.lock),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 56,
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
                  borderRadius: BorderRadius.circular(12),
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
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ResetPasswordPage(email: '')),
              );
            },
            child: const Text(
              'Şifremi Unuttum',
              style: TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 24),
          // Public pages accessible without logging in
          const Row(
            children: [
              Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'Giriş yapmadan göz atın',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ),
              Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const BlogPage()),
                    );
                  },
                  icon: const Icon(Icons.article),
                  label: const Text('Blog'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BmiCalculatorPage(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.monitor_weight),
                  label: const Text('BKİ Hesaplama'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
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

