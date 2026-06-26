package game

import "core:fmt"
import "core:math/rand"
import "core:reflect"
import "core:slice"
import rl "vendor:raylib"

AntagonistID :: enum{
	Antagonist_TheNoob,				// Special since it is the first
	// Aggressor,
	// Calm,
	// CEO,
	// Chaos,
	Antagonist_TheDictator,
	Antagonist_TheMathematician,
	// Mirror,
	// Mogul,
	// Outlaw,
	// Party,
	// Scientist,
	// Spiritual,
	// Tycoon,
}

TutorialID :: enum{Begin1, Begin2, GhostDice, GhostBoard, Cards, Cycles, Introduction}

Antagonist :: struct {
	id:				AntagonistID,
	past_ids:		bit_set[AntagonistID],
	level:			u32,					// move to the next level as soon as all antagonists have been met.
	story_id:    	string,
	story_index:       	i32,
	blocking:		bool,
	wanted_power:	f32,
	win_score:  	sco,
	tutorials:		bit_set[TutorialID],
	tutorials_off:	bool,
}

tutorial :: proc(id: TutorialID) -> bool{
	if len(game.antagonist.story_id) != 0 do return false
	if game.antagonist.tutorials_off || id in game.antagonist.tutorials do return false

	game.antagonist.tutorials += {id}

	// Tutorials are always blocking
	antagonist_story(fmt.aprintf("Tutorial_%s", reflect.enum_string(id)), blocking=true)

	return true
}

antagonist_set :: proc(id: AntagonistID) {
	game.antagonist.id = id
	game.antagonist.past_ids += {id}
}

show_antagonist_introduction :: proc() {
	fade_out()
	delay :: f32(1.0)

	ai := &game.players[1]
	color := ai.color

	font_size := L.font_size1+20*S
	board_size := min(L.width, L.height)-200*S
	board_position := rl.Vector2{(L.width - board_size) / 2., 50*S}
	padding := font_size

	draw_box(board_position, {}+board_size, fill=rl.BLACK)

	message := get_text(reflect.enum_string(game.antagonist.id), "title")
	char_duration :f32= 0.16
	spelling_time := char_duration * f32(len(message))
	spelling_done := game.state_clock-delay>spelling_time

	n_visible_chars := min(int(game.state_clock/char_duration), len(message))
	draw_text(message[:n_visible_chars], board_position+padding, font_size, color, underline=spelling_done)

	if !spelling_done do return

	icon_size := splash_shrink((game.state_clock-spelling_time-delay)/0.5, 1.) * board_size/2. * 1.3
	icon_position := board_position + board_size/2. - {0, SCALE(100)}
	draw_antagonist(game.antagonist.id, icon_position, icon_size, color)

	subline_clock := game.state_clock-spelling_time-delay-1.0
	if subline_clock < 0. do return
	subline_font_size := L.font_size2// * splash_shrink(subline_clock/0.5, 1.)
	draw_text("1st  ANTAGONIST", board_position+padding+{0, font_size+10*S}, subline_font_size, color)

	if subline_clock-2.0 < 0. do return

	font_size = L.font_size1
	position := board_position + {padding, icon_position.y+icon_size/2.+padding}
	draw_text("[h]ABILITIES:[h] [iCardRoll_HappyHour] + 6x [iDieFace6] with 2x [iCardDice_Optimist], 4x [iCardDice_PlusOne]\n[h]SCORE TO WIN:[h] 1000", position, font_size, color)

	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) || continue_button() do state_change(.WAIT_FOR_PLAYER)
}

antagonist_is_speaking :: proc() -> bool{
	return len(game.antagonist.story_id) != 0
}

antagonist_story :: proc(story_id: string, index: i32=1, blocking:bool=false) {
	fmt.println("antagonist story:", story_id, index, blocking)
	game.antagonist.story_id = story_id
	game.antagonist.story_index = index
	game.antagonist.blocking = blocking
}
antagonist_story_continue :: proc() {
	fmt.println("story continue:", game.antagonist.story_id, game.antagonist.story_index, game.antagonist.blocking)
	if len(game.antagonist.story_id) == 0 do return

	game.antagonist.story_index += 1
	text_id := fmt.tprintf("%s/%d", game.antagonist.story_id, game.antagonist.story_index)
	if text_id in app.texts {
		antagonist_story(game.antagonist.story_id, game.antagonist.story_index)
	} else {
		delete(game.antagonist.story_id)
		game.antagonist.story_id = ""
		game.antagonist.story_index = 0
		game.antagonist.blocking = false
	}
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

	if len(ai.cards) > 0 {
		cards_to_discard := [dynamic]i32{}
		defer delete(cards_to_discard)
		for &card, c in ai.cards {
			if card.active do continue

			#partial switch card.category {
			case .ROLL, .FLASH:
				card_activate(ai, &card)
			case .DICE:
				for &die in game.dice {
					if die.state != .ALIVE || die.player != 1 do continue
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

	state_change(.WAIT_FOR_PLAYER)

	tutorial(.Begin2)
}
