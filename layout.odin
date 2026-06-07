package game

import rl "vendor:raylib"

V2 :: [2]f32
V3 :: [3]f32

Layout :: struct{
	// S: f32,


	height: f32,
	width: f32,

	font_size1: f32,
	font_size2: f32,

	card_size: V2,

	score_positions: [2]V2,
	ghost_positions: [2]V2,
	hand_positions: [2]V2,
}
L: Layout
S: f32					// Scale value to adjust for different window sizes, etc.
REF_HEIGHT :f32: 1440

update_layout :: proc() {
	L.width = f32(rl.GetScreenWidth())
	L.height = f32(rl.GetScreenHeight())
	S = L.height / REF_HEIGHT // Scale

	L.font_size1 = 50 * S
	L.font_size2 = 30 * S

	L.card_size = {300, 350} * S

	L.score_positions = {
		{50*S, f32(L.height) - 200*S},
		{f32(L.width) - 50*S, f32(L.height) - 200*S},
	}

	L.hand_positions  = {
		V2{50, 50}*S,
		{f32(L.width) - 50*S - L.card_size.x, 50*S}
	}
	L.ghost_positions = {
			{50*S, f32(L.height) - 320*S},
			{f32(L.width) - 50*S, f32(L.height) - 320*S},
		}
}
