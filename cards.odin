package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:reflect"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

CardCategory :: enum {NONE, FLASH, ROLL, DICE, CYCLE}
CardType :: enum i32{
		CardNone,
	CardFlash_GraveRoll,
		FlashCards,
	CardRoll_Attack,
	CardRoll_Defense,
	CardRoll_Doppelgeist,
	CardRoll_Exorcism,
	CardRoll_FakeNews,
	CardRoll_GhostHour,
	CardRoll_HappyHour,
	CardRoll_Immortality,
	CardRoll_MarketCrash,
	CardRoll_Revenge,
	CardRoll_Suidice,
	CardRoll_TombRaider,
	CardRoll_WhiteElephant,
		RollCards,				// <- Until here we got roll cards
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
	CardDice_PowerUp,
	CardDice_Historian,
	CardDice_Librarian,
	CardDice_Pirate,
	CardDice_Randomizer,
	CardDice_Researcher,
	CardDice_Tank,
	CardDice_Train,
	CardDice_Veteran,
	CardDice_WarHero,
		DiceCards,				// <- Until we got dice cards
	CardDice_BirthdayKid,
	CardDice_Introvert,
	CardDice_SuperHero,
	CardDice_VIP,
		UniqueDiceCards,		// <- Until here we get unique dice cards
	CardCycle_ExtraDie,
	CardCycle_EternalRoll,
	CardCycle_Graveyard,
	CardCycle_GhostDiscount,
	CardCycle_Recycle,
	CardCycle_Supermarket,
		CycleCards,				// <- Until we got cycle cards
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

cards_battle :: proc(dt: real) {
	for &player, p in game.players {
		player.roll.effects = {}
		other_player := &game.players[(p + 1) % N_PLAYERS]

		for &card, c in player.cards {
			if !card.active || card.already_scored do continue

			player.roll.effects[card.type] = {}

			position := L.hand_positions[p] + L.card_size / 2.
			// if len(player.cards) > 5 {
			// 	position.y += L.hand_area_height / f32(len(player.cards)) * f32(c)
			// } else {
			// 	position.y += f32(c) * (30 + L.card_size.y)
			// }
			#partial switch card.type {
			case .CardRoll_Attack:
				for &dice, d in game.dice {
					if dice.state != .ALIVE || dice.player != u8(p) do continue
					dice.attack += 1
					add_text(
						dice.position,
						fmt.aprint("+1 ATTACK"),
						COLOR_CARDS[card.category],
						lifetime = 0.6,
					)
				}
			case .CardRoll_Defense:
				for &dice, d in game.dice {
					if dice.state != .ALIVE || dice.player != u8(p) do continue
					dice.health += 1
					add_text(
						dice.position,
						fmt.aprint("+1 HEALTH"),
						COLOR_CARDS[card.category],
						lifetime = 0.6,
					)
				}
			case .CardRoll_Doppelgeist:
				ghosts := player.ghosts
				for ghost in ghosts {
					if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
					append(&player.ghosts, ghost)
				}
				slice.sort(player.ghosts[:])
			case .CardRoll_GhostHour:
				ghost_score: sco
				for ghost in player.ghosts do ghost_score += sco(ghost)
				player.roll.score += ghost_score
				add_text(
					position,
					fmt.aprintf("+%.f FROM GHOSTS!", ghost_score),
					COLOR_CARDS[card.category],
					lifetime = 1.,
				)
			case .CardRoll_HappyHour:
				player.roll.factor += 1
				add_text(position, fmt.aprint("+1 ROLL FACTOR"), player.color, lifetime = 1.)
			case .CardRoll_MarketCrash:
				for &dice, d in game.dice {
					for &upgrade, u in dice.upgrades {
						position := dice.position - f32(u) * Vector3{0, 2, 0}
						text: string

						#partial switch upgrade.type {
						case .CardDice_Investor:
							upgrade.var1 *= 0.5
							add_text(
								dice.position,
								fmt.aprint("MARKET CRASH: LOSING 50%"),
								COLOR_CARDS[card.category],
							)
						}
					}
				}
			case .CardRoll_Suidice:
				// Find dice with highest number
				suidice_index := -1
				suidice_number: i32 = 0
				for &dice, d in game.dice {
					if dice.state != .ALIVE || dice.player != u8(p) do continue

					if dice.current_number > suidice_number {
						suidice_index = d
						suidice_number = dice.current_number
					}
				}

				if suidice_index != -1 {
					suidice := &game.dice[suidice_index]

					die_death(suidice)
					add_text(suidice.position, fmt.aprint("SUIDICE!"), suidice.color)

					for &dice, d in game.dice {
						if dice.state != .ALIVE || dice.player == u8(p) do continue

						die_death(&dice, suidice)
					}
				}
			case .CardRoll_TombRaider:
				if len(other_player.ghosts) == 0 {
					add_text(
						position,
						fmt.aprint("NO GHOSTS TO STEAL"),
						COLOR_CARDS[card.category],
						lifetime = 1.,
					)
				} else {
					if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
					index_stolen := rand.int32_range(0, i32(len(other_player.ghosts)))
					append(&player.ghosts, other_player.ghosts[index_stolen])
					ordered_remove(&other_player.ghosts, index_stolen)
					add_text(
						position,
						fmt.aprint("STEALING GHOSTS!"),
						COLOR_CARDS[card.category],
						lifetime = 1.,
					)
				}
				// Sort the ghost dices (makes other things easier later on also for the human player)
				slice.sort(player.ghosts[:])
			case:
				continue
			}

			player.roll.score_counter += 1

			pitch: f32 = 1.0 + ((p == 0) ? 0.1 : -0.1) * f32(player.roll.score_counter)
			play_sound(6, volume = 0.5, pitch = pitch)

			card.triggered = 1.0
			card.already_scored = true
			return
		}
	}

	state_change(.DICES_BATTLE, 0.3)
}

cards_scoring :: proc(dt: real) {
	state_change(.SCORING_SUMMARY, wait = 0.4)
}

CardGenerateTypes :: enum{AllCards, FlashCards, RollCards, FlashRollAndDiceCards, DiceCards, UniqueDiceCards, CycleCards}
cards_generate :: proc(cards: []Card, types:CardGenerateTypes){
	lower_bound := i32(CardType.CardNone)+1
	upper_bound := i32(CardType.CycleCards)
	switch types {
	case .AllCards:
		// do nothing, we want all cards
	case .FlashCards:
		upper_bound = i32(CardType.FlashCards)
	case .RollCards:
		lower_bound = i32(CardType.FlashCards)+1
		upper_bound = i32(CardType.RollCards)
	case .DiceCards:
		lower_bound = i32(CardType.FlashCards)+1
		upper_bound = i32(CardType.DiceCards)
	case .FlashRollAndDiceCards:
		upper_bound = i32(CardType.DiceCards)
	case .UniqueDiceCards:
		lower_bound = i32(CardType.DiceCards)+1
		upper_bound = i32(CardType.UniqueDiceCards)
	case .CycleCards:
		lower_bound = i32(CardType.UniqueDiceCards)+1
	}

	generated_types := bit_set[CardType]{.CardNone, .RollCards, .FlashCards, .DiceCards, .UniqueDiceCards}
	for i in 0..<len(cards) {
		card_type: CardType
		for (card_type in generated_types) {
			card_type = CardType(rand.int32_range(lower_bound, upper_bound))
		}

		cards[i] = card_make(card_type)
		generated_types += {card_type}
	}
}

card_make :: proc(card_type: CardType) -> Card{
	return Card{type=card_type, category=card_category(card_type), var1=card_type==.CardDice_PowerUp ? 1. : 0.}
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
	if type > .CardNone && type < .FlashCards do return .FLASH
	if type > .FlashCards && type < .RollCards do return .ROLL
	if type > .RollCards && type < .UniqueDiceCards do return .DICE
	if type > .UniqueDiceCards && type < .CycleCards do return .CYCLE
	return .NONE // Invalid card type, return default category
}

card_is_unique :: proc(type: CardType) -> bool{
	return type > .DiceCards && type < .UniqueDiceCards
}

card_is_hovered :: proc(position: rl.Vector2, ) -> bool{
	return rl.CheckCollisionPointRec(rl.GetMousePosition(), {x=position.x, y=position.y, width=f32(L.card_size.x), height=f32(L.card_size.y)})
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
	if card.category == .ROLL && player.max_lifetime_roll_cards > card.lifetime{
		card.lifetime = player.max_lifetime_roll_cards
	}

	if player.id == 0 {
		sound := app.sounds[10]
		rl.SetSoundVolume(sound, 1.)
		rl.PlaySound(sound)
	}

	#partial switch card.type {
	case .CardFlash_GraveRoll:
		if len(player.ghosts) > 0{
			for &ghost in player.ghosts{
				ghost = rand.int32_range(1, 7)
			}
			slice.sort(player.ghosts[:])
			add_text_fixed(L.ghost_positions[player.id], fmt.aprint("REROLLED GHOSTS!"), player.color, anchor=.LEFT)
		} else {
			add_text_fixed(L.ghost_positions[player.id], fmt.aprint("NO GHOSTS TO REROLL!"), player.color, anchor=.LEFT)
		}
	case .CardCycle_EternalRoll:
		player.max_lifetime_roll_cards += 1
	case .CardCycle_ExtraDie:
		// player.n_dice += 1
		append(&game.dice, Die{player=player.id, state=.DEAD, color=player.color})
		dice_init(&game.dice[len(game.dice)-1])
	case .CardCycle_Graveyard:
		player.ghosts_max += 1
	case .CardCycle_GhostDiscount:
		player.ghosts_costs_per_combination -= 1
		if player.ghosts_costs_per_combination < 1 do player.ghosts_costs_per_combination=1
	}

	for &dice, d in game.dice{
		if dice.player != player.id || dice.state != .ALIVE do continue

		for &upgrade in dice.upgrades{
			#partial switch upgrade.type {
			case .CardDice_Historian:
				if card.category == .ROLL{
					upgrade.var1 += 1.
					add_text(dice.position, fmt.aprint("HISTORIAN: +1 SCORE!"), dice.color, 0.5)
				}
			case .CardDice_Librarian:
				if card.category == .DICE{
					upgrade.var1 += 1.
					add_text(dice.position, fmt.aprint("LIBRARIAN: +1 SCORE!"), dice.color, 0.5)
				}
			case .CardDice_Researcher:
				if card.category == .CYCLE{
					upgrade.var1 += 1.
					add_text(dice.position, fmt.aprint("RESEARCHER: +1 ROLL FACTOR!"), dice.color, 0.5)
				}
			}
		}
	}

	texture_ids := []Vector2{
		{0, 8}, {0, 9}, {0, 10}, {0, 11}, {0, 12}, {0, 13},
	}
	// add_icon_particles(
	// 	rl.GetMousePosition()-L.card_size/2., L.card_size, texture_ids, COLOR_CARDS[card.category])
}

card_assign :: proc(die: ^Die, card: Card, index:i32=-1) -> bool{
	for &upgrade, i in die.upgrades{
		if upgrade.type == card.type{
			add_text(die.position, fmt.aprint("Die has been upgraded with this card already!"), die.color)
			return false // Die cannot have duplicated upgrades
		}
	}

	could_upgrade := false
	index := index
	// Look for a good spot...
	if index == -1{
		for &upgrade, i in die.upgrades{
			if upgrade.type == .CardNone {
				index = i32(i)
				break
			}
		}
	}
	if index == -1 {
		add_text(die.position, fmt.aprint("Die has no free upgrade slots!"), die.color)
		return false
	}

	add_text(die.position,
		"",// fmt.aprintf("Upgraded with %v!", get_text(upgrade.type, "title")),
		die.color, 1.5, icon_id=icon_index_from_card(card.type))

	die.upgrades[index] = card
	card_activate(&game.players[die.player], &die.upgrades[index])
	die.upgrades[index].triggered = 0.
	apply_dice_upgrades(0.)	// @FIXME: Is that good?

	return true
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

test_combination :: proc(combination: CombinationType, dices: []i32, highlight: ^[5]bool) -> (match:bool=false, score:f64=0, factor:f64=0.) {
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
		factor = 2
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
