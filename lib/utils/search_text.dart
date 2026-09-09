/// Danışan/kayıt aramalarında kullanılan metin normalizasyonu ve eşleştirme.
///
/// İki sorunu birden çözer:
/// - **Türkçe harfler:** Dart'ın `toLowerCase()` metodu "I" harfini "i" yapar,
///   "İ" için ise birleşik bir karakter üretir. Bu yüzden harfler ASCII
///   karşılıklarına katlanır: "İnci" yazan da "inci" yazan da bulur.
/// - **Yanlış eşleşme:** Arama, alanın herhangi bir yerinde değil **kelime
///   başında** aranır. Böylece "si" sorgusu "Simge"yi bulur ama "Oya Oytan"ı
///   getirmez. (Eski hâlinde sorgu, rastgele karakterlerden oluşan uid'nin
///   içinde de aranıyordu ve iki harflik sorgular alakasız danışanları
///   getiriyordu.)
library;

const Map<String, String> _turkishFolding = {
  'ı': 'i',
  'İ': 'i',
  'I': 'i',
  'ç': 'c',
  'Ç': 'c',
  'ş': 's',
  'Ş': 's',
  'ğ': 'g',
  'Ğ': 'g',
  'ö': 'o',
  'Ö': 'o',
  'ü': 'u',
  'Ü': 'u',
  'â': 'a',
  'Â': 'a',
  'î': 'i',
  'Î': 'i',
  'û': 'u',
  'Û': 'u',
};

/// [input] metnini aramaya uygun hâle getirir: küçük harf + Türkçe harflerin
/// ASCII karşılığı. Harf/rakam dışındaki karakterler korunur; kelimelere
/// ayırma işini [searchWordsOf] yapar.
String normalizeSearchText(String input) {
  final StringBuffer buffer = StringBuffer();
  for (final int rune in input.runes) {
    final String ch = String.fromCharCode(rune);
    final String? folded = _turkishFolding[ch];
    buffer.write(folded ?? ch.toLowerCase());
  }
  return buffer.toString();
}

/// [input] içindeki aranabilir kelimeler (normalize edilmiş).
///
/// Ad soyad, e-posta gibi alanlar boşluk, nokta, "@", tire gibi ayraçlardan
/// bölünür: "oya.oytan@mail.com" -> [oya, oytan, mail, com].
List<String> searchWordsOf(String input) {
  final String normalized = normalizeSearchText(input);
  return normalized
      .split(RegExp(r'[^a-z0-9]+'))
      .where((word) => word.isNotEmpty)
      .toList();
}

/// Bir kaydın önceden hesaplanmış arama kelimeleri, sorguya uyuyor mu.
///
/// Sorgu birden fazla kelimeyse ("ayşe yıl") hepsinin ayrı ayrı bir kelimenin
/// başına uyması gerekir; böylece "ayşe yıl" yazınca "Ayşe Yılmaz" bulunur.
bool matchesSearchWords(List<String> queryWords, List<String> targetWords) {
  if (queryWords.isEmpty) return true;

  for (final String queryWord in queryWords) {
    bool matched = false;
    for (final String targetWord in targetWords) {
      if (targetWord.startsWith(queryWord)) {
        matched = true;
        break;
      }
    }
    if (!matched) return false;
  }
  return true;
}
