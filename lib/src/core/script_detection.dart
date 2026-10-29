/// Letters used in Urdu but not in Arabic or Persian (spec §6.4).
const _urduOnlyLetters = {'ٹ', 'ڈ', 'ڑ', 'ں', 'ے', 'ھ', 'ہ'};

bool containsUrduLetters(String text) => text.runes.any(
  (rune) => _urduOnlyLetters.contains(String.fromCharCode(rune)),
);

bool isArabicScript(String text) => text.runes.any(_isArabicRune);

bool _isArabicRune(int rune) =>
    (rune >= 0x0600 && rune <= 0x06FF) ||
    (rune >= 0x0750 && rune <= 0x077F) ||
    (rune >= 0xFB50 && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF);
