import 'strings.dart';

/// Translate a key, filling `{name}` placeholders. Missing keys show the key itself.
String tr(String lang, String key, [Map<String, Object?> vars = const {}]) {
  var s = strings[lang]?[key] ?? strings['en']?[key] ?? key;
  vars.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}
