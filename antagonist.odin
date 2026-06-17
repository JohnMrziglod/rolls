package game

import "core:fmt"
import rl "vendor:raylib"

AntagonistID :: enum{
	Noob,				// Special since it is the first
	// Aggressor,
	// Calm,
	// CEO,
	// Chaos,
	// Fascist,
	Mathematician,
	// Mirror,
	// Mogul,
	// Outlaw,
	// Party,
	// Scientist,
	// Spiritual,
	// Tycoon,
}

Antagonist :: struct {
	id: 		AntagonistID,
	past_ids: 	bit_set[AntagonistID],
	level:		u32,					// move to the next level as soon as all antagonists have been met.
	story_id:             string,
	index:                i32,
	wanted_power:         f32,
	win_score:           sco,
	tutorial2:            bool,
	tutorial_ghost_board: bool,
	tutorial_cards:       bool,
	tutorial_cycles:      bool,
}



antagonist_set :: proc(id: AntagonistID) {
	game.antagonist.id = id
	game.antagonist.past_ids += {id}
}

draw_antagonist_welcome :: proc() {
	fade_out()

	ai := &game.players[1]
	color := ai.color

	board_size := rl.Vector2{920*S, L.height - 150*S}
	board_position := rl.Vector2{(L.width - board_size.x) / 2., 50*S}

	draw_box(board_position, board_size, fill=rl.BLACK)
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
