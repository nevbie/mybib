/// Strip everything but digits (and a trailing X of an ISBN-10).
String cleanCode(String raw) => raw.toUpperCase().replaceAll(RegExp(r'[^0-9X]'), '').replaceAll(RegExp(r'X(?=.)'), '');

bool isValidIsbn10(String s) {
  if (!RegExp(r'^\d{9}[\dX]$').hasMatch(s)) return false;
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    sum += (s[i] == 'X' ? 10 : int.parse(s[i])) * (10 - i);
  }
  return sum % 11 == 0;
}

/// EAN-13 checksum – ISBN-13 is an EAN-13 starting with 978/979.
bool isValidEan13(String s) {
  if (!RegExp(r'^\d{13}$').hasMatch(s)) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(s[i]) * (i.isOdd ? 3 : 1);
  }
  return (10 - sum % 10) % 10 == int.parse(s[12]);
}

bool isIsbn13(String s) => isValidEan13(s) && (s.startsWith('978') || s.startsWith('979'));

String isbn10to13(String s) {
  final core = '978${s.substring(0, 9)}';
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    sum += int.parse(core[i]) * (i.isOdd ? 3 : 1);
  }
  return '$core${(10 - sum % 10) % 10}';
}

/// Classify a scanned or typed code: 'isbn' (normalised to 13 digits), 'ean' or null (invalid).
({String type, String code})? classifyCode(String raw) {
  final s = cleanCode(raw);
  if (s.length == 10 && isValidIsbn10(s)) return (type: 'isbn', code: isbn10to13(s));
  if (s.length == 13 && isIsbn13(s)) return (type: 'isbn', code: s);
  if (s.length == 13 && isValidEan13(s)) return (type: 'ean', code: s);
  // UPC-A (12 digits) – common on US CDs / DVDs
  if (s.length == 12 && isValidEan13('0$s')) return (type: 'ean', code: s);
  if (s.length == 8 && RegExp(r'^\d+$').hasMatch(s)) return (type: 'ean', code: s);
  return null;
}
