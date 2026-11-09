extends SceneTree
## Profile and economy tests: godot --headless --path . --script res://tests/meta_tests.gd

const Profile = preload("res://scripts/meta/profile.gd")

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
	check(p.grant_purchase("starter", t) and p.booster_count("undo") == 6, "starter pack gives boosters")
	check(not p.iap_available("starter", t), "starter pack only once")
	var q := fresh(t)
	check(not q.iap_available("starter", t + 4 * 86400), "starter pack expires after 3 days")
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
