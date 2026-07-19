package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:reflect"
import "core:slice"
import rl "vendor:raylib"

ENUMERATIONS := []string{
	"1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th", "10th",
	"11th", "12th", "13th", "14th", "15th", "16th", "17th", "18th", "19th", "20th",
	"21st", "22nd", "23rd", "24th", "25th", "26th", "27th", "28th", "29th", "30th",
	"31st", "32nd", "33rd", "34th", "35th", "36th", "37th", "38th", "39th", "40th",
}

AntagonistID :: enum{
	Antagonist_TheNoob,				// Special since it is the first
	// Aggressor,
	// Calm,
	// CEO,
	// Chaos,
	Antagonist_TheDictator,
	// TheEntertainer
	Antagonist_TheMathematician,
	// Mirror,
	// Mogul,
	// Outlaw,
	// Party,
	// Scientist,
	// Spiritual,
	// Tycoon,
}
AntagonistSetup :: struct {
	cards: []CardType,
	n_dice: i32,
}
antagonist_setups := [AntagonistID]AntagonistSetup{
	.Antagonist_TheNoob={
		cards={},
		n_dice=5,
	},
	.Antagonist_TheDictator={
		cards={.CardRoll_FakeNews, .CardDice_Tank, .CardDice_General, .CardDice_Tank, .CardDice_General},
		n_dice=5,
	},
	.Antagonist_TheMathematician={
		cards={.CardDice_PowerUp, .CardDice_PlusOne, .CardDice_PowerUp, .CardDice_PlusOne, .CardDice_PowerUp, .CardDice_PlusOne},
		n_dice=5,
	},
}


TutorialID :: enum{None, Begin1, Begin2, GhostDice, GhostBoard, Cards, Cycles, Introduction}

Antagonist :: struct {
	id:				AntagonistID,
	count:			i32,
	name:			string,
	past_ids:		bit_set[AntagonistID],
	level:			u32,					// move to the next level as soon as all antagonists have been met.
	story_id:    	string,
	story_index:    i32,
	blocking:		bool,
	wanted_power:	f32,
	win_score:  	sco,
	tutorials:		bit_set[TutorialID],
	tutorial_id: 	TutorialID, // Current Tutorial ID
}

antagonist_next :: proc(){
	possible_antagonists: [dynamic]AntagonistID
	for antagonist_id in AntagonistID {
		if antagonist_id in game.antagonist.past_ids do continue
		append(&possible_antagonists, antagonist_id)
	}

	if len(possible_antagonists) == 0 {
		fmt.println("No more antagonists available!")
		return
	}

	rand.shuffle(possible_antagonists[:])

	antagonist_set(possible_antagonists[0])
}

antagonist_set :: proc(id: AntagonistID) {
	game.antagonist.id = id
	game.antagonist.past_ids += {id}
	game.antagonist.name = get_text(reflect.enum_string(game.antagonist.id), "name")
	game.antagonist.count += 1

	// setup the antagonist's cards and dice
	setup := antagonist_setups[id]
	player_init(1, setup.n_dice)

	clear(&game.players[1].cards)
	for card_type in setup.cards {
		card := card_make(card_type)
		card.lifetime = 999			// Roll cards should have a very long lifetime!
		append(&game.players[1].cards, card)
	}

	antagonist_use_cards(even_on_dead_dice=true)

	state_change(.ANTAGONIST_INTRODUCTION)
}

show_antagonist_details :: proc() {
	fade_out()
	delay :: f32(.5)

	ai := &game.players[1]
	color := ai.color

	font_size := L.font_size1+20*S
	board_size := min(L.width, L.height)-200*S
	board_position := rl.Vector2{(L.width - board_size) / 2., 50*S}
	padding := font_size

	draw_box(board_position, {}+board_size, fill=rl.BLACK)

	message := game.antagonist.name
	char_duration :f32= 0.16
	spelling_time := char_duration * f32(len(message))
	spelling_done := game.state_clock-delay>spelling_time

	n_visible_chars := min(int(game.state_clock/char_duration), len(message))
	draw_text(message[:n_visible_chars], board_position+padding, font_size, color, underline=spelling_done)

	if !spelling_done do return
	subline_font_size := L.font_size2// * splash_shrink(subline_clock/0.5, 1.)
	subline := fmt.tprintf("%v  ANTAGONIST", ENUMERATIONS[game.antagonist.count-1])
	draw_text(subline, board_position+padding+{0, font_size+10*S}, subline_font_size, color)

	subline_clock := game.state_clock-spelling_time-delay-0.8
	if subline_clock < 0. do return
	icon_size := splash_shrink(subline_clock, 1.) * board_size/2. * 1.3
	icon_position := board_position + board_size/2. - {0, SCALE(100)}
	draw_antagonist(game.antagonist.id, icon_position, icon_size, color)

	if subline_clock-2.0 < 0. do return

	font_size = L.font_size1
	position := board_position + {padding, icon_position.y+icon_size/2.+padding}
	// abilities := "[iCardRoll_HappyHour] + 6x [iDieFace6] with [iCardDice_Optimist], [iCardDice_PlusOne]"
	abilities := "tbd"//antagonist_setups[game.antagonist.id]
	description := fmt.tprintf("[h]ABILITIES:[h] %v[n][h]SCORE TO WIN:[h] %v", abilities, game.antagonist.win_score)
	draw_text(description, position, font_size, color)

	if game.state == .VICTORY{
		draw_text("YOU WON!", board_position+board_size/2, L.font_size1+SCALE(10), rl.BLACK, anchor=.CENTER, boxed=COLOR_PLAYERS[0])
	} else if game.state == .DEFEAT{
		draw_text("YOU LOST!", board_position+board_size/2, L.font_size1+SCALE(10), rl.BLACK, anchor=.CENTER, boxed=rl.RED)
	}

	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) || continue_button() do state_change(.WAIT_FOR_PLAYER)
}

show_antagonist_story :: proc(){
	if len(game.antagonist.story_id) == 0 do return

	// Let's the bubble get bigger and smaller to make it more dynamic, and also changes the color a bit
	time_factor := f32(1.)
	if game.antagonist.blocking do time_factor += 0.05 * math.sin(f32(rl.GetTime()) * 5)

	font_size := L.font_size1 * time_factor
	sub_font_size := (font_size-1)/2.
	thickness: f32 = 4.
	max_width: f32 = 600*S * time_factor
	padding: f32 = 20.*S
	color_fill := rl.BLACK
	color_text := game.players[1].color
	message := get_text(game.antagonist.story_id, game.antagonist.story_index)
	size := measure_text(message, font_size, max_width = max_width) + padding
	extra_space := measure_text("Press <SPACE> to continue", sub_font_size) + padding

	size = {max(size.x, extra_space.x), size.y+extra_space.y}

	position := Vector2{L.width - 40*S, L.height - 200*S} - size - padding

	// SPECIAL TREATMENT if we have end of level screen or antagonist introduction
	if game.state == .VICTORY || game.state == .DEFEAT{
		position = {3*L.width/4, L.height/2} - size - padding
	}


	rl.DrawRectangleV(position, size, color_fill)
	rl.DrawRectangleLinesEx(
		{
			position.x - thickness,
			position.y - thickness,
			size.x + 2 * thickness,
			size.y + 2 * thickness,
		},
		thickness,
		rl.BLACK,
	)
	draw_text(message, position + padding / 2., font_size, color_text, max_width=max_width)
	draw_text("Press <SPACE> to continue", position + {padding / 2.,size.y-extra_space.y}, sub_font_size, color_text)

	hovered := rl.CheckCollisionPointRec(
		rl.GetMousePosition(),
		{x = position.x, y = position.y, width = size.x, height = size.y},
	)
	clicked := hovered && rl.IsMouseButtonPressed(.LEFT)
	if clicked {
		antagonist_story_continue()
	}

	// button_pos := position + size
	// if button(fmt.tprint("<SPACE>"), button_pos, font_size=L.font_size2, anchor=.RIGHT, text_color=color_text, hover_motion=false) {
	// 	antagonist_story_continue()
	// }
}

tutorial :: proc(id: TutorialID) -> bool{
	if len(game.antagonist.story_id) != 0 do return false
	if app.tutorials_off || id in game.antagonist.tutorials do return false

	game.antagonist.tutorials += {id}
	game.antagonist.tutorial_id = id

	// Tutorials are always blocking
	antagonist_story(fmt.aprintf("Tutorial_%s", reflect.enum_string(id)), blocking=true)

	return true
}
antagonist_is_speaking :: proc() -> bool{
	return len(game.antagonist.story_id) != 0
}
antagonist_story :: proc(story_id: string, index: i32=1, blocking:bool=false) {
	game.antagonist.story_id = story_id
	game.antagonist.story_index = index
	game.antagonist.blocking = blocking
}
antagonist_story_continue :: proc() {
	if len(game.antagonist.story_id) == 0 do return

	game.antagonist.story_index += 1
	text_id := fmt.tprintf("%s/%d", game.antagonist.story_id, game.antagonist.story_index)
	if text_id in app.texts {
		antagonist_story(game.antagonist.story_id, game.antagonist.story_index)
	} else {
		antagonist_story_cancel()
		if game.antagonist.tutorial_id == .Introduction {
			state_change(.ANTAGONIST_INTRODUCTION)
		}
		game.antagonist.tutorial_id = .None
	}
}
antagonist_story_cancel :: proc(){
	delete(game.antagonist.story_id)
	game.antagonist.story_id = ""
	game.antagonist.story_index = 0
	game.antagonist.blocking = false
}

wait_for_ai :: proc() {
	// Some actions that the AI could do...
	ai := &game.players[1]

	if len(ai.ghosts) >= 5 {
		// @TODO: how do we find the best selection of dice?
		counter := [6]i32{} // dice number -> count
		for ghost_number, i in ai.ghosts {
			counter[ghost_number - 1] += 1
		}
		lower_straight := slice.min(counter[:5]) > 0
		upper_straight := slice.min(counter[1:]) > 0
		has_pairs := slice.max(counter[:]) > 1

		best_indices := [dynamic]i32{}
		defer delete(best_indices)

		if lower_straight || upper_straight {
			// If we have a straight, we want to keep all the numbers that are part
			// of the straight and get rid of the others
			last_number: i32 = 0
			for ghost_number, i in ai.ghosts {
				if ghost_number > last_number {
					append(&best_indices, i32(i))
					last_number = ghost_number
				}
			}
		} else if has_pairs {
			// If we have pairs, we want to keep all the numbers that are part of a pair
			#reverse for ghost_number, i in ai.ghosts {
				if counter[ghost_number - 1] > 1 && len(best_indices) < 5 {
					append(&best_indices, i32(i))
				}
			}

			// Fill up with other dice:
			#reverse for ghost_number, i in ai.ghosts {
				if len(best_indices) < 5 && !contains(best_indices[:], i32(i)) {
					append(&best_indices, i32(i))
				}
			}
		} else {
			// Choose random dices...
			for i in 0 ..< len(ai.ghosts) do append(&best_indices, i32(i))
			rand.shuffle(best_indices[:])
		}

		best_numbers := [5]i32{}
		for index, i in best_indices[:5] do best_numbers[i] = ai.ghosts[index]

		best_score, best_factor: sco
		best_combo: CombinationType = .None
		highlighted := [5]bool{}

		for combo_type, c in CombinationType {
			if combo_type == .None do continue

			match, score, factor := test_combination(combo_type, best_numbers[:], &highlighted)
			if match && (factor > best_factor || score > best_score) {
				best_factor = factor
				best_score = score
				best_combo = combo_type
			}
		}

		// Only use ghosts if we expect a high score or if we might lose our ghosts...
		// If there are many dice left, the chances are high that there are many ghost
		// dice next round
		n_alive: i32 = 0
		for &die, d in game.dice {
			// The max number of ghosts next round, is the number of ghosts we have now
			// + the number of alive dice of the defensive player (roll cards not included)
			if die.state == .ALIVE && die.player != game.current_player do n_alive += 1
		}
		if best_score > 0 &&
		   (best_score > 20 || best_factor > 0 || i32(len(ai.ghosts)) + n_alive > ai.ghosts_max) {
			ai.roll.score += best_score
			ai.roll.factor += best_factor

			not_wanted_cards := bit_set[CardType] {
				.CardRoll_Exorcism,
				.CardRoll_FakeNews,
				.CardRoll_MarketCrash,
				.CardRoll_WhiteElephant,
			}
			cards := [3]Card{}
			cards_generate(cards[:], .FlashRollAndDiceCards)
			for card in cards {
				if card.type in not_wanted_cards do continue
				append(&ai.cards, card)
				break
			}

			ghosts_copy := make([dynamic]i32, len(ai.ghosts), cap(ai.ghosts))
			defer delete(ghosts_copy)
			copy(ghosts_copy[:], ai.ghosts[:])
			clear(&ai.ghosts)

			for ghost, index in ghosts_copy {
				if !contains(best_indices[:5], i32(index)) do append(&ai.ghosts, ghost)
			}
		}
	}

	antagonist_use_cards()

	state_change(.WAIT_FOR_PLAYER)
	tutorial(.Begin2)
}

antagonist_use_cards :: proc(even_on_dead_dice:bool=false){
	ai := &game.players[1]
	if len(ai.cards) == 0 do return

	cards_to_discard := [dynamic]i32{}
	defer delete(cards_to_discard)

	for &card, c in ai.cards {
		if card.active do continue

		#partial switch card.category {
		case .ROLL, .FLASH:
			card_activate(ai, &card)
		case .DICE:
			for &die in game.dice {
				if (die.state != .ALIVE && !even_on_dead_dice) || die.player != 1 do continue
				if card_assign(&die, card) {
					append(&cards_to_discard, i32(c))
					break
				}
			}
		}
	}

	#reverse for index in cards_to_discard {
		ordered_remove(&ai.cards, index)
	}
}
