/// Letters used in Urdu but not in Arabic or Persian (spec §6.4).
const _urduOnlyLetters = {'ٹ', 'ڈ', 'ڑ', 'ں', 'ے', 'ھ', 'ہ'};

/// Letters Persian shares with Urdu but Arabic lacks (spec §6.4).
const _persianLetters = {'پ', 'چ', 'ژ', 'گ'};

bool containsUrduLetters(String text) => _containsAnyOf(text, _urduOnlyLetters);

bool containsPersianLetters(String text) =>
    _containsAnyOf(text, _persianLetters);

bool isArabicScript(String text) => text.runes.any(_isArabicRune);

bool isDevanagari(String text) =>
    text.runes.any((rune) => rune >= 0x0900 && rune <= 0x097F);

bool isBengaliScript(String text) =>
    text.runes.any((rune) => rune >= 0x0980 && rune <= 0x09FF);

bool isGurmukhi(String text) =>
    text.runes.any((rune) => rune >= 0x0A00 && rune <= 0x0A7F);

bool isLatinScript(String text) => text.contains(RegExp('[A-Za-z]'));

bool _containsAnyOf(String text, Set<String> letters) =>
    text.runes.any((rune) => letters.contains(String.fromCharCode(rune)));

bool _isArabicRune(int rune) =>
    (rune >= 0x0600 && rune <= 0x06FF) ||
    (rune >= 0x0750 && rune <= 0x077F) ||
    (rune >= 0xFB50 && rune <= 0xFDFF) ||
    (rune >= 0xFE70 && rune <= 0xFEFF);
