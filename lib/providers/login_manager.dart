import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/logger.dart';

final Logger logger = Logger.forClass(LoginProvider);

///TODO: mail/şifre yanlış girince defaulta düşüyor. login methodu commentler yer değiştirmeli uncommented yerlerle
/// Manages user authentication and login state
/// Provides functionality for user login and error handling
class LoginProvider extends ChangeNotifier {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  bool _isLoading = false;
  String _errorMessage = '';

  /// Whether the login process is currently in progress
  bool get isLoading => _isLoading;
  
  /// The current error message, if any
  String get errorMessage => _errorMessage;

  /// Attempts to log in with the provided email and password.
  /// 
  /// @param context The BuildContext for potential UI interactions
  /// 
  /// @return A boolean indicating whether the login was successful
  Future<bool> login(BuildContext context) async {
    // windowsta cacheden login oluyor durumu vardı o yüzden burası var
    // if (FirebaseAuth.instance.currentUser != null) {
    //   if (kDebugMode) {
    //     await FirebaseAuth.instance
    //         .signOut(); // always start logged out on debug
    //   }
    // }
    _setLoadingState(true);
    _errorMessage = '';
    bool isLoginSuccessful = false;
    try {
    await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );
    isLoginSuccessful = true;


    } on FirebaseAuthException catch (e) {
      _handleFirebaseAuthError(e);
      // return false;
    } catch (e) {
      _errorMessage = 'Beklenmeyen bir hata oluştu.';
      logger.err('Unexpected error during sign-in: {}', [e.toString()]);
      // return false;
    }
    logger.info('isLoginSuccessful={}',[isLoginSuccessful]);
    _setLoadingState(false);
    notifyListeners();
    return isLoginSuccessful;
  }

  /// Handles Firebase Authentication errors and sets appropriate error messages.
  /// 
  /// @param e The FirebaseAuthException to handle
  void _handleFirebaseAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-credential':
        _errorMessage = 'E-posta adresi veya şifre yanlış, lütfen kontrol ediniz.';
        break;
      case 'invalid-email':
        _errorMessage = 'Geçersiz e-posta adresi.';
        break;
      case 'user-disabled':
        _errorMessage = 'Bu kullanıcı hesabı devre dışı bırakılmış.';
        break;
      case 'user-not-found':
        _errorMessage = 'Kullanıcı bulunamadı.';
        break;
      case 'wrong-password':
        _errorMessage = 'Girdiğiniz şifre yanlış. Lütfen tekrar deneyiniz.';
        break;
      default:
        _errorMessage = 'Giriş yaparken beklenmeyen bir hata oluştu. Lütfen mailinizi ve şifrenizi kontrol ediniz.';
        break;
    }
    logger.err('Firebase auth error: {}', [e.code]);
    notifyListeners();
  }

  /// Clears the error message.
  void clearError() {
    _errorMessage = '';
    notifyListeners();
  }

  /// Validates that email and password fields are not empty.
  /// 
  /// @return A boolean indicating whether the inputs are valid
  bool _validateInputs() {
    if (emailController.text.trim().isEmpty || passwordController.text.trim().isEmpty) {
      _errorMessage = 'Lütfen alanları doldurunuz.';
      return false;
    }
    return true;
  }

  /// Updates the loading state and notifies listeners.
  /// 
  /// @param isLoading The new loading state
  void _setLoadingState(bool isLoading) {
    _isLoading = isLoading;
    notifyListeners();
  }

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }
}