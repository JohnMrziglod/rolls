package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"

CARD_SIZE :: [2]f32{300, 350}
CardCategory :: enum {NONE, ROLL, DICE, CYCLE}
CardType :: enum i32{
		CardNone,
	CardRoll_Attack,
	CardRoll_Defense,
	CardRoll_Doppelgeist,
	CardRoll_Exorcism,
	CardRoll_FakeNews,
	CardRoll_GraveRoll,
	CardRoll_GhostHour,
	CardRoll_HappyHour,
	CardRoll_Immortality,
	CardRoll_MarketCrash,
	CardRoll_Revenge,
	CardRoll_Suidice,
	CardRoll_TombRaider,
	CardRoll_WhiteElephant,
		CardRolls,				// <- Until here we got roll cards
	CardDice_Antenna,
	CardDice_Assassin,
	CardDice_Drunk,
	CardDice_Engineer,
	CardDice_Journalist,
	CardDice_General,
	CardDice_Influencer,
	CardDice_Investor,
	CardDice_Medium,
	CardDice_Optimist,
	CardDice_Pessimist,
	CardDice_PlusOne,
	CardDice_PowerDice,
	CardDice_Historian,
	CardDice_Librarian,
	CardDice_Pirate,
	CardDice_Researcher,
	CardDice_Tank,
	CardDice_Train,
	CardDice_Veteran,
	CardDice_WarHero,
		CardDices,				// <- Until we got upgrade cards
	CardCycle_ExtraDie,
	CardCycle_EternalRoll,
	CardCycle_Graveyard,
	CardCycle_GhostDiscount,
	CardCycle_Recycle,
	CardCycle_Supermarket,
		CardCycles,				// <- Until we got cycle cards
}
Card :: struct{
	type: CardType,
	category: CardCategory,
	var1: f64,				// One can use these variables as they want...
	var2: f64,
	already_scored: bool,
	active: bool,
	lifetime: i32,		// Number of rolls until discard
	triggered: f32,		// How long it should be displayed as triggered in seconds
}

CardGenerateTypes :: enum{AllCards, RollCards, RollAndDiceCards, DiceCards, CycleCards}
cards_generate :: proc(cards: []Card, types:CardGenerateTypes){
	lower_bound := i32(CardType.CardNone)+1
	upper_bound := i32(CardType.CardCycles)
	switch types {
	case .AllCards:
		// do nothing, we want all cards
	case .DiceCards:
		lower_bound = i32(CardType.CardRolls)+1
		upper_bound = i32(CardType.CardDices)
	case .RollCards:
		upper_bound = i32(CardType.CardRolls)
	case .RollAndDiceCards:
		upper_bound = i32(CardType.CardDices)
	case .CycleCards:
		lower_bound = i32(CardType.CardDices)+1
		upper_bound = i32(CardType.CardCycles)
	}

	generated_types := bit_set[CardType]{}
	for i in 0..<len(cards) {
		card_type: CardType

		for (card_type == .CardNone || card_type == .CardRolls || card_type in generated_types) {
			card_type = CardType(rand.int32_range(lower_bound, upper_bound))
		}

		cards[i] = Card{type=card_type, category=card_category(card_type)}
		generated_types += {card_type}
	}
}

card_fill_vars :: proc(card: Card, text: string) -> string{
	new_text: string

	allocator := context.allocator
	context.allocator = context.temp_allocator
	new_text, _ = strings.replace_all(text, "%VAR1_F", fmt.tprintf("%.1f", card.var1))
	new_text, _ = strings.replace_all(new_text, "%VAR1", fmt.tprintf("%.f", card.var1))
	new_text, _ = strings.replace_all(new_text, "%VAR2_F", fmt.tprintf("%.1f", card.var2))
	new_text, _ = strings.replace_all(new_text, "%VAR2", fmt.tprintf("%.f", card.var2))
	context.allocator = allocator

	return new_text
}

card_category :: proc(type: CardType) -> CardCategory{
	if type > .CardNone && type < .CardRolls do return .ROLL
	if type > .CardRolls && type < .CardDices do return .DICE
	if type > .CardDices && type < .CardCycles do return .CYCLE
	return .NONE // Invalid card type, return default category
}

card_discard :: proc(player: ^Player, index: i32, silent:bool=false){
	if index < 0 || index >= i32(len(player.cards)) do return // Invalid index, do nothing
	ordered_remove(&player.cards, index)

	if silent || player.id != 0 do return
	sound := app.sounds[11]
	rl.SetSoundVolume(sound, 1.)
	rl.PlaySound(sound)
}

card_activate :: proc(player: ^Player, card: ^Card){
	card.active = true
	card.triggered = 1.0
	if card.category == .ROLL{
		card.lifetime = player.max_lifetime_roll_cards
	}

	if player.id == 0 {
		sound := app.sounds[10]
		rl.SetSoundVolume(sound, 1.)
		rl.PlaySound(sound)
	}

	#partial switch card.type {
	case .CardCycle_EternalRoll:
		player.max_lifetime_roll_cards += 1
	case .CardCycle_ExtraDie:
		// player.n_dice += 1
		append(&app.dice, Die{player=player.id, state=.DEAD, color1=player.color, color2=rl.BLACK})
		dice_init(&app.dice[len(app.dice)-1])
	case .CardCycle_Graveyard:
		player.ghosts_max += 1
	case .CardCycle_GhostDiscount:
		player.ghosts_costs_per_combination -= 1
		if player.ghosts_costs_per_combination < 1 do player.ghosts_costs_per_combination=1
	}

	for &dice, d in app.dice{
		if dice.player != player.id || dice.state != .ALIVE do continue

		for &upgrade in dice.upgrades{
			#partial switch upgrade.type {
			case .CardDice_Historian:
				if card.category == .ROLL{
					upgrade.var1 += 1.
					add_text(dice.position, fmt.aprint("HISTORIAN: +1 SCORE!"), dice.color1, 0.5)
				}
			case .CardDice_Librarian:
				if card.category == .DICE{
					upgrade.var1 += 1.
					add_text(dice.position, fmt.aprint("LIBRARIAN: +1 SCORE!"), dice.color1, 0.5)
				}
			case .CardDice_Researcher:
				if card.category == .CYCLE{
					upgrade.var1 += 1.
					add_text(dice.position, fmt.aprint("RESEARCHER: +1 ROLL MULTIPLIER!"), dice.color1, 0.5)
				}
			}
		}
	}
}

card_assign :: proc(die: ^Die, card: Card, index:i32=-1) -> bool{
	could_upgrade := false
	index := index
	if index == -1{
		for &upgrade, i in die.upgrades{
			if upgrade.type == .CardNone {
				index = i32(i)
				break
			}
		}
	}
	if index != -1 {
		add_text(die.position,
			"",// fmt.aprintf("Upgraded with %v!", get_text(upgrade.type, "title")),
			die.color1, 1.5, icon_id=icon_index_from_card(card.type))

		die.upgrades[index] = card
		card_activate(&app.players[die.player], &die.upgrades[index])
		die.upgrades[index].triggered = 0.
		apply_dice_upgrades(0.)	// @FIXME: Is that good?

		return true
	}

	return false
}

card_add_to_hand :: proc(player: ^Player, card: Card) {
	if len(player.cards) >= 10 do return
	append(&player.cards, card)
}

card_in_hand :: proc(player: Player, card_type: CardType, start_index:i32=0, only_active:=false) -> Card{
	for i in start_index..<i32(len(player.cards)) {
		if player.cards[i].type == card_type && (!only_active || player.cards[i].active) do return player.cards[i]
	}
	return Card{} // Return default card if not found
}

CombinationType :: enum u8 {
	None,
	Pair,
	DoublePair,
	RollOfThree,
	RollOfFour,
	RollRoyal,
	FullHouse,
	LowerStraight,
	UpperStraight,
	AllTogether,
	OnlyOnes,
	OnlyTwos,
	OnlyThrees,
	OnlyFours,
	OnlyFives,
	OnlySixes,
}
Combination :: struct {
	type: CombinationType,
	score: i32,
	n_cards: i32,
}
CombinationSet :: bit_set[CombinationType]

possible_combinations :: proc(dice: []i32) -> CombinationSet{
	combinations := CombinationSet{}
	if len(dice) < 5 do return combinations // Invalid number of dice, return empty set

	counter := [6]i32{}
	for number in dice {
		if number < 1 || number > 6 do continue // Invalid dice number, skip
		counter[number-1] += 1
	}

	pair, double_pair, three, four, five := false, false, false, false, false
	for count in counter {
		if count >= 2 {
			if pair do double_pair = true
			pair = true
		}
		if count >= 3 do three = true
		if count >= 4 do four = true
		if count >= 5 do five = true
	}
	full_house := double_pair && three
	lower_straight := counter == [6]i32{1, 1, 1, 1, 1, 0}
	upper_straight := counter == [6]i32{0, 1, 1, 1, 1, 1}

	if pair do combinations += {.Pair}
	if double_pair do combinations += {.DoublePair}
	if three do combinations += {.RollOfThree}
	if four do combinations += {.RollOfFour}
	if five do combinations += {.RollRoyal}
	if full_house do combinations += {.FullHouse}
	if lower_straight do combinations += {.LowerStraight}
	if upper_straight do combinations += {.UpperStraight}

	combinations += {.AllTogether}

	for i in 0..<6 {
		if counter[i] > 0 do combinations += {CombinationType(u8(i) + u8(CombinationType.OnlyOnes))}
	}

	return combinations
}

test_combination :: proc(combination: CombinationType, dices: []i32, highlight: ^[5]bool) -> (match:bool=false, score:f64=0) {
	if combination == .None do return

	counter := [6]i32{}
	for number, i in dices {
		if number < 1 || number > 6 do return // Invalid dice number, return no match
		counter[number-1] += 1
	}

	pair, double_pair, three, four, five := false, false, false, false, false
	for count in counter {
		if count >= 2 {
			if pair do double_pair = true
			pair = true
		}
		if count >= 3 do three = true
		if count >= 4 do four = true
		if count >= 5 do five = true
	}
	full_house := double_pair && three
	lower_straight := counter == [6]i32{1, 1, 1, 1, 1, 0}
	upper_straight := counter == [6]i32{0, 1, 1, 1, 1, 1}

	#partial switch combination {
	case .Pair:
		match = pair
		if !match do return
		score = 15 // fixed score
		n_highlighted := 0 // Highlight only two dices
		#reverse for count, i in counter { // Always take the highest pair
			if count < 2 do continue

			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 1 do return
				}
			}
		}

	case .DoublePair:
		match = double_pair
		if !match do return
		score = 20 // fixed score
		for c, i in counter {
			if c < 2 do continue
			n_highlighted := 0 // Highlight only four dices

			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 1 do break
				}
			}
			if count(highlight[:], true) >= 4 do break
		}

	case .RollOfThree:
		match = three
		if !match do return
		score = 25 // fixed score
		n_highlighted := 0 // Highlight only three dices
		for count, i in counter {
			if count < 3 do continue
			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 2 do return
				}
			}
		}
	case .RollOfFour:
		match = four
		if !match do return
		score = 40 // fixed score
		n_highlighted := 0 // Highlight only four dices
		for count, i in counter {
			if count < 4 do continue
			for number, j in dices {
				if number == i32(i) + 1 {
					highlight[j] = true
					n_highlighted += 1
					if n_highlighted > 3 do return
				}
			}
		}
	case .RollRoyal:
		match = five
		if !match do return
		score = 70 // fixed score
		for number, j in dices {
			highlight[j] = true
		}
	case .FullHouse:
		match = full_house
		if !match do return
		score = 35 // fixed score
		for number, j in dices {
			highlight[j] = true
		}
	case .LowerStraight:
		match = lower_straight
		if !match do return
		score = 50 // fixed score
		for number, j in dices {
			if number >= 1 && number <= 5 {
				highlight[j] = true
			}
		}
	case .UpperStraight:
		match = upper_straight
		if !match do return
		score = 50 // fixed score
		for number, j in dices {
			if number >= 2 && number <= 6 {
				highlight[j] = true
			}
		}
	case .AllTogether:
		match = true
		if !match do return
		score = f64(math.sum(dices[:]))
		for number, j in dices do highlight[j] = true
	case .OnlyOnes, .OnlyTwos, .OnlyThrees, .OnlyFours, .OnlyFives, .OnlySixes:
		target_number := i32(combination) - i32(CombinationType.OnlyOnes) + 1
		match = counter[target_number-1] > 0
		if !match do return
		score = f64(counter[target_number-1] * target_number)
		for number, j in dices {
			if number == target_number do highlight[j] = true
		}
	}


	return
}
