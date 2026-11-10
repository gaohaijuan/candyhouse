extends RefCounted
## Game language. The game is written in Simplified Chinese; every other
## language is a table data/i18n/<code>.json mapping each Chinese string (as
## it appears in scripts and data, format strings included) to its
## translation. Labels translate their text on their own; composed strings
## go through tr()/Lang.t() before formatting. Art with words in it has a
## per-language twin (<name>_<code>.png), picked by Art.ui.

const LANGS := [["en", "English"], ["zh", "简体中文"]]
const DEFAULT := "en"

static var code := ""

## Loads the tables once and switches to `lang` (unknown codes fall back to
## the default).
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
	code = lang if LANGS.any(func(l): return l[0] == lang) else DEFAULT
	TranslationServer.set_locale(code)

static func t(s: String) -> String:
	return TranslationServer.translate(s)

static func is_zh() -> bool:
	return code == "zh"

static func name_of(lang: String) -> String:
	for l in LANGS:
		if l[0] == lang:
			return l[1]
	return lang

## The language after the current one (the settings row cycles through them).
static func next() -> String:
	for i in LANGS.size():
		if LANGS[i][0] == code:
			return LANGS[(i + 1) % LANGS.size()][0]
	return DEFAULT
