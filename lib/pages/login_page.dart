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

// ---------------------------------------------------------------------------
// Login page vertical layout ratio
//
// The login screen is split vertically into two areas: the logo on top and the
// email/password (form) area below. These two flex values decide how the screen
// height is shared between them and should ADD UP TO 100, so you can read them
// as percentages and tune the ratio here (bigger logo → raise the logo value
// and lower the form value, keeping the sum at 100).
// ---------------------------------------------------------------------------

/// Share of the screen height taken by the logo area (out of 100).
const int kLoginLogoAreaFlex = 40;

/// Share of the screen height taken by the email/password (form) area
/// (out of 100). Should be `100 - kLoginLogoAreaFlex`.
const int kLoginFormAreaFlex = 60;

/// Upper bound (in logical pixels) for the logo's side length, so it doesn't
/// grow absurdly large on wide/tall screens even when its area is big.
const double kLoginLogoMaxSize = 360;

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

            // Height available for the logo/form split. Falls back to the
            // screen height if the constraint is unbounded.
            final availableHeight = constraints.maxHeight.isFinite
                ? constraints.maxHeight
                : screenSize.height;

            return Consumer<LoginProvider>(
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
                  isSmallScreen,
                  availableHeight,
                );
              },
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
    bool isSmallScreen,
    double availableHeight,
  ) {
    // Responsive horizontal padding
    double horizontalPadding;
    if (isLargeScreen) {
      horizontalPadding = 48;
    } else if (isMediumScreen) {
      horizontalPadding = 36;
    } else {
      horizontalPadding = 24;
    }

    // The screen height is shared between the logo area and the email/password
    // (form) area using the kLoginLogoAreaFlex / kLoginFormAreaFlex constants
    // (which add up to 100). The form area scrolls internally so its contents
    // stay readable and never overflow when its share is small.
    return Container(
      width: double.infinity,
      height: availableHeight,
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // ----- Logo area -----
          Expanded(
            flex: kLoginLogoAreaFlex,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: kLoginLogoMaxSize,
                  maxHeight: kLoginLogoMaxSize,
                ),
                child: AspectRatio(
                  aspectRatio: 1,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/ngy.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ----- Email / password (form) area -----
          Expanded(
            flex: kLoginFormAreaFlex,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const Text(
                    'Hesabınıza Giriş Yapın',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
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
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 24),
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
                              style: TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
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
                  const SizedBox(height: 16),
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
                  const SizedBox(height: 12),
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
            ),
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

