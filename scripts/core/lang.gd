extends RefCounted
## Game language. The game is written in Simplified Chinese; every other
## language is a table data/i18n/<code>.json mapping each Chinese string (as
## it appears in scripts and data, format strings included) to its
## translation. Labels translate their text on their own; composed strings
## go through tr()/Lang.t() before formatting. Art with words in it has a
## per-language twin (<name>_<code>.png), picked by Art.ui.

const LANGS := [["en", "English"], ["zh", "简体中文"], ["ja", "日本語"], ["ko", "한국어"]]
const DEFAULT := "en"
# Each language's own rounded font, with the others behind it so any
# language name (日本語, 한국어) still draws in the settings row.
const FONT_FILES := {
	"zh": "res://assets/fonts/LXGW975YuanSC-700W.ttf",
	"ja": "res://assets/fonts/MPLUSRounded1c-Bold.ttf",
	"ko": "res://assets/fonts/Jua-Regular.ttf",
}

static var code := ""
static var _fonts := {}
static var _own: Array[RegEx] = []     # this language's texts as patterns (checks)

## The device's language when the game has it (any Chinese reads Simplified),
## else English.
static func system() -> String:
	var l := OS.get_locale_language()
	return l if l in ["zh", "ja", "ko"] else DEFAULT

## Loads the tables once and switches to `lang`: "" follows the device,
## unknown codes fall back to the default.
static func use(lang: String) -> void:
	if code == "":
		for l in LANGS:
			var path: String = "res://data/i18n/%s.json" % l[0]
			if not FileAccess.file_exists(path):
				continue
			var table = JSON.parse_string(FileAccess.get_file_as_string(path))
			if not table is Dictionary:
				continue
			var tr := Translation.new()
			tr.locale = l[0]
			for k in table:
				tr.add_message(k, table[k])
			TranslationServer.add_translation(tr)
	if lang == "":
		lang = system()
	code = lang if LANGS.any(func(l): return l[0] == lang) else DEFAULT
	TranslationServer.set_locale(code)

## The game font for the current language (English uses the Chinese
## font's Latin letters, as before).
static func font() -> Font:
	var c := code if code in FONT_FILES else "zh"
	if not _fonts.has(c):
		var f: FontFile = (load(FONT_FILES[c]) as FontFile).duplicate()
		var rest: Array[Font] = []
		for k in ["zh", "ja", "ko"]:
			if k != c:
				rest.append(load(FONT_FILES[k]))
		f.fallbacks = rest
		_fonts[c] = f
	return _fonts[c]

static func t(s: String) -> String:
	return TranslationServer.translate(s)

## For screenshot checks: true when a shown text still reads as the Chinese
## source. Chinese characters give it away, except in Japanese, where kanji
## are fine when the text has kana or matches one of the Japanese texts.
static func looks_untranslated(shown: String) -> bool:
	if is_zh() or LANGS.any(func(l): return shown.contains(l[1])):
		return false
	if not RegEx.create_from_string("[\\x{4e00}-\\x{9fff}]").search(shown):
		return false
	if code != "ja":
		return true
	if RegEx.create_from_string("[\\x{3040}-\\x{30ff}]").search(shown):
		return false
	if _own.is_empty():
		var table = JSON.parse_string(FileAccess.get_file_as_string("res://data/i18n/ja.json"))
		for k in table:
			var pat := "^" + RegEx.create_from_string("([\\\\^$.|?*+()\\[\\]{}])").sub(String(table[k]), "\\$1", true) + "$"
			pat = RegEx.create_from_string("%0?\\d?[ds]").sub(pat, ".+", true)
			_own.append(RegEx.create_from_string(pat))
	return not _own.any(func(r): return r.search(shown) != null)

static func is_zh() -> bool:
	return code == "zh"

static func name_of(lang: String) -> String:
	for l in LANGS:
		if l[0] == lang:
			return l[1]
	return lang
