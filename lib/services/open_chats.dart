// lib/services/open_chats.dart
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Açık bir sohbet sayfasının kaydı (bkz. [OpenChats.open]).
class OpenChat {
  final String chatId;

  /// Sohbet sayfasının rotası: bildirimle başka sohbete geçilirken alttaki
  /// sohbet bununla kapatılır.
  final Route<dynamic>? route;

  /// Sohbet açıkken bu sohbetin bildirimine basılınca bildirimin mesaj
  /// kimliğiyle (yoksa null) çağrılır.
  final ValueChanged<String?>? onNotificationOpen;

  const OpenChat({
    required this.chatId,
    required this.route,
    required this.onNotificationOpen,
  });
}

/// Açık sohbet sayfaları, en üstteki (görünen) en sonda. Bildirim bastırma ve
/// bildirime basınca sohbete gitme bunu kullanır (bkz. `FcmService`).
///
/// Admin bir sohbetteyken başka bir sohbetin bildirimine basınca yeni sohbet
/// açık sohbetin üstüne açılır; geri tuşu önceki sohbete, oradan da sohbetin
/// açıldığı yere (sohbet listesi) döner. Üst üste en fazla
/// [maxStackedChats] sohbet kalır: bildirimlere basıldıkça sohbetler arkada
/// birikmez, en alttakiler kapatılır.
class OpenChats {
  /// Üst üste en fazla bu kadar sohbet açık kalır.
  static const int maxStackedChats = 2;

  final List<OpenChat> _chats = [];

  /// En üstteki (görünen) sohbet; yoksa null.
  String? get topChatId => _chats.isEmpty ? null : _chats.last.chatId;

  /// Sayfası hâlâ yığında duran sohbetler. Kapanış geçişindeki (ör. geri
  /// basıldı, geçiş uygulama arka plandayken bitmedi) sayfa kaydını ancak
  /// kapandığında siler; bildirim ona gitmez.
  List<OpenChat> get _activeChats => [
        for (final OpenChat chat in _chats)
          if (chat.route?.isActive ?? true) chat,
      ];

  /// Açık sohbet sayısı.
  int get length => _chats.length;

  /// Bir sohbet sayfası açıldı.
  void open(
    String chatId, {
    Route<dynamic>? route,
    ValueChanged<String?>? onNotificationOpen,
  }) {
    _chats.add(OpenChat(
      chatId: chatId,
      route: route,
      onNotificationOpen: onNotificationOpen,
    ));
  }

  /// Sohbet sayfası kapandı. Kayıt, sayfanın [open]'a verdiği işlevle
  /// bulunur: aynı sohbetin eski sayfası yenisi açıldıktan sonra kapanırsa
  /// yenisinin kaydı silinmez.
  void close(String chatId, {ValueChanged<String?>? onNotificationOpen}) {
    final int index = _chats.lastIndexWhere((chat) =>
        chat.chatId == chatId &&
        chat.onNotificationOpen == onNotificationOpen);
    if (index >= 0) _chats.removeAt(index);
  }

  /// Bildirimle sohbete geçerken kapatılmadan bırakılan rotalar: ilk sayfa,
  /// diyaloglar (kapatılan bir yükleme göstergesinin sahibi, sonra onu
  /// kapatırken alttaki sayfayı kapatırdı) ve kapanmadan önce soru soran
  /// sayfalar (ör. gönderilmemiş fotoğrafın düzenleme ekranı).
  static bool keepsRoute(Route<dynamic> route) =>
      route.isFirst ||
      route is RawDialogRoute ||
      route.popDisposition == RoutePopDisposition.doNotPop;

  /// Danışana kendi sohbetini gösterir: sohbet zaten açıksa ikinci bir sohbet
  /// sayfası açılmaz, sohbetin üstündeki sayfalar kapanır ve sohbet
  /// bildirimin mesajına (yoksa en yeni mesaja) gider; açık değilse
  /// [newRoute] açılır.
  void showClientChat(
    NavigatorState navigator,
    String chatId,
    String? focusMessageId,
    Route<void> Function() newRoute,
  ) {
    final List<OpenChat> active = _activeChats;
    final int index = active.lastIndexWhere((chat) => chat.chatId == chatId);
    if (index < 0) {
      navigator.push(newRoute());
      return;
    }
    _reveal(navigator, active[index], focusMessageId);
  }

  /// Admin'e bildirimdeki sohbeti gösterir.
  ///
  /// Sohbet zaten en üstteyse yeni sayfa açılmaz: üstündeki sayfalar kapanır,
  /// sohbet bildirimin mesajına (yoksa en yeni mesaja) gider. Değilse sohbet
  /// ([newRoute]) en üste açılır ve altında yalnızca şu an görünen sohbet
  /// kalır; daha alttaki sohbetler (bildirimin sohbeti alttaysa onun eski
  /// sayfası da), açtıkları sayfalarla (ör. Öğün Fotoğrafları) birlikte
  /// kapatılır.
  ///
  /// En üstte bir diyalog (ör. yükleme göstergesi) ya da kapanmadan soru soran
  /// bir sayfa varsa hiçbir şey yapılmaz: diyaloğun sahibi sonra onu
  /// kapatırken yeni sohbeti kapatırdı.
  void showAdminChat(
    NavigatorState navigator,
    String chatId,
    String? focusMessageId,
    Route<void> Function() newRoute,
  ) {
    final List<OpenChat> active = _activeChats;
    if (active.isNotEmpty && active.last.chatId == chatId) {
      _reveal(navigator, active.last, focusMessageId);
      return;
    }

    final Route<dynamic>? top = _topRoute(navigator);
    if (top != null && !top.isFirst && keepsRoute(top)) return;

    final int keep = maxStackedChats - 1;
    final List<OpenChat> older =
        active.sublist(0, math.max(0, active.length - keep));
    final Route<dynamic>? kept = active.isEmpty ? null : active.last.route;
    for (final OpenChat chat in older) {
      final Route<dynamic>? route = chat.route;
      if (route == null) continue;
      if (kept == null) {
        if (route.isActive) navigator.removeRoute(route);
        continue;
      }
      // Kalan sohbetin altından, kapatılan sohbete kadar (onun açtığı
      // sayfalar dahil) her şey kalkar.
      for (int i = 0; i < _maxRemovedRoutes && route.isActive; i++) {
        navigator.removeRouteBelow(kept);
      }
    }
    navigator.push(newRoute());
  }

  /// Bir bildirimle kaldırılan rota sayısının üst sınırı (emniyet payı).
  static const int _maxRemovedRoutes = 50;

  /// Yığının en üstündeki rota; hiçbir rota kapatılmaz.
  static Route<dynamic>? _topRoute(NavigatorState navigator) {
    Route<dynamic>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return top;
  }

  /// [chat]'in üstündeki sayfaları kapatır (bkz. [keepsRoute]) ve sohbeti
  /// bildirimin mesajına götürür.
  void _reveal(NavigatorState navigator, OpenChat chat, String? messageId) {
    final Route<dynamic>? target = chat.route;
    if (target != null) {
      navigator.popUntil((route) => route == target || keepsRoute(route));
    }
    chat.onNotificationOpen?.call(messageId);
  }
}
