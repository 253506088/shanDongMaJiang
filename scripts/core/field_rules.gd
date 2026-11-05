class_name FieldRules
extends RefCounted
## Optional round modifiers. Regional rules remain the base ruleset.

const IDS = ["ouroboros", "diamond_finger", "honor_sequences", "rebirth", "transparent", "tolerance", "reclaim", "wildcard", "astrology_wall", "astrology_waits", "angels_gift", "no_honors", "single_wait", "exchange", "chosen", "chosen_head"]
const CATALOG = {
	"ouroboros": ["衔尾蛇", "数牌首尾相接，顺子可以跨过九与一。", "万、筒、条各自按一至九首尾循环。除普通顺子外，八九一、九一二也可组成顺子，用于吃牌与胡牌。不同花色不能混搭；关闭吃牌时仍不能吃。", false],
	"diamond_finger": ["大力金刚指", "将一张手牌变为白板，每人每局一次。", "在自己的出牌回合，选择一张手牌变为白板；其他玩家看不到被替换的牌。每人每局限用一次，报听或明搂后不能使用。已有白板杠时，再获得白板仍可续杠并再取一次杠头补牌；听牌后的续杠仍须保持原听口。", true],
	"honor_sequences": ["东南西北中", "东、南、西、北、中，三种不同牌也成顺子。", "东、南、西、北、红中这五种牌中，任意三种不同牌可组成顺子，用于吃牌与胡牌。例如东南西、东中西、北中南。发财和白板不参与；关闭吃牌时仍不能吃。", false],
	"rebirth": ["新生", "撤销一次听牌声明，亮出手牌后重新谋划。", "每人每局可在自己的回合撤销一次报听或明搂。撤销后手牌持续公开，可重新整理牌型；再次听牌时只能明搂，只能自摸，胡牌按明搂计算。", true],
	"transparent": ["瓦西子麻将", "每种牌一张暗牌、三张明牌，手牌信息更透明。", "每种普通牌的四张实体牌中，随机一张保持暗牌，其余三张进入玩家手牌后公开可见。牌山和杠头都盖住，开杠仍照常从杠头位置补牌。暗明属性跟随实体牌；花牌照常补花并公开。", false],
	"tolerance": ["宽容", "碰过的牌，也能用别人打出的第四张补杠。", "已经碰出的一组牌，可以接其他玩家打出的同种牌补成明杠，并照常取杠头补牌。其他玩家的胡牌响应优先；报听后仍须保持原听口。", false],
	"reclaim": ["上架", "将一组吃牌或碰牌收回手中，每人每局一次。", "每人每局可在自己的出牌回合，将一组已经吃出或碰出的副露完整收回手牌，再重新组牌。收回的牌曾经公开，不会让其他玩家忘记；杠牌和花牌不参与。报听后不能使用。", true],
	"wildcard": ["癞子", "红中可在胡牌组合中代替任意普通牌。", "手中的红中是癞子，判断胡牌和听牌时可代替任意一种万、筒、条或字牌，也可以当红中使用。二五八将等基础条件仍按替代后的牌型判断。吃、碰、杠必须使用实际同种牌，不能用癞子冒充。", false],
	"astrology_wall": ["占星Ⅰ", "私下查看牌山接下来四张牌，每人每局一次。", "每人每局可在自己的出牌回合查看一次牌山前端接下来的四张牌；不足四张时显示剩余可查看的牌。只有自己知道结果。这是查看时刻的顺序，后续摸牌、补花或其他能力可能改变实际取得的牌。", true],
	"astrology_waits": ["占星Ⅱ", "查看一位听牌玩家的听口，向其点炮额外加一番。", "每人每局可在自己的出牌回合，选择一位已经听牌的其他玩家，私下查看对方当时的全部听口。若你随后向这位玩家点炮，该次胡牌额外加一番。只有使用者知道查询结果。", true],
	"angels_gift": ["天使的施舍", "正常摸牌后，可追加两张再三选一，每人每局一次。", "每次先正常摸一张；在这次出牌前，可主动追加两张，与本次新摸牌三选一。未选的两张按候选原顺序放回牌山前端，只有自己看得到候选和选择。每人每局限用一次，不使用时照常出牌。报听、明搂后禁用；开局、吃碰后及杠后补牌不适用，普通摸花后补到的牌仍可作为首张候选。选牌时可查看完整手牌和副露。发动即消耗次数，不能取消；可先收起选牌界面，随后继续选择。", true],
	"no_honors": ["无字天书", "移除全部字牌，补入二十八张随机数牌。", "本局移除东、南、西、北、中、发、白共二十八张字牌，随机补入二十八张万、筒、条；花色和数字独立随机，允许重复。花牌保留，牌总数不变。同种牌可能超过四张；已有杠再获得同种牌时可续杠并再取一次杠头补牌。", false],
	"single_wait": ["听单张", "只准听一种牌，胡牌额外加一番。", "只有听口恰好为一种牌时，才可报听或明搂；听两种及以上牌时不能声明听牌。“一种”指牌面种类，不是剩余张数，也不限定为单钓将。本局符合规则的胡牌额外加一番。", false],
	"exchange": ["换牌", "开局每人选三张牌，交给自己的下家。", "开局补花后、首次出牌前，每人从手牌中选三张交给下家，并同时接收上家交来的三张。必须优先选择万、筒、条；仅当数牌不足三张时，才可用字牌补足。各家完成选择后统一交换，不能先看收牌再选送牌。", true],
	"chosen": ["天选", "公开三种天选数牌，以其中任意一种胡牌加一番。", "开局随机选出三种不同的万、筒、条牌面，向所有玩家公开。本局胡牌所用的最后一张牌命中任意天选牌时，额外加一番；即使同时命中多种也只加一次。天胡没有最后来牌，只要起手胡牌中含任意天选牌便可触发。", false],
	"chosen_head": ["天选Ⅱ", "胡牌牌面命中公开杠头，额外加一番。", "胡牌的最后一张牌，与胡牌前公开杠头的牌面相同时，额外加一番；普通自摸和点炮也可触发。杠后自摸以本次取出前的杠头为准。天胡只要起手胡牌中包含开局杠头牌面即可触发。", false]
}

static func info(id: String) -> Dictionary:
	if not CATALOG.has(id):
		return {"id": "", "name": "正常模式", "summary": "不使用场地规则，按所选地方麻将玩法进行。", "description": "场地规则是独立增强选项。关闭后，仅应用所选地方玩法与吃牌等常规选项。", "active": false}
	var row = CATALOG[id]
	return {"id": id, "name": row[0], "summary": row[1], "description": row[2], "active": row[3]}

static func all() -> Array:
	return IDS.map(func(id): return info(id))

static func normalize(settings: Dictionary) -> Dictionary:
	var result = settings.duplicate(true)
	result.field_rules = settings.get("field_rules", false) is bool and settings.get("field_rules", false)
	result.field_selection = selection(settings)
	return result

static func selection(settings: Dictionary) -> String:
	# Selection and enablement are separate: switching the modifier off keeps
	# the chosen rule ready for the next time it is enabled. Old saves lack it.
	var chosen = settings.get("field_selection", "random")
	return chosen if chosen is String and (chosen == "random" or chosen in IDS) else "random"

static func summary(settings: Dictionary) -> String:
	if not (settings.get("field_rules", false) is bool and settings.get("field_rules", false)): return "场地：关闭"
	var chosen = selection(settings)
	return "场地：每局随机" if chosen == "random" else "场地：%s（指定）" % info(chosen).name

static func sequences(field_id: String = "") -> Array:
	var result: Array = []
	for suit in range(3):
		for start in range(7): result.append([suit * 9 + start, suit * 9 + start + 1, suit * 9 + start + 2])
		if field_id == "ouroboros":
			result.append([suit * 9, suit * 9 + 7, suit * 9 + 8])
			result.append([suit * 9, suit * 9 + 1, suit * 9 + 8])
	if field_id == "honor_sequences":
		for first in range(27, 30):
			for second in range(first + 1, 31):
				for third in range(second + 1, 32): result.append([first, second, third])
	return result

static func bonus(result: Dictionary, names: Array) -> Dictionary:
	if result.is_empty() or names.is_empty(): return result
	for label in names:
		result.multiplier *= 2
		result.points *= 2
		result.patterns.append({"name": str(label), "multiplier": 2})
	result.field_bonus = names.duplicate()
	return result

static func _tiles(counts: Array) -> Array:
	var hand: Array = []
	for tile in range(34):
		for _copy in range(counts[tile]): hand.append(tile)
	return hand

static func _active(melds: Array) -> Array:
	return melds.filter(func(m): return m.type != "flower")

static func _all_tiles(hand: Array, melds: Array) -> Array:
	var tiles = hand.duplicate()
	for meld in _active(melds): tiles.append_array(meld.tiles)
	return tiles

static func _wild_groups(counts: Array, wild: int, needed: int, runs: bool, allowed: Array, memo: Dictionary) -> Array:
	if wild < 0 or needed < 0: return [-1]
	var first = -1
	for tile in range(34):
		if counts[tile] > 0: first = tile; break
	if first < 0:
		if wild != needed * 3: return [-1]
		var tail: Array = []
		for _group in range(needed): tail.append_array([allowed[0], allowed[0], allowed[0]])
		return tail
	if needed == 0: return [-1]
	var key = str(counts) + ":" + str(wild) + ":" + str(needed)
	if memo.has(key): return memo[key]
	# Try every possible use of natural copies; a wildcard may preserve a real
	# copy needed by another group, even when three copies are already present.
	for natural in range(mini(3, counts[first]), 0, -1):
		if 3 - natural > wild: continue
		counts[first] -= natural
		var rest = _wild_groups(counts, wild - (3 - natural), needed - 1, runs, allowed, memo)
		counts[first] += natural
		if rest.size() == (needed - 1) * 3:
			memo[key] = [first, first, first] + rest
			return memo[key]
	if runs and first < 27:
		for sequence in sequences():
			if first not in sequence or not sequence.all(func(t): return t in allowed): continue
			# The chosen first natural tile must participate; each other tile can
			# use its natural copy or a joker. At most four combinations per run.
			var others = sequence.duplicate(); others.erase(first)
			for mask in range(4):
				var used = [first]
				var spent = 0
				for index in range(2):
					if mask & (1 << index): spent += 1
					else: used.append(others[index])
				if spent > wild or used.any(func(t): return counts[t] < 1): continue
				for tile in used: counts[tile] -= 1
				var rest = _wild_groups(counts, wild - spent, needed - 1, runs, allowed, memo)
				for tile in used: counts[tile] += 1
				if rest.size() == (needed - 1) * 3:
					memo[key] = sequence + rest
					return memo[key]
	memo[key] = [-1]
	return [-1]

static func _wild_complete(hand: Array, melds: Array, luan: bool, allowed: Array, runs: bool = true) -> Array:
	var needed = 4 - _active(melds).size()
	if hand.size() != needed * 3 + 2 or needed < 0: return []
	for meld in _active(melds):
		if not runs and meld.type == "chi": return []
		if meld.tiles.any(func(t): return t not in allowed): return []
	var counts = Tiles.counts(hand)
	var wild = counts[31]; counts[31] = 0
	for tile in range(42):
		if counts[tile] > 0 and tile not in allowed: return []
	var memo = {}
	for tile in allowed:
		if not luan and not Tiles.eye(tile): continue
		for natural in range(mini(2, counts[tile]), -1, -1):
			if 2 - natural > wild: continue
			counts[tile] -= natural
			var groups = _wild_groups(counts, wild - (2 - natural), needed, runs, allowed, memo)
			counts[tile] += natural
			if groups.size() == needed * 3: return [tile, tile] + groups
	return []

static func _wild_seven(hand: Array, melds: Array, luan: bool, allowed: Array) -> Array:
	if hand.size() != 14 or not _active(melds).is_empty(): return []
	var counts = Tiles.counts(hand)
	var wild = counts[31]; counts[31] = 0
	for tile in range(42):
		if counts[tile] > 0 and tile not in allowed: return []
		if counts[tile] % 2 != 0: counts[tile] += 1; wild -= 1
	if wild < 0: return []
	if not luan and not allowed.any(func(t): return Tiles.eye(t) and counts[t] > 0):
		var eyes = allowed.filter(func(t): return Tiles.eye(t))
		if eyes.is_empty() or wild < 2: return []
		counts[eyes[0]] += 2; wild -= 2
	# Complete as many four-of-a-kinds as possible, selecting a best-scoring
	# seven-pairs interpretation without enumerating every joker assignment.
	for tile in allowed:
		if wild >= 2 and counts[tile] == 2: counts[tile] += 2; wild -= 2
	for tile in allowed:
		while wild >= 2 and counts[tile] < 4: counts[tile] += 2; wild -= 2
	return _tiles(counts) if wild == 0 else []

static func _wild_orphans(hand: Array, melds: Array) -> Array:
	if hand.size() != 14 or not _active(melds).is_empty(): return []
	var counts = Tiles.counts(hand)
	var wild = counts[31]; counts[31] = 0
	var pairs = 0
	for tile in range(42):
		if counts[tile] > 0 and tile not in Tiles.ORPHANS: return []
		if counts[tile] > 2: return []
		if counts[tile] == 2: pairs += 1
	if pairs > 1: return []
	for tile in Tiles.ORPHANS:
		if counts[tile] == 0: counts[tile] = 1; wild -= 1
	if pairs == 0: counts[Tiles.ORPHANS[0]] += 1; wild -= 1
	return _tiles(counts) if wild == 0 else []

static func _wild_bukao(hand: Array, melds: Array) -> Array:
	if hand.size() != 14 or not _active(melds).is_empty(): return []
	for pattern in [[0,1,2], [0,2,1], [1,0,2], [1,2,0], [2,0,1], [2,1,0]]:
		var allowed: Array = range(27, 34)
		for suit in range(3):
			for rank in range(pattern[suit], 9, 3): allowed.append(suit * 9 + rank)
		var counts = Tiles.counts(hand)
		var wild = counts[31]; counts[31] = 0
		var valid = true
		for tile in range(42):
			if counts[tile] > 1 or (counts[tile] > 0 and tile not in allowed): valid = false; break
		if not valid: continue
		for tile in allowed:
			if wild > 0 and counts[tile] == 0: counts[tile] = 1; wild -= 1
		if wild == 0: return _tiles(counts)
	return []

static func wildcard_winning(hand: Array, melds: Array, luan: bool) -> bool:
	if melds.size() - _active(melds).size() >= 8: return true
	if not _wild_orphans(hand, melds).is_empty() or not _wild_bukao(hand, melds).is_empty(): return true
	if not _wild_seven(hand, melds, luan, range(34)).is_empty(): return true
	if not _wild_complete(hand, melds, luan, range(34)).is_empty(): return true
	# The regional baseline permits wind/258 color hands with an unrestricted
	# pair even when the selected ordinary pair rule is 258.
	if _all_tiles(hand,melds).size() != 14: return false
	for allowed in [range(27,34), range(27).filter(func(t): return Tiles.eye(t))]:
		if not _wild_complete(hand, melds, true, allowed, false).is_empty(): return true
		if not _wild_seven(hand, melds, true, allowed).is_empty(): return true
	return false

static func wildcard_candidates(hand: Array, melds: Array, luan: bool) -> Array:
	var result: Array = []
	var sets: Array = [range(34), range(27,34), range(27).filter(func(t): return Tiles.eye(t))]
	for suit in range(3):
		sets.append(range(suit * 9, suit * 9 + 9))
		sets.append(range(suit * 9, suit * 9 + 9) + range(27,34))
	for index in range(sets.size()):
		var allowed = sets[index]
		var any_pair = luan or (index in [1,2] and _all_tiles(hand,melds).size() == 14)
		for candidate in [_wild_complete(hand,melds,any_pair,allowed), _wild_complete(hand,melds,any_pair,allowed,false), _wild_seven(hand,melds,any_pair,allowed)]:
			if not candidate.is_empty() and candidate not in result: result.append(candidate)
	for candidate in [_wild_orphans(hand,melds), _wild_bukao(hand,melds)]:
		if not candidate.is_empty() and candidate not in result: result.append(candidate)
	# Reserve jokers for ranks absent from a possible straight before finding
	# the remaining groups. A witness prevents incompatible pattern stacking.
	var total = Tiles.counts(_all_tiles(hand, melds))
	for suit in range(3):
		var trial = hand.duplicate()
		for rank in range(9):
			var tile = suit * 9 + rank
			if total[tile] == 0:
				if 31 not in trial: trial = []; break
				trial.erase(31); trial.append(tile)
		if trial.is_empty(): continue
		for allowed in [range(34), range(suit * 9, suit * 9 + 9), range(suit * 9, suit * 9 + 9) + range(27,34)]:
			var candidate = _wild_complete(trial, melds, luan, allowed)
			if not candidate.is_empty() and candidate not in result: result.append(candidate)
	return result
