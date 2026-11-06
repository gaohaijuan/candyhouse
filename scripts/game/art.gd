extends RefCounted
## Art lookup. Uses sliced textures when they exist and placeholder drawing
## otherwise, so code and art can land independently.

const DESSERTS := [
	{"key": "macaron", "name": "马卡龙", "color": Color("#F48FB1")},
	{"key": "donut", "name": "甜甜圈", "color": Color("#8D5A3B")},
	{"key": "cupcake", "name": "纸杯蛋糕", "color": Color("#E57373")},
	{"key": "cake", "name": "草莓蛋糕", "color": Color("#F06292")},
	{"key": "croissant", "name": "牛角包", "color": Color("#E0A040")},
	{"key": "icecream", "name": "冰淇淋", "color": Color("#4DB6AC")},
	{"key": "cookie", "name": "曲奇", "color": Color("#B07A4A")},
	{"key": "pudding", "name": "布丁", "color": Color("#F2B544")},
	{"key": "lollipop", "name": "棒棒糖", "color": Color("#BA68C8")},
	{"key": "chocolate", "name": "巧克力", "color": Color("#6D4C41")},
]

static var _cache: Dictionary = {}

static func texture(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path)
	_cache[path] = tex
	return tex

static func dessert_icon(type: int) -> Texture2D:
	return texture("res://assets/desserts/%s.png" % DESSERTS[type].key)

static func ui(name: String) -> Texture2D:
	return texture("res://assets/ui/%s.png" % name)

static var font: Font = load("res://assets/fonts/LXGW975YuanSC-700W.ttf")
