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
	// Fascist,
	Antagonist_TheMathematician,
	// Mirror,
	// Mogul,
	// Outlaw,
	// Party,
	// Scientist,
	// Spiritual,
	// Tycoon,
}

Antagonist :: struct {
	id:				AntagonistID,
	past_ids:		bit_set[AntagonistID],
	level:			u32,					// move to the next level as soon as all antagonists have been met.
	story_id:    	string,
	index:       	i32,
	wanted_power:	f32,
	win_score:  	sco,
	tutorial2:            bool,
	tutorial_ghost_board: bool,
	tutorial_cards:       bool,
	tutorial_cycles:      bool,
}

antagonist_set :: proc(id: AntagonistID) {
	game.antagonist.id = id
	game.antagonist.past_ids += {id}
}

show_antagonist_welcome :: proc() {
	fade_out()

	ai := &game.players[1]
	color := ai.color

	font_size := L.font_size1+20*S
	board_size := min(L.width, L.height)-200*S
	board_position := rl.Vector2{(L.width - board_size) / 2., 50*S}
	padding := font_size

	draw_box(board_position, {}+board_size, fill=rl.BLACK)

	message := get_text(reflect.enum_string(game.antagonist.id), "title")
	char_duration :f32= 0.2
	n_visible_chars := min(int(game.state_clock/char_duration), len(message))
	draw_text(message[:n_visible_chars], board_position+padding, font_size, color)

	spelling_time := char_duration * f32(len(message))
	if game.state_clock-0.3<spelling_time do return

	icon_size := splash((game.state_clock-spelling_time-0.3)/0.5, 1.) * board_size/2.
	draw_antagonist(game.antagonist.id, board_position + board_size/2., icon_size, color)
}

antagonist_story :: proc(story_id: string, index: i32 = 1) {
	game.antagonist.story_id = story_id
	game.antagonist.index = index
}
antagonist_story_continue :: proc() {
	if len(game.antagonist.story_id) == 0 do return

	game.antagonist.index += 1
	text_id := fmt.aprintf("%s/%d", game.antagonist.story_id, game.antagonist.index)
	if text_id in app.texts {
		antagonist_story(game.antagonist.story_id, game.antagonist.index)
	} else {
		game.antagonist.story_id = ""
		game.antagonist.index = 0
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
			case .ROLL:
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

	state_change(.WAIT_FOR_ROLL)
}
