extends RefCounted
## The player's saved progress and wallet. Pure data and rules: no nodes, no
## UI. Time comes from `now` (unix seconds) so tests can move the clock.

const SAVE_PATH := "user://profile.json"

var economy: Dictionary
var data: Dictionary
var path := SAVE_PATH

func _init(economy_def: Dictionary, save_path := SAVE_PATH) -> void:
	economy = economy_def
	path = save_path
	data = _fresh(0)

func _fresh(now: int) -> Dictionary:
	return {
		"coins": int(economy.start_coins),
		"boosters": economy.start_boosters.duplicate(),
		"lives": int(economy.lives.max), "lives_at": now,
		"unlocked": 1, "stars": {},
		"chests_opened": 0,
		"checkin": {"day": 0, "last": ""},
		"purchases": {}, "no_ads": false,
		"settings": {"music": true, "sfx": true, "vibrate": true},
		"privacy_accepted": false,
		"ads_today": {"date": "", "counts": {}},
		"first_day": "",
		"last_interstitial": 0, "levels_since_ad": 0,
	}

# ---------------------------------------------------------------- persistence

func load_or_create(now: int) -> void:
	data = _fresh(now)
	if FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			for k in parsed:
				data[k] = parsed[k]
	if data.first_day == "":
		data.first_day = day_key(now)
	_normalize()

func save() -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(data))

func _normalize() -> void:
	data.coins = int(data.coins)
	data.lives = int(data.lives)
	data.lives_at = int(data.lives_at)
	data.unlocked = int(data.unlocked)
	for k in economy.start_boosters:
		data.boosters[k] = int(data.boosters.get(k, 0))

static func day_key(now: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(now)
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]

# ---------------------------------------------------------------- coins

func can_afford(amount: int) -> bool:
	return data.coins >= amount

func spend(amount: int) -> bool:
	if amount < 0 or data.coins < amount:
		return false
	data.coins -= amount
	return true

func add_coins(amount: int) -> void:
	data.coins += maxi(0, amount)

# ---------------------------------------------------------------- boosters

func booster_count(kind: String) -> int:
	return int(data.boosters.get(kind, 0))

func use_booster(kind: String) -> bool:
	if booster_count(kind) <= 0:
		return false
	data.boosters[kind] = booster_count(kind) - 1
	return true

func add_booster(kind: String, n := 1) -> void:
	data.boosters[kind] = booster_count(kind) + n

func buy_booster(kind: String) -> bool:
	if not spend(int(economy.booster_price[kind])):
		return false
	add_booster(kind)
	return true

func buy_bundle() -> bool:
	if not spend(int(economy.booster_bundle.price)):
		return false
	for k in ["undo", "move_out", "shuffle"]:
		add_booster(k, int(economy.booster_bundle.each))
	return true

# ---------------------------------------------------------------- lives

## Applies regeneration up to `now` and returns the current lives.
func lives(now: int) -> int:
	var cap := int(economy.lives.max)
	var step := int(economy.lives.regen_seconds)
	if data.lives >= cap:
		data.lives_at = now
		return data.lives
	var gained: int = (now - int(data.lives_at)) / step
	if gained > 0:
		data.lives = mini(cap, data.lives + gained)
		data.lives_at = now if data.lives >= cap else data.lives_at + gained * step
	return data.lives

## Seconds until the next life, or 0 when full.
func next_life_in(now: int) -> int:
	if lives(now) >= int(economy.lives.max):
		return 0
	return int(economy.lives.regen_seconds) - (now - data.lives_at)

func level_costs_life(level_id: int) -> bool:
	return level_id > int(economy.lives.free_until_level)

## Called when a level is lost (wins never cost a life).
func lose_life(now: int, level_id: int) -> void:
	if not level_costs_life(level_id):
		return
	var cap := int(economy.lives.max)
	if lives(now) >= cap:
		data.lives_at = now
	data.lives = maxi(0, data.lives - 1)

func add_life(now: int, n := 1) -> void:
	lives(now)
	data.lives = mini(int(economy.lives.max), data.lives + n)

func refill_lives(now: int) -> bool:
	if lives(now) >= int(economy.lives.max) or not spend(int(economy.lives.refill_price)):
		return false
	data.lives = int(economy.lives.max)
	data.lives_at = now
	return true

# ---------------------------------------------------------------- levels and stars

## Records a win; returns the coins earned (before any ad doubling).
func record_win(level_id: int, stars: int, difficulty := "normal") -> int:
	var key := str(level_id)
	var best := int(data.stars.get(key, 0))
	data.stars[key] = maxi(best, stars)
	data.unlocked = maxi(data.unlocked, level_id + 1)
	var w: Dictionary = economy.win_coins
	var coins: float = float(w.base) + float(w.per_star) * stars
	if difficulty == "hard":
		coins *= float(w.hard_mult)
	elif difficulty == "super":
		coins *= float(w.super_mult)
	add_coins(int(coins))
	return int(coins)

func total_stars() -> int:
	var n := 0
	for k in data.stars:
		n += int(data.stars[k])
	return n

## Stars collected toward the next chest, and whether one can be opened.
func chest_progress() -> Vector2i:
	var need := int(economy.star_chest.stars)
	return Vector2i(total_stars() - int(data.chests_opened) * need, need)

func can_open_chest() -> bool:
	var p := chest_progress()
	return p.x >= p.y

## Opens a star chest; `pick` chooses the random booster (0..2).
func open_chest(pick: int) -> Dictionary:
	if not can_open_chest():
		return {}
	data.chests_opened = int(data.chests_opened) + 1
	add_coins(int(economy.star_chest.coins))
	var kind: String = ["undo", "move_out", "shuffle"][clampi(pick, 0, 2)]
	add_booster(kind, int(economy.star_chest.random_booster))
	return {"coins": int(economy.star_chest.coins), "boosters": {kind: int(economy.star_chest.random_booster)}}

# ---------------------------------------------------------------- daily check-in

## Day index (0-6) available today, or -1 if already claimed today.
func checkin_today(now: int) -> int:
	var today := day_key(now)
	if data.checkin.last == today:
		return -1
	var yesterday := day_key(now - 86400)
	var streak := int(data.checkin.day)
	if data.checkin.last != yesterday:
		streak = 0
	return streak % 7

func claim_checkin(now: int, double := false) -> Dictionary:
	var i := checkin_today(now)
	if i < 0:
		return {}
	var reward: Dictionary = economy.checkin[i]
	var mult := 2 if double else 1
	add_coins(int(reward.get("coins", 0)) * mult)
	for k in reward.get("boosters", {}):
		add_booster(k, int(reward.boosters[k]) * mult)
	data.checkin = {"day": i + 1, "last": day_key(now)}
	return {"day": i, "reward": reward, "mult": mult}

# ---------------------------------------------------------------- ads

func ads_left(kind: String, now: int) -> int:
	_roll_ad_day(now)
	return int(economy.ad_limits.get(kind, 0)) - int(data.ads_today.counts.get(kind, 0))

func note_ad(kind: String, now: int) -> void:
	_roll_ad_day(now)
	data.ads_today.counts[kind] = int(data.ads_today.counts.get(kind, 0)) + 1

func _roll_ad_day(now: int) -> void:
	var today := day_key(now)
	if data.ads_today.date != today:
		data.ads_today = {"date": today, "counts": {}}

## Whether an interstitial may show after finishing `level_id` (wins only).
func interstitial_due(level_id: int, now: int) -> bool:
	var rule: Dictionary = economy.interstitial
	data.levels_since_ad = int(data.levels_since_ad) + 1
	if data.no_ads or level_id < int(rule.from_level):
		return false
	if int(data.levels_since_ad) < int(rule.every_levels):
		return false
	if now - int(data.last_interstitial) < int(rule.min_seconds):
		return false
	data.levels_since_ad = 0
	data.last_interstitial = now
	return true

# ---------------------------------------------------------------- purchases

func iap(id: String) -> Dictionary:
	for p in economy.iap:
		if p.id == id:
			return p
	return {}

func iap_available(id: String, now: int) -> bool:
	var p := iap(id)
	if p.is_empty():
		return false
	if p.get("once", false) and data.purchases.has(id):
		return false
	if p.has("days"):
		var first: int = Time.get_unix_time_from_datetime_string(data.first_day + "T00:00:00")
		if now - first > int(p.days) * 86400:
			return false
	return true

## Grants a completed purchase.
func grant_purchase(id: String, now: int) -> bool:
	if not iap_available(id, now):
		return false
	var p := iap(id)
	add_coins(int(p.get("coins", 0)))
	for k in p.get("boosters", {}):
		add_booster(k, int(p.boosters[k]))
	if p.get("no_ads", false):
		data.no_ads = true
	data.purchases[id] = int(data.purchases.get(id, 0)) + 1
	return true
