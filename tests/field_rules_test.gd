extends SceneTree
var checks = 0
var failures: Array = []

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures.append(label); printerr("FAIL: ", label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var started = Time.get_ticks_msec()
	check(FieldRules.IDS.size() == 17, "seventeen field rules")
	check(not FieldRules.normalize({}).field_rules, "field rules default off")
	check(not FieldRules.normalize({"field_rules":"true"}).field_rules, "field toggle rejects wrong JSON type")
	for id in FieldRules.IDS:
		var item = FieldRules.info(id)
		check(item.id == id and not item.description.is_empty(), "player description: " + id)
	_test_configuration()
	_test_sequences()
	_test_wildcards()
	_test_wildcard_random_oracle()
	_test_scores()
	_benchmark_wildcards()
	print("FIELD RULES: %d checks, %d failures, %.2fs" % [checks, failures.size(), (Time.get_ticks_msec()-started)/1000.0])
	quit(0 if failures.is_empty() else 1)

func _test_configuration() -> void:
	var defaults = FieldRules.normalize({})
	check(not defaults.field_rules and defaults.field_selection == "random", "new settings default to disabled with random selection")
	check(FieldRules.selection({"field_rules":true}) == "random", "legacy enabled settings keep per-round random behavior")
	check(FieldRules.summary({}) == "场地：关闭", "disabled summary")
	check(FieldRules.summary({"field_rules":true}) == "场地：每局随机", "legacy random summary")
	for id in FieldRules.IDS:
		var source = {"field_rules":true,"field_selection":id,"jiang":"luan","extra":{"value":1}}
		var normalized = FieldRules.normalize(source)
		check(normalized.field_rules and normalized.field_selection == id, "selected field survives normalization: " + id)
		check(normalized.jiang == "luan" and normalized.extra.value == 1, "normalization preserves independent options: " + id)
		normalized.extra.value = 2
		check(source.extra.value == 1, "normalization does not alias caller nested settings: " + id)
		check(FieldRules.summary(source) == "场地：%s（指定）" % FieldRules.info(id).name, "named selection summary: " + id)
		source.field_rules = false
		check(FieldRules.selection(source) == id and FieldRules.normalize(source).field_selection == id, "disabled toggle retains chosen field: " + id)
		check(FieldRules.summary(source) == "场地：关闭", "disabled selection does not claim the rule is active: " + id)
	for invalid in [null,true,false,0,1,1.5,[],{},"","WILDCARD"," wildcard ","not_a_field"]:
		var malformed = {"field_rules":true,"field_selection":invalid}
		check(FieldRules.selection(malformed) == "random", "invalid selection uses random: " + str(invalid))
		check(FieldRules.normalize(malformed).field_selection == "random", "invalid selection normalization: " + str(invalid))
		check(FieldRules.summary(malformed) == "场地：每局随机", "invalid enabled selection summary: " + str(invalid))
	for invalid in [null,0,1,"true",[],{}]:
		var malformed = {"field_rules":invalid,"field_selection":"wildcard"}
		check(not FieldRules.normalize(malformed).field_rules, "invalid enablement cannot activate a field: " + str(invalid))
		check(FieldRules.summary(malformed) == "场地：关闭", "invalid enablement summary stays closed: " + str(invalid))
	check(FieldRules.selection({"field_selection":"random"}) == "random", "explicit random option remains selectable")

func _test_sequences() -> void:
	for suit in range(3):
		var offset = suit * 9
		check(Rules.chi([offset+7,offset+8],offset,"ouroboros").has([offset,offset+7,offset+8]), "891 wraps each suit")
		check(Rules.chi([offset,offset+1],offset+8,"ouroboros").has([offset,offset+1,offset+8]), "912 wraps each suit")
		check(Rules.chi([offset+1,offset+2],offset+8,"ouroboros").is_empty(), "923 is not consecutive")
		check(Rules.chi([offset+7,offset+8],offset).is_empty(), "ordinary mode does not wrap")
	var wrapped = [0,7,8,9,10,11,18,19,20,24,24,24,13,13]
	check(Rules.winning(wrapped,[],false,"ouroboros") and not Rules.winning(wrapped), "wrapped sequence used by win solver")
	check(Rules.waits(wrapped.slice(0,13),[],false,"ouroboros").has(13), "wrapped sequence used by wait solver")
	for honor_group in [[27,28,29],[27,29,31],[28,30,31],[28,29,30]]:
		check(Rules.chi(honor_group.slice(0,2),honor_group[2],"honor_sequences").has(honor_group), "all supplied honor examples")
	check(Rules.chi([27,32],31,"honor_sequences").is_empty(), "green dragon excluded from honor sequences")
	check(Rules.chi([27,27],31,"honor_sequences").is_empty(), "honor sequence requires three distinct faces")
	var honor_hand = [27,28,29,27,29,31,28,30,31,28,29,30,33,33]
	check(Rules.winning(honor_hand,[],false,"honor_sequences"), "all-honor sequences retain wind-color exemption")
	check(Rules.evaluate(honor_hand,[],{"field_id":"honor_sequences"}).get("pattern","")=="风一色", "all-honor sequences score wind color")
	var two_waits = [0,1,2,9,10,11,18,19,20,3,4,13,13]
	check(Rules.waits(two_waits).size()==2 and Rules.waits(two_waits,[],false,"single_wait").is_empty(), "multi-face waits cannot declare single wait")
	var one_wait = [0,1,2,9,10,11,18,19,20,24,24,24,13]
	check(Rules.waits(one_wait,[],false,"single_wait")==[13], "one face qualifies regardless unseen copies")
	var honor_wait = [0,1,2,9,10,11,18,19,20,13,13,27,27]
	check(Rules.waits(honor_wait,[],false,"no_honors").is_empty(), "removed honors never appear as no-honors wait")
	check(Rules.seven([1,1,1,1,1,1,10,10,10,10,13,13,22,22],[],false,"no_honors")==2, "six duplicate tiles form three pairs with one luxury quartet")
	check(Rules.winning([33,33,33,33,33,33,33,33,27,27,28,28,29,29],[],false,"diamond_finger"),"extended pairs preserve wind-color pair exception")

func _oracle(hand: Array, luan: bool, index: int = 0) -> bool:
	var next = hand.find(31,index)
	if next < 0: return Rules.winning(hand,[],luan)
	for tile in range(34):
		hand[next] = tile
		if _oracle(hand,luan,next+1): hand[next]=31; return true
	hand[next] = 31
	return false

func _score_oracle(hand: Array, luan: bool, index: int = 0, physical: Array = []) -> int:
	if physical.is_empty(): physical = hand.duplicate()
	var next = hand.find(31,index)
	if next < 0:
		var score = Rules.evaluate(hand,[],{"luan":luan})
		if score.is_empty(): return 0
		var as_drawn = Tiles.counts(physical)
		var as_used = Tiles.counts(hand)
		var hua = score.hua
		for tile in range(27,34):
			if as_used[tile] >= 3: hua -= 1
			if as_drawn[tile] >= 3: hua += 1
		return int(score.multiplier * hua * 10)
	var highest = 0
	for tile in range(34):
		hand[next] = tile
		highest = maxi(highest,_score_oracle(hand,luan,next+1,physical))
	hand[next] = 31
	return highest

func _test_wildcards() -> void:
	var samples = [
		[0,1,2,9,10,11,18,19,20,24,24,24,13,31],
		[0,1,2,9,10,11,18,19,20,24,24,31,31,13],
		[0,0,3,3,7,7,12,12,17,17,20,20,31,31],
		[0,8,9,17,18,26,27,28,29,30,32,33,31,31],
		[0,3,6,10,13,16,20,23,26,27,28,29,31,31],
		[0,0,0,2,2,2,4,4,4,6,6,6,31,31],
		[0,0,0,1,2,4,7,10,14,20,24,28,31,31],
		[27,27,27,28,28,28,29,29,29,30,30,30,31,31],
		[0,0,0,0,2,2,2,5,5,5,7,7,31,31]
	]
	for luan in [false,true]:
		for index in range(samples.size()):
			var hand = samples[index].duplicate()
			var expected = _oracle(hand.duplicate(),luan)
			check(Rules.winning(hand,[],luan,"wildcard")==expected, "wildcard substitution oracle %d/%s" % [index,luan])
			var score = Rules.evaluate(hand,[],{"luan":luan,"field_id":"wildcard"})
			check(not score.is_empty() == expected, "wildcard winning/scoring agreement %d/%s" % [index,luan])
			check(score.get("points",0)==_score_oracle(hand.duplicate(),luan),"wildcard maximum score oracle %d/%s" % [index,luan])
	var four = [0,1,2,9,10,11,18,19,20,13,31,31,31,31]
	check(Rules.winning(four,[],false,"wildcard"), "four jokers complete groups and a 258 pair")
	check(not Rules.chi([0,31],2,"wildcard").has([0,1,2]), "joker cannot pretend to be an exposed chi tile")
	var melds = [{"type":"peng","tile":0,"tiles":[0,0,0]}]
	check(Rules.winning([9,10,11,18,19,20,24,24,24,13,31],melds,false,"wildcard"), "wildcard completes exposed hand")
	var pair_only = [{"type":"peng","tile":0,"tiles":[0,0,0]},{"type":"peng","tile":9,"tiles":[9,9,9]},{"type":"peng","tile":18,"tiles":[18,18,18]},{"type":"peng","tile":24,"tiles":[24,24,24]}]
	check(Rules.winning([13,31],pair_only,false,"wildcard"), "two-tile joker pair")
	check(not Rules.winning([12,31],pair_only,false,"wildcard"), "joker honors regional pair restriction")
	var substituted_honor = Rules.evaluate([0,1,2,9,10,11,18,19,20,13,13,33,31,31],[],{"field_id":"wildcard"})
	check(substituted_honor.hua==1, "joker-created honor triplet does not mint physical flower points")
	var actual_reds = Rules.evaluate([0,1,2,9,10,11,18,19,20,13,13,31,31,31],[],{"field_id":"wildcard"})
	check(actual_reds.hua==2 and actual_reds.hua_details.back().name=="字暗刻（中）", "three actual red dragons retain physical honor flower")
	var high = [9,10,11,12,13,14,15,16,10,11,12,31,31,31]
	var high_score = Rules.evaluate(high,[],{"field_id":"wildcard"})
	check(high_score.get("points",0)==640,"one witness combines a pure-suit straight and actual red triplet flowers")
	check(high_score.get("points",0)==_score_oracle(high.duplicate(),false),"three-joker maximum score exhaustive oracle")

func _test_scores() -> void:
	var hand = [0,1,2,9,10,11,18,19,20,24,24,24,13,13]
	var ordinary = Rules.evaluate(hand,[],{"bao":true})
	var enhanced = Rules.evaluate(hand,[],{"bao":true,"field_id":"single_wait","field_bonus":["听单张"]})
	check(enhanced.points==ordinary.points*2 and enhanced.multiplier==ordinary.multiplier*2,"one extra fan doubles scoring")
	check(enhanced.patterns.back().name=="听单张", "field bonus named on result")
	var heavenly = Rules.evaluate(hand,[],{"tianhu":true,"field_bonus":["天选"]})
	check(heavenly.points==600,"field bonus applies to heavenly fixed score")
	var meld = [{"type":"gang","tile":33,"tiles":[33,33,33,33,33]}]
	var extended = Rules.evaluate([0,1,2,9,10,11,18,19,20,13,13],meld,{"field_id":"diamond_finger"})
	check(extended.hua==5, "five white tiles count two kong payments plus base")
	check(extended.hua_details.back().name.contains("×2"), "repeated kong scoring explanation")

func _test_wildcard_random_oracle() -> void:
	var random = RandomNumberGenerator.new(); random.seed = 710513
	for sample in range(90):
		var hand: Array = []
		if sample % 3 != 0:
			for group in range(4):
				if random.randf() < 0.5:
					var tile = random.randi_range(0,30)
					hand.append_array([tile,tile,tile])
				else:
					var first = random.randi_range(0,2)*9+random.randi_range(0,6)
					hand.append_array([first,first+1,first+2])
			var pair = random.randi_range(0,30); hand.append_array([pair,pair])
		else:
			for tile_index in range(14): hand.append(random.randi_range(0,30))
		for joker_index in range(1 if sample % 2 == 0 else 2):
			var index = random.randi_range(0,13)
			while hand[index] == 31: index = random.randi_range(0,13)
			hand[index] = 31
		var luan = sample % 2 == 0
		var expected = _oracle(hand.duplicate(),luan)
		check(Rules.winning(hand,[],luan,"wildcard")==expected, "random wildcard oracle %d: %s" % [sample,hand])
		check(not Rules.evaluate(hand,[],{"luan":luan,"field_id":"wildcard"}).is_empty()==expected,"random joker scoring agrees with winning %d" % sample)
		if sample < 30:
			var points = Rules.evaluate(hand,[],{"luan":luan,"field_id":"wildcard"}).get("points",0)
			check(points==_score_oracle(hand.duplicate(),luan),"random joker max-score oracle %d %s" % [sample,hand])

func _benchmark_wildcards() -> void:
	var hand = [0,1,2,9,10,11,18,19,20,31,31,31,31]
	var start = Time.get_ticks_usec()
	for _iteration in range(20): Rules.waits(hand,[],false,"wildcard")
	print("WILDCARD PERF: four-joker / 34-face waits %.2f ms per query (20 queries)" % ((Time.get_ticks_usec()-start)/20000.0))
