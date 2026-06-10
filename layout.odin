package game

import "core:math"
import rl "vendor:raylib"

V2 :: [2]f32
V3 :: [3]f32

Layout :: struct{
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
REF_HEIGHT :f32: 1440
S: f32					// Scale value to adjust for different window sizes, etc.
SCALE :: proc(v: f32) -> f32{
	return math.ceil(v * S)
}

update_layout :: proc() {
	L.width = f32(rl.GetScreenWidth())
	L.height = f32(rl.GetScreenHeight())
	S = L.height / REF_HEIGHT // Scale

	L.font_size1 = SCALE(50)
	L.font_size2 = SCALE(30)

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
