package app.mybib.core

/** The texts from shared/strings.json: `{ de: {key: text}, en: {...} }` with `{placeholder}`s. */
class Strings(val dicts: Map<String, Map<String, String>>) {
    /** Translate a key, filling `{name}` placeholders. Missing keys fall back to English, then to the key itself. */
    fun t(lang: String, key: String, vars: Map<String, Any?> = emptyMap()): String {
        var s = dicts[lang]?.get(key) ?: dicts["en"]?.get(key) ?: key
        vars.forEach { (k, v) -> s = s.replace("{$k}", "$v") }
        return s
    }

    companion object {
        fun parse(text: String) = Strings(
            parseJson(text).obj?.mapValues { (_, d) -> d.obj?.mapNotNull { (k, v) -> v.string?.let { k to it } }?.toMap() ?: emptyMap() } ?: emptyMap(),
        )
    }
}
