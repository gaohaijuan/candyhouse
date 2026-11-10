extends SceneTree
## Profile and economy tests: godot --headless --path . --script res://tests/meta_tests.gd

const Profile = preload("res://scripts/meta/profile.gd")
const Lang = preload("res://scripts/core/lang.gd")
const Kit = preload("res://scripts/ui/kit.gd")

var failures := 0
var checks := 0
var economy: Dictionary

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", what)

func fresh(now := 1_800_000_000) -> Profile:
	var p := Profile.new(economy, "user://test_profile.json")
	if FileAccess.file_exists(p.path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(p.path))
	p.load_or_create(now)
	return p

func _init() -> void:
	economy = JSON.parse_string(FileAccess.get_file_as_string("res://data/economy.json"))
	_coins_and_boosters()
	_lives()
	_wins_and_chests()
	_checkin()
	_ads()
	_purchases()
	_persistence()
	_comeback_gifts()
	_perfect_chests()
	_house()
	_language()
	print("checks=%d failures=%d" % [checks, failures])
	quit(1 if failures > 0 else 0)

func _coins_and_boosters() -> void:
	var p := fresh()
	check(p.data.coins == 200, "new player starts with 200 coins")
	check(p.booster_count("shuffle") == 3, "new player has 3 shuffles")
	check(not p.spend(201) and p.data.coins == 200, "cannot overspend")
	check(p.buy_booster("shuffle") and p.data.coins == 130 and p.booster_count("shuffle") == 4, "buy shuffle for 70")
	check(p.use_booster("shuffle") and p.booster_count("shuffle") == 3, "use a booster")
	p.data.coins = 450
	check(p.buy_bundle() and p.data.coins == 0 and p.booster_count("undo") == 6, "bundle gives 3 of each")
	check(not p.buy_booster("undo"), "cannot buy without coins")

func _lives() -> void:
	var t := 1_800_000_000
	var p := fresh(t)
	check(p.lives(t) == 5, "starts with full lives")
	p.lose_life(t, 3)
	check(p.lives(t) == 5, "levels 1-5 do not cost lives")
	p.lose_life(t, 6)
	check(p.lives(t) == 4, "losing level 6 costs a life")
	check(p.next_life_in(t) == 1800, "next life in 30 minutes")
	check(p.lives(t + 1799) == 4 and p.lives(t + 1800) == 5, "life regenerates after 30 minutes")
	for i in 5:
		p.lose_life(t + 1800, 10)
	check(p.lives(t + 1800) == 0, "can run out of lives")
	check(p.lives(t + 1800 + 2 * 1800 + 5) == 2, "two lives after an hour")
	check(p.next_life_in(t + 1800 + 2 * 1800 + 5) == 1800 - 5, "timer keeps the remainder")
	p.data.coins = 300
	check(p.refill_lives(t + 1800 + 3605) and p.lives(t + 1800 + 3605) == 5 and p.data.coins == 100, "refill for 200 coins")
	check(not p.refill_lives(t + 9999), "no refill when full")
	p.add_life(t + 9999, 3)
	check(p.lives(t + 9999) == 5, "add_life is capped")

func _wins_and_chests() -> void:
	var p := fresh()
	var c := p.record_win(1, 3)
	check(c == 40 and p.data.coins == 240, "3-star normal win pays 40")
	check(p.record_win(2, 1, "hard") == 30, "1-star hard win pays 30")
	check(p.record_win(3, 2, "super") == 60, "2-star super win pays 60")
	check(p.data.unlocked == 4, "wins unlock the next level")
	p.record_win(1, 1)
	check(int(p.data.stars["1"]) == 3, "best stars are kept")
	check(p.total_stars() == 6 and not p.can_open_chest(), "6 stars, chest closed")
	for i in range(4, 12):
		p.record_win(i, 3)
	check(p.total_stars() == 30 and p.can_open_chest(), "30 stars open a chest")
	var r := p.open_chest(1)
	check(r.coins == 100 and r.boosters.has("move_out") and not p.can_open_chest(), "chest pays and resets")
	check(p.chest_progress() == Vector2i(0, 30), "progress restarts at 0/30")

func _checkin() -> void:
	var day := 86400
	var t := 1_800_000_000
	var p := fresh(t)
	check(p.checkin_today(t) == 0, "first check-in is day 1")
	var coins: int = p.data.coins
	p.claim_checkin(t)
	check(p.data.coins == coins + 50 and p.checkin_today(t) == -1, "day 1 pays 50, once a day")
	check(p.checkin_today(t + day) == 1, "next day is day 2")
	p.claim_checkin(t + day, true)
	check(p.data.coins == coins + 50 + 160, "double claim pays twice")
	check(p.checkin_today(t + 3 * day) == 0, "a missed day restarts the streak")
	for i in 7:
		p.claim_checkin(t + (10 + i) * day)
	check(p.checkin_today(t + 17 * day) == 0, "after day 7 the cycle restarts")

func _ads() -> void:
	var t := 1_800_000_000
	var p := fresh(t)
	check(p.ads_left("free_coins", t) == 5, "5 free-coin ads a day")
	for i in 5:
		p.note_ad("free_coins", t)
	check(p.ads_left("free_coins", t) == 0, "limit reached")
	check(p.ads_left("free_coins", t + 86400) == 5, "limit resets the next day")
	check(not p.interstitial_due(5, t), "no interstitial before level 8")
	p.data.levels_since_ad = 0
	check(not p.interstitial_due(8, t) and not p.interstitial_due(9, t) and p.interstitial_due(10, t + 1000), "at most one interstitial per 3 levels")
	check(not p.interstitial_due(11, t + 1010) and not p.interstitial_due(12, t + 1020) and not p.interstitial_due(13, t + 1030), "90 s minimum gap")
	p.data.no_ads = true
	p.data.levels_since_ad = 10
	check(not p.interstitial_due(30, t + 99999), "no interstitials after buying no-ads")

func _purchases() -> void:
	var t := 1_800_000_000
	var p := fresh(t)
	check(p.grant_purchase("coins_3300", t) and p.data.coins == 3500, "coin pack adds coins")
	check(p.grant_purchase("coins_3300", t), "coin packs can be bought again")
	check(p.grant_purchase("starter", t) and p.booster_count("undo") == 8 and p.booster_count("magnet") == 3 and p.booster_count("extra_slot") == 3, "starter pack gives boosters")
	check(not p.iap_available("starter", t), "starter pack only once")
	var q := fresh(t)
	check(q.iap_available("starter", t + 40 * 86400), "starter pack never expires")
	# Limited pack: opens when level 5 is reached, ¥0.1, for 3 days from then.
	check(not q.iap_available("limited", t), "limited pack hidden before level 5")
	q.data.unlocked = 4
	check(q.start_offers(t).is_empty(), "limited pack still hidden at level 4")
	q.data.unlocked = 5
	var t5 := t + 5 * 86400
	check(q.start_offers(t5) == ["limited"] and q.start_offers(t5 + 10).is_empty(), "limited pack opens once at level 5")
	check(q.iap_available("limited", t5 + 2 * 86400) and q.iap_days_left("limited", t5 + 86400) == 2, "limited pack runs 3 days from level 5")
	check(not q.iap_available("limited", t5 + 3 * 86400), "limited pack gone after 3 days")
	check(q.offer_first_show("limited") and not q.offer_first_show("limited"), "limited pack pops up by itself once")
	check(float(q.iap("limited").price) < 1.0, "limited pack costs under a yuan")
	var r := fresh(t)
	r.data.unlocked = 5
	r.start_offers(t)
	var c0: int = r.data.coins
	check(r.grant_purchase("limited", t + 100) and r.data.coins == c0 + 200 and not r.iap_available("limited", t + 200), "limited pack buys once")
	check(q.grant_purchase("no_ads", t) and q.data.no_ads, "no-ads purchase")

func _persistence() -> void:
	var t := 1_800_000_000
	var p := fresh(t)
	p.data.coins = 777
	p.add_booster("magnet", 2)
	p.record_win(5, 2)
	p.save()
	var q := Profile.new(economy, "user://test_profile.json")
	q.load_or_create(t + 10)
	check(q.data.coins == p.data.coins and q.booster_count("magnet") == 3 and int(q.data.unlocked) == 6, "profile survives save and load")

func _comeback_gifts() -> void:
	var p := fresh()
	check(p.gift_count(7) == 0, "no gift before any failure")
	p.note_failure(7)
	check(p.gift_count(7) == 1, "one gift after the first failure")
	p.note_failure(7)
	p.note_failure(7)
	check(p.gift_count(7) == 2, "gifts cap at two")
	check(p.gift_count(8) == 0, "gifts belong to the failed level")
	p.note_failure(8)
	check(p.gift_count(8) == 1 and p.gift_count(7) == 0, "failing another level starts over")
	p.record_win(8, 2)
	check(p.gift_count(8) == 0, "a win clears the gifts")
	var rng := RandomNumberGenerator.new()
	for n in 3:
		var kinds: Array = Profile.pick_gifts(n, rng)
		var unique := {}
		for k in kinds:
			unique[k] = true
		check(kinds.size() == n and unique.size() == n, "%d distinct gift kinds" % n)
	var before := p.booster_count("undo")
	p.note_failure(9)
	check(p.booster_count("undo") == before, "gifts never enter the inventory")

func _perfect_chests() -> void:
	var p := fresh()
	p.record_win(4, 2)
	check(not p.perfect_chest_ready(4), "no chest below three stars")
	p.record_win(4, 3)
	check(p.perfect_chest_ready(4), "three stars leave a chest")
	var coins: int = p.data.coins
	var r := p.claim_perfect_chest(4, "normal", [1])
	check(r.coins == 60 and p.data.coins == coins + 60 and r.boosters.get("move_out", 0) == 1, "normal chest: 60 coins and the picked booster")
	check(p.claim_perfect_chest(4, "normal", [1]).is_empty() and not p.perfect_chest_ready(4), "a chest opens once")
	p.record_win(12, 3)
	var r2 := p.claim_perfect_chest(12, "super", [0, 0])
	check(r2.coins == 150 and r2.boosters.get("undo", 0) == 2, "super chest: 150 coins and two boosters")

func _house() -> void:
	var house: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/house.json"))
	var room: Dictionary = house.rooms[0]
	check(room.slots.size() == 10 and house.colors.size() == 8, "living room has 10 slots and 8 colours")
	for s in room.slots:
		check(s.items.size() == 3 and int(s.items[0].price) < int(s.items[1].price) and int(s.items[1].price) < int(s.items[2].price), "%s: three items, prices rising" % s.id)
	var p := fresh()
	var sofa: Dictionary = room.slots[3]
	p.data.coins = 1000
	check(not p.house_set_color("living", "sofa", 2), "cannot colour an empty slot")
	check(p.house_place("living", "sofa", sofa.items[0]) and p.data.coins == 750, "buy the basic sofa for 250")
	check(p.house_set_color("living", "sofa", 2) and p.house_slot("living", "sofa").color == 2, "recolour is free")
	check(p.house_place("living", "sofa", sofa.items[1]) and p.data.coins == 150, "buy the berry sofa for 600")
	check(p.house_slot("living", "sofa").color == 2, "swapping keeps the colour")
	check(p.house_place("living", "sofa", sofa.items[0]) and p.data.coins == 150, "switching back to an owned sofa is free")
	check(not p.house_place("living", "sofa", sofa.items[2]) and p.data.coins == 150 and p.house_slot("living", "sofa").item == "sofa_cream", "cannot buy the castle sofa without coins")
	check(p.house_progress(room) == Vector2i(1, 10), "one of ten slots filled")
	check(p.claim_house_reward(room).is_empty(), "no reward before the room is done")
	p.data.coins = 100000
	for s in room.slots:
		p.house_place("living", s.id, s.items[0])
	var before: int = p.data.coins
	var undo := p.booster_count("undo")
	check(p.house_reward_ready(room), "full room is ready for its reward")
	check(not p.claim_house_reward(room).is_empty() and p.data.coins == before + 500 and p.booster_count("undo") == undo + 1, "reward pays 500 coins and boosters")
	check(p.claim_house_reward(room).is_empty() and p.data.coins == before + 500, "reward pays once")
	p.save()
	var q := Profile.new(economy, "user://test_profile.json")
	q.load_or_create(1_800_000_000)
	check(q.house_slot("living", "sofa").item == "sofa_cream" and q.house_owns("sofa_berry") and q.house_progress(room).x == 10, "house survives save and load")

func _language() -> void:
	var p := fresh()
	check(p.data.settings.lang == "en", "new players start in English")
	var pack: Dictionary = {}
	for it in economy.iap:
		if it.id == "starter":
			pack = it
	Lang.use("en")
	check(Lang.t("设置") == "Settings" and Lang.t("第 %d 关") % 3 == "Level 3", "English texts and formats")
	check(Kit.price_text(pack) == "$1.99", "English prices in dollars")
	Lang.use("zh")
	check(Lang.t("设置") == "设置" and Lang.t("第 %d 关") % 3 == "第 3 关", "Chinese stays Chinese")
	check(Kit.price_text(pack) == "¥3", "Chinese prices in yuan")
	Lang.use("fr")
	check(Lang.code == "en", "unknown language falls back to English")
	for it in economy.iap:
		check(float(it.get("usd", 0)) > 0, "%s has a dollar price" % it.id)
