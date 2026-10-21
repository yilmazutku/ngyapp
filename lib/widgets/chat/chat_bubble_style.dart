// lib/widgets/chat/chat_bubble_style.dart
import 'package:flutter/material.dart';

/// Sohbet baloncuğunun renkleri: kendi mesajı ([mine]) WhatsApp'taki koyu
/// yeşil zemin üstünde açık renk yazı, karşı tarafınki ([other]) açık gri
/// zemin üstünde koyu yazı. Baloncuğun içindeki her parça (metin, saat, tik,
/// alıntı, öğün etiketi, yükleme baloncuğu) rengini buradan alır.
class ChatBubbleStyle {
  final Color background;
  final Color text;

  /// Saat, gönderim tiki, "fotoğraf silindi" notu gibi soluk yazılar.
  final Color secondaryText;

  /// Alıntı kutusunun zemini.
  final Color quoteBackground;

  /// Alıntının sol çizgisi ve gönderen adı; null ise temanın ana rengi.
  final Color? quoteAccent;

  /// Alıntının metni; null ise temanın metin rengi.
  final Color? quoteText;

  /// Baloncuktaki düğmelerin ("Tekrar dene", "Kaldır") yazısı; null ise
  /// temanın ana rengi.
  final Color? action;

  /// Baloncuktaki hata yazısı; null ise temanın hata rengi.
  final Color? error;

  /// Öğün etiketinin rengi öğünün renginin bu oranda beyaza açılmışı: koyu
  /// zeminde okunur kalsın.
  final double mealColorLightening;

  const ChatBubbleStyle._({
    required this.background,
    required this.text,
    required this.secondaryText,
    required this.quoteBackground,
    this.quoteAccent,
    this.quoteText,
    this.action,
    this.error,
    this.mealColorLightening = 0,
  });

  static const ChatBubbleStyle mine = ChatBubbleStyle._(
    background: Color(0xFF234B37),
    text: Colors.white,
    secondaryText: Color(0xFFA0B8AC),
    quoteBackground: Color(0xFF1C3B2C),
    quoteAccent: Color(0xFF6CC0B4),
    quoteText: Color(0xFFC9D8D2),
    action: Color(0xFF6CC0B4),
    error: Color(0xFFFFB4AB),
    mealColorLightening: 0.5,
  );

  static const ChatBubbleStyle other = ChatBubbleStyle._(
    background: Color(0xFFE0E0E0),
    text: Colors.black87,
    secondaryText: Colors.black54,
    quoteBackground: Color(0x0D000000),
  );

  static ChatBubbleStyle of({required bool isMe}) => isMe ? mine : other;

  /// [mealColor] renkli öğün etiketinin bu baloncuktaki rengi.
  Color mealLabel(Color mealColor) => mealColorLightening == 0
      ? mealColor
      : Color.lerp(mealColor, Colors.white, mealColorLightening)!;
}
