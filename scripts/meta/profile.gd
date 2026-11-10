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
		"chests_opened": 0, "chapter_chests": [],
		"checkin": {"day": 0, "last": ""},
		"purchases": {}, "no_ads": false,
		"settings": {"music": true, "sfx": true, "vibrate": true},
		"privacy_accepted": false,
		"ads_today": {"date": "", "counts": {}},
		"first_day": "",
		"last_interstitial": 0, "levels_since_ad": 0,
		"failures": {"level": 0, "count": 0}, "perfect_chests": [],
		"house": {"placed": {}, "owned": [], "rewarded": []},
		"offers": {}, "offers_seen": [],
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
	var pc: Array = []
	for v in data.get("perfect_chests", []):
		pc.append(int(v))
	data.perfect_chests = pc
	for k in economy.start_boosters:
		data.boosters[k] = int(data.boosters.get(k, 0))
	for k in ["placed", "owned", "rewarded"]:
		if not data.house.has(k):
			data.house[k] = {} if k == "placed" else []
	for room in data.house.placed:
		for slot in data.house.placed[room]:
			var e: Dictionary = data.house.placed[room][slot]
			e.color = int(e.get("color", -1))

## Calendar day in the player's local time zone (check-in and daily limits
## reset at local midnight).
static var tz_seconds := int(Time.get_time_zone_from_system().get("bias", 0)) * 60

static func day_key(now: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(now + tz_seconds)
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
	data.failures = {"level": 0, "count": 0}
	return int(coins)

# ---------------------------------------------------------------- comeback gifts

const GIFT_KINDS := ["undo", "move_out", "shuffle"]

## Producer 2026-11-09: a failed level is retried with one random booster as a
## gift, after two or more failures with two (the cap). Gifts last one attempt
## only; once they are used up the player buys their own.
func note_failure(level_id: int) -> void:
	var f: Dictionary = data.get("failures", {})
	var count := int(f.get("count", 0)) if int(f.get("level", 0)) == level_id else 0
	data.failures = {"level": level_id, "count": count + 1}

func gift_count(level_id: int) -> int:
	var f: Dictionary = data.get("failures", {})
	if int(f.get("level", 0)) != level_id:
		return 0
	return mini(int(f.get("count", 0)), int(economy.get("comeback_gifts_max", 2)))

## Distinct booster kinds for this attempt's gifts.
static func pick_gifts(n: int, rng: RandomNumberGenerator) -> Array:
	var kinds: Array = GIFT_KINDS.duplicate()
	var out: Array = []
	for i in mini(n, kinds.size()):
		out.append(kinds.pop_at(rng.randi_range(0, kinds.size() - 1)))
	return out

## The chest at the end of each chapter: granted once, on the first win of
## levels 10, 20, ... Returns the reward, or {} when there is none.
func claim_chapter_chest(level_id: int) -> Dictionary:
	var c: Dictionary = economy.get("chapter_chest", {})
	if c.is_empty() or level_id % int(c.every) != 0:
		return {}
	var got: Array = data.get("chapter_chests", [])
	if got.has(level_id):
		return {}
	got.append(level_id)
	data.chapter_chests = got
	add_coins(int(c.coins))
	for k in c.boosters:
		add_booster(k, int(c.boosters[k]))
	return {"coins": int(c.coins), "boosters": c.boosters.duplicate()}

## The perfect chest on the map: every level won with three stars has one,
## opened once from its stars on the map. Bigger for harder levels.
func perfect_chest_ready(level_id: int) -> bool:
	return int(data.stars.get(str(level_id), 0)) >= 3 and not data.get("perfect_chests", []).has(level_id)

## `picks` choose the random boosters (each 0..2); `difficulty` as in record_win.
func claim_perfect_chest(level_id: int, difficulty: String, picks: Array) -> Dictionary:
	if not perfect_chest_ready(level_id):
		return {}
	var c: Dictionary = economy.perfect_chest.get(difficulty, economy.perfect_chest.normal)
	var got: Array = data.get("perfect_chests", [])
	got.append(level_id)
	data.perfect_chests = got
	add_coins(int(c.coins))
	var boosters := {}
	for i in int(c.boosters):
		var kind: String = GIFT_KINDS[clampi(int(picks[i]) if i < picks.size() else 0, 0, 2)]
		boosters[kind] = int(boosters.get(kind, 0)) + 1
		add_booster(kind)
	return {"coins": int(c.coins), "boosters": boosters}

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
	if p.has("from_level") and not data.offers.has(id):
		return false
	if p.has("days") and now >= _offer_end(id):
		return false
	return true

## Offers with `from_level` open when the player reaches that level and run
## `days` from then; others with `days` run from the first day played.
## Returns the ids that opened now.
func start_offers(now: int) -> Array:
	var opened: Array = []
	for p in economy.iap:
		if p.has("from_level") and not data.offers.has(p.id) and int(data.unlocked) >= int(p.from_level):
			data.offers[p.id] = now
			opened.append(p.id)
	return opened

func _offer_end(id: String) -> int:
	var p := iap(id)
	var start: int
	if p.has("from_level"):
		start = int(data.offers.get(id, 0))
	else:
		start = Time.get_unix_time_from_datetime_string(data.first_day + "T00:00:00") - tz_seconds
	return start + int(p.days) * 86400

## Seconds left before a time-limited offer disappears (0 if none or over).
func iap_seconds_left(id: String, now: int) -> int:
	if not iap(id).has("days") or not iap_available(id, now):
		return 0
	return maxi(0, _offer_end(id) - now)

## Whole days left before a time-limited offer disappears (0 if none).
func iap_days_left(id: String, now: int) -> int:
	return ceili(iap_seconds_left(id, now) / 86400.0)

## A newly opened offer pops up once by itself; returns true the first time.
func offer_first_show(id: String) -> bool:
	if data.offers_seen.has(id):
		return false
	data.offers_seen.append(id)
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

# ---------------------------------------------------------------- candy house
# Rooms come from data/house.json. Each slot holds one of its items and a
# colour (index into the palette, -1 = the item's own colour). Bought items
# stay owned, so switching back to one is free.

func house_slot(room: String, slot: String) -> Dictionary:
	return data.house.placed.get(room, {}).get(slot, {})

func house_owns(item: String) -> bool:
	return data.house.owned.has(item)

## Puts `item` in the slot, paying its price unless already owned.
func house_place(room: String, slot: String, item: Dictionary) -> bool:
	if not house_owns(item.id):
		if not spend(int(item.price)):
			return false
		data.house.owned.append(item.id)
	if not data.house.placed.has(room):
		data.house.placed[room] = {}
	var old := house_slot(room, slot)
	data.house.placed[room][slot] = {"item": item.id, "color": int(old.get("color", -1))}
	return true

func house_set_color(room: String, slot: String, color: int) -> bool:
	var e := house_slot(room, slot)
	if e.is_empty():
		return false
	e.color = color
	return true

## Filled slots and all slots of a room.
func house_progress(room_def: Dictionary) -> Vector2i:
	var n := 0
	for s in room_def.slots:
		if not house_slot(room_def.id, s.id).is_empty():
			n += 1
	return Vector2i(n, room_def.slots.size())

func house_reward_ready(room_def: Dictionary) -> bool:
	var p := house_progress(room_def)
	return p.x == p.y and not data.house.rewarded.has(room_def.id)

## Pays the room's completion reward once; returns it, or {} if not ready.
func claim_house_reward(room_def: Dictionary) -> Dictionary:
	if not house_reward_ready(room_def):
		return {}
	data.house.rewarded.append(room_def.id)
	var r: Dictionary = room_def.reward
	add_coins(int(r.get("coins", 0)))
	for k in r.get("boosters", {}):
		add_booster(k, int(r.boosters[k]))
	return r
