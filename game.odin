#+feature dynamic-literals
package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:sort"
import "core:strings"
import rl "vendor:raylib"

sco :: f64
void :: struct {}

AREA_SIZE :: 30.0
COLOR_BACKGROUND := rl.Color{203, 161, 53, 255}
COLOR_CARDS := [CardCategory]rl.Color {
	.NONE  = rl.BLACK,
	.ROLL  = rl.Color{200, 224, 193, 255},
	.FLASH = rl.Color{152, 95, 153, 255},
	.DICE  = rl.Color{245, 105, 96, 255},
	.CYCLE = rl.Color{106, 168, 168, 255},
}
COLOR_TABLE := rl.Color{196, 109, 94, 255}
COLOR_PLAYERS := [2]rl.Color{rl.Color{243, 201, 139, 255}, rl.Color{156, 246, 246, 255}}
COLOR_SHIFT :: -0.3

CAMERA_HEIGHT :: 75.

DICE_HALF_SIZE :: 0.75
EntityState :: enum {
	NOT_USED,
	DEAD,
	ALIVE,
}
Die :: struct {
	state:          EntityState,
	using body:     RigidBody,
	player:         u8,
	color1:         rl.Color, // face color (back ground)
	color2:         rl.Color, // points and borders color
	faces:          [6]i32, // which numbers are shown on the faces, normally 1..6 but it can be manipulated
	current_face:   int, // which face/side is shown on top, from 0..5
	current_number: i32, // which number is shown on top face, depends on the numbers in .faces
	current_score:  sco,
	already_scored: bool,
	upgrades:       [6]Card, // For each side is one upgrade possible:
	attack:         sco,
	health:         sco,
}

GameState :: enum {
	EXIT,
	MENU,
	ANTAGONIST_WELCOME,
	TUTORIAL,
	WAIT_FOR_ROLL,
	CHARGING,
	PRE_ROLLING,
	ROLLING,
	DICE_UPGRADES,
	CARDS_BATTLE,
	DICES_BATTLE,
	DICE_DEATHS,
	DICE_SCORING,
	CARDS_SCORING,
	SCORING_SUMMARY, // only for the animations (all points are flying in)
	WAIT_FOR_AI,
	GHOST_BOARD,
	CARDS_OFFER,
	UPGRADE_DIE,
	VICTORY,
	DEFEAT,
}

RollState :: struct {
	score:         sco,
	score_counter: i32,
	score_timer:   f32,
	factor:        sco,
	kills:         i32,
	effects:       map[CardType]void,
}

N_PLAYERS :: 2
Player :: struct {
	id:                           u8,
	color:                        rl.Color,
	color2:                       rl.Color,
	total_score:                  sco,
	roll:                         RollState,
	is_scoring:                   bool,
	cards:                        [dynamic]Card, // used for some roll cards
	max_lifetime_roll_cards:      i32,
	ghosts:                       [dynamic]i32,
	ghosts_max:                   i32,
	ghosts_costs_per_combination: i32,
	cycle:                        Cycle,
	dice_sorted:                  [dynamic]i32, // sorted list of dice indices for better visuals during battles and scoring
	n_dice:                       i32,
}

Cycle :: struct {
	current:             i32,
	scored_combinations: bit_set[CombinationType],
}

Camera3D :: struct {
	using raylib:     rl.Camera3D,
	desired_target:   rl.Vector3,
	desired_position: rl.Vector3,
	desired_fovy:     f32,
	timer:            f64,
	angle:            f32,
	trauma:           f32,
}

battle_id :: proc(a, b: int) -> int {
	// we want a unique id for each combination of two dice, regardless of their order
	if a < b do return a * 1000 + b
	return b * 1000 + a
}
BattleState :: enum {
	Over,
	Fighting,
	Retreating,
}
Battle :: struct {
	dice:               [2]^Die,
	previous_positions: [2]Vector3,
	timer:              f32,
	state:              BattleState,
	seen:               map[int]bool,
}
Game :: struct{
	running:			bool,

	// gui
	bg_color: 	   		 rl.Color,
	last_mouse_position: rl.Vector2,
	camera3d:            Camera3D,
	camera2d:            rl.Camera2D,
	particles:           [1000]Particles,
	icon_particles:      [1000]IconParticle,
	animations:          [200]Animation,

	// game world
	speed: 				 f32,
	state:               GameState,
	state_before:        GameState,
	state_timer:         f32,
	state_clock:         f32,
	players:             [2]Player,
	current_player:      u8,
	dice:                [dynamic]Die,
	contacts:            [dynamic]Contact,
	battle:              Battle,
	antagonist:          Antagonist,
	cards_offer:         [5]Card, // Up to five cards can be selected
	card_selected:       Card,
	ghosts_selected:     [5]i32,
	die_selected:        i32,
	power:               f32,
}
game: Game

GUI :: struct {
	font_size1:       f32,
	font_size2:       f32,
	score_positions:  [N_PLAYERS]rl.Vector2,
	ghost_positions:  [N_PLAYERS]rl.Vector2,
	hand_positions:   [N_PLAYERS]rl.Vector2,
	hand_area_height: f32,
	card_size:        rl.Vector2,
	width:            f32,
	height:           f32,
	bg_color:         rl.Color,
}
gui: GUI

camera_shake :: proc(intensity: f32, duration: f32) {
	game.camera3d.trauma = math.max(game.camera3d.trauma, intensity)
	game.camera3d.timer = 0.
}

game_init :: proc(){
	game = {
		running = true,
		speed = 2,

		// font = rl.LoadFont("assets/j_audio_cassette.otf"),
		bg_color        = rl.ColorBrightness(COLOR_PLAYERS[0], COLOR_SHIFT),
		state           = .PRE_ROLLING,
		players         = {
			{
				color                        = COLOR_PLAYERS[0],
				id                           = 0,
				n_dice                       = 6,
				ghosts_max                   = 10,
				ghosts_costs_per_combination = 5,
				max_lifetime_roll_cards      = 2, //ghosts={1, 2, 3, 4, 5}
			},
			{
				color                        = COLOR_PLAYERS[1],
				id                           = 1,
				n_dice                       = 6,
				ghosts_costs_per_combination = 5,
				ghosts_max                   = 10,
				max_lifetime_roll_cards      = 2, //ghosts={1, 2, 3, 4, 5}
			},
		},
		ghosts_selected = {-1, -1, -1, -1, -1},
		die_selected    = -1,
		camera3d = {
			up         = {0.0, 0.0, -1.},
			projection = .ORTHOGRAPHIC,
		},
		power=2.,
		antagonist={
			win_score=1000,
		}
	}
	camera_reset()

	game.camera2d = {}
	game.camera2d.target = {f32(L.width) / 2.0, f32(L.height) / 2.0}
	game.camera2d.offset = {f32(L.width) / 2.0, f32(L.height) / 2.0}
	// camera.rotation = 0.0f;
	// game.camera2d.zoom = target_ratio

	dice_reset(first_round = true)

	// game.antagonist = {
	// 	win_score           = 1000,
	// 	tutorial2            = true,
	// 	tutorial_cards       = true,
	// 	tutorial_ghost_board = true,
	// 	tutorial_cycles      = true,
	// }
	// antagonist_story("antagonist_tutorial1")
}

game_loop :: proc(dt: f32) {
	if !game.running do game_init()

	game.state_timer = max(0., game.state_timer - dt)
	game.state_clock += dt

	game_handle_input(dt)

	fmt.println("FPS: ", rl.GetFPS(), " dt: ", dt, " speed: ", game.speed, " state: ", game.state, " state timer:", game.state_timer)
	game_update(dt)

	// draw everything:
	game_draw(dt)
}

game_handle_input :: proc(dt: f32){
	// Zoom in and out:
	mouse_wheel := rl.GetMouseWheelMove()
	if mouse_wheel != 0.0 {
		game.camera3d.desired_position.y = max(min(game.camera3d.desired_position.y + 200.*mouse_wheel*dt, CAMERA_MAX_HEIGHT), 5.)
		game.camera3d.desired_position.z = CAMERA_MAX_HEIGHT-min(game.camera3d.desired_position.y, CAMERA_MAX_HEIGHT-3.)
		// game.camera3d.desired_fovy = linalg.lerp(game.camera3d.desired_fovy, game.camera3d.desired_position.y == 30. ? 40. : 50., dt * 5)
	}

	if rl.IsMouseButtonDown(.MIDDLE) {
		// game.camera_rotat
		delta := rl.GetMouseDelta()
		game.camera3d.angle += (delta.x + delta.y) * math.RAD_PER_DEG * dt * 5
	}

	if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
		if game.state == .GHOST_BOARD {
			state_change(.WAIT_FOR_ROLL)
			game.ghosts_selected = {-1, -1, -1, -1, -1}
		} else if game.state == .UPGRADE_DIE || game.state == .CARDS_OFFER {
			state_change(.WAIT_FOR_ROLL)
		} else {
			app.state = .Menu
		}
	}

	if rl.IsKeyPressed(rl.KeyboardKey.F) {
		game.speed += .5
	}
	if rl.IsKeyPressed(rl.KeyboardKey.D) {
		game.speed -= .5
	}
	if rl.IsKeyPressed(rl.KeyboardKey.G) {
		game.cards_offer = {}
		cards_generate(game.cards_offer[:5], .FlashRollAndDiceCards)
		state_change(.CARDS_OFFER)
	}
	if rl.IsKeyPressed(rl.KeyboardKey.H) {
		game.cards_offer = {}
		cards_generate(game.cards_offer[:5], .CycleCards)
		state_change(.CARDS_OFFER)
	}

	if game.state == .WAIT_FOR_ROLL && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
		state_change(.CHARGING)
		game.antagonist.wanted_power = rand.float32_range(0.3, 1.)
	}

	// Max power is reached after 3 seconds of charging)
	game.power = f32(math.min(1.0, game.state_clock / 0.25))
	if game.state == .CHARGING &&
	   ((game.current_player == 0 &&
				   (rl.IsKeyReleased(rl.KeyboardKey.SPACE) ||
						   rl.IsMouseButtonReleased(.LEFT))) ||
			   (game.current_player == 1 && game.power >= game.antagonist.wanted_power)) {
		dice_reset()
		state_change(.PRE_ROLLING)
		camera_shake(2.0, 0.5)
	}

	// if len(game.antagonist.story_id) > 0 {
	// 	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
	// 		antagonist_story_continue()
	// 		// @TODO: Stop the other code?
	// 	}
	// }

	if game.state >= .VICTORY && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
		game.antagonist.win_score *= game.state == .VICTORY ? 10. : 1.
		game.players[0].total_score = 0
		game.players[0].roll = {}
		game.players[1].total_score = 0
		game.players[1].roll = {}
		text := fmt.aprintf("Next score is %v!", game.antagonist.win_score)
		add_text(
			Vector2{L.width / 2., L.height / 2.},
			text,
			font_size = L.font_size1,
			color = rl.RAYWHITE,
		)
		state_change(.WAIT_FOR_ROLL)
	}
}

game_update :: proc(dt: real){
	// Update the camera
	game.camera3d.trauma = math.max(0., game.camera3d.trauma - dt * 2)
	camera_target := game.camera3d.trauma * random_vector(-1, 1) + game.camera3d.desired_target
	game.camera3d.target = linalg.lerp(game.camera3d.target, camera_target, f32(dt) * 5)
	camera_position :=
		game.camera3d.desired_position + game.camera3d.trauma * random_vector(-1, 1)
	game.camera3d.position = linalg.lerp(game.camera3d.position, camera_position, f32(dt) * 5)
	game.camera3d.fovy = linalg.lerp(game.camera3d.fovy, game.camera3d.desired_fovy, f32(dt) * 5)
	if game.camera3d.desired_position.y > CAMERA_MAX_HEIGHT-0.001{
		game.camera3d.projection = .ORTHOGRAPHIC
	} else {
		game.camera3d.projection = .PERSPECTIVE
	}

	for &player, i in game.players {
		for &card, c in player.cards {
			card.triggered -= dt
			if card.triggered < 0. do card.triggered = 0.
		}
	}

	if game.state_timer > 0. do return

	#partial switch game.state {
	case .PRE_ROLLING:
		apply_dice_upgrades(dt)
		state_change(.ROLLING)
	case .ROLLING:
		rolling(dt)
	case .DICE_UPGRADES:
		dice_upgrades(dt)
	case .CARDS_BATTLE:
		cards_battle(dt)
	case .DICES_BATTLE:
		dice_battle(dt)
	case .DICE_DEATHS:
		dice_deaths(dt)
	case .DICE_SCORING:
		dice_scoring(dt)
	case .CARDS_SCORING:
		cards_scoring(dt)
	case .SCORING_SUMMARY:
		scoring_summary(dt)
	case .WAIT_FOR_AI:
		wait_for_ai()
	case .VICTORY, .DEFEAT:
		end_of_level(dt)
	}
}

rolling :: proc(duration: real) {
	for &dice, d in game.dice {
		body_integrate(&dice, duration)
	}

	// walls and ground
	walls := []Plane {
		{direction = {0.0, 1.0, 0.0}},
		{direction = {1.0, 0.0, 0.0}, offset = -AREA_SIZE / 2.0},
		{direction = {-1.0, 0.0, 0.0}, offset = -AREA_SIZE / 2.0},
		{direction = {0.0, 0.0, 1.0}, offset = -AREA_SIZE / 2.0},
		{direction = {0.0, 0.0, -1.0}, offset = -AREA_SIZE / 2.0},
	}

	clear(&game.contacts)
	for &dice, d in game.dice {
		if len(game.contacts) > 1000 do break

		collision_wall := false
		for wall in walls {
			collision_wall |= collision_detect_box_plane(&dice, wall, &game.contacts)
		}

		collision_other_dice := false
		for &other_dice, od in game.dice {
			if dice == other_dice || other_dice.state != .ALIVE do continue

			collision_other_dice |= collision_detect_box_box(&dice, &other_dice, &game.contacts)
		}

		if collision_wall && dice.motion > 0.97 {
			volume := math.min(1.0, linalg.length(dice.velocity) / 200.0)
			pitch := rand.float32_range(.7, 1.1)
			play_sound(rand.int32_range(0, 4), volume = volume, pitch = pitch)
		}
		if collision_other_dice && dice.motion > 0.9 && game.state_clock > 1.0 {
			volume := math.min(1.0, linalg.length(dice.velocity) / 140.0)
			pitch := rand.float32_range(1., 1.5)
			play_sound(rand.int32_range(0, 4), volume = volume, pitch = pitch)
		}
	}

	if len(game.contacts) > 0 {
		resolver := ContactResolver {
			position_iterations = i32(len(game.contacts)) * 16,
			velocity_iterations = i32(len(game.contacts)) * 16,
		}
		contact_resolve_contacts(&resolver, game.contacts[:], duration)
	}

	for &die, d in game.dice {
		if die.state != .ALIVE do continue

		// Either wait until all game.dice are not moving that much anymore
		// or until enough time has past
		if die.motion > 0.9 && game.state_clock < 5. {
			return
		}

		faces := []Vector3 {
			{0, 0, 1}, // (1)
			{-1, 0, 0},
			{0, 1, 0},
			{0, -1, 0},
			{1, 0, 0},
			{0, 0, 0 - 1}, // 6
		}

		highest_face_height: f32 = -1.
		for face, i in faces {
			height := body_get_point_in_world_space(&die, face).y
			if height > highest_face_height {
				highest_face_height = height
				die.current_face = i
				die.current_number = die.faces[i]
			}
		}
		die.already_scored = false
	}

	// Get a sorted list from left-to-right for each player, so we have better visuals
	// for cascading events
	PositionIndex :: struct {
		index:    i32,
		position: Vector2,
	}

	for &player, p in game.players {
		dice_2d: [dynamic]PositionIndex
		defer delete(dice_2d)
		for die, d in game.dice {
			if die.state != .ALIVE || die.player != u8(p) do continue
			append(
				&dice_2d,
				PositionIndex{index = i32(d), position = Vector2{die.position.x, die.position.z}},
			)
		}
		slice.sort_by(dice_2d[:], proc(a, b: PositionIndex) -> bool {
				if a.position.x != b.position.x do return a.position.x < b.position.x
				return a.position.y > b.position.y
			})
		player.dice_sorted = {}
		for pi in dice_2d {
			append(&player.dice_sorted, pi.index)
		}
	}

	// We move to the next game.state
	state_change(.DICE_UPGRADES)
}

play_sound :: proc(sound_id: i32, volume: f32 = 1., pitch: f32 = 1.) {
	sound := app.sounds[sound_id]
	rl.StopSound(sound)
	rl.SetSoundVolume(sound, volume * 1.)
	rl.SetSoundPitch(sound, pitch)
	rl.PlaySound(sound)
}

scoring_summary :: proc(dt: real) {
	roll_scores := [2]sco{}
	for &player, p in game.players {
		if player.roll.factor > 0. {
			player.roll.score *= player.roll.factor
		}

		// We delay it due to the Revenge Roll Card
		roll_scores[p] = player.roll.score
		player.roll = {}

		for &card, c in player.cards {
			card.already_scored = false
		}
	}

	if .CardRoll_Revenge in game.players[0].roll.effects && roll_scores[0] < roll_scores[1] {
		roll_scores = {roll_scores[1], roll_scores[0]}
	}
	if .CardRoll_Revenge in game.players[1].roll.effects && roll_scores[1] < roll_scores[0] {
		roll_scores = {roll_scores[1], roll_scores[0]}
	}
	for &player, p in game.players {
		player.total_score += roll_scores[p]

		// Tidy up all cards that should be inactive now...
		cards_copy := make([dynamic]Card, len(player.cards), cap(player.cards))
		defer delete(cards_copy)
		copy(cards_copy[:], player.cards[:])
		clear(&player.cards)

		for &card, index in cards_copy {
			if card.active do card.lifetime -= 1
			if !card.active || card.lifetime > 0 {
				append(&player.cards, card)
			} else {
				play_sound(11)
				texture_ids := []Vector2{{0, 8}, {0, 9}, {0, 10}, {0, 11}, {0, 12}, {0, 13}}
				// add_icon_particles(
				// 	L.hand_positions[p], L.card_size, texture_ids, COLOR_CARDS[card.category])
			}
		}
	}

	if game.players[0].total_score >= game.antagonist.win_score {
		antagonist_story("antagonist_defeat")
		state_change(.VICTORY)
		return
	} else if game.players[1].total_score >= game.antagonist.win_score {
		antagonist_story("antagonist_wins")
		state_change(.DEFEAT)
		return
	}

	game.current_player = (game.current_player + 1) % N_PLAYERS
	state_change(.WAIT_FOR_AI)

	camera_reset()
}

end_of_level :: proc(dt: real) {
	game.state_timer = 0.5

	victor: u8 = game.state == .VICTORY ? 0 : 1
	loser: u8 = game.state == .DEFEAT ? 0 : 1
	for &die, d in game.dice {
		if die.state != .ALIVE do continue
		if die.player == loser {
			die.state = .DEAD
		} else {
			add_particles(die.position, die.color1)
		}
	}
	for i in 0 ..< 10 {
		particles := &game.particles[i]
		if !particles.visible || particles.lifetime > .7 do continue
		for position, p in particles.positions {
			add_particles(position, particles.color)
			if p > 1 do break
		}
	}
	// state_change(.WAIT_FOR_ROLL)
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

game_draw :: proc(dt: real) {
	human := &game.players[0]

	rl.BeginDrawing()
	defer rl.EndDrawing()

	anti_bg := rl.Color{}
	if game.state == .WAIT_FOR_ROLL {
		ratio := game.state_timer / 3.
		color1 := rl.ColorBrightness(COLOR_PLAYERS[game.current_player], COLOR_SHIFT)
		color2 := rl.ColorBrightness(
			COLOR_PLAYERS[(game.current_player + 1) % N_PLAYERS],
			COLOR_SHIFT,
		)
		game.bg_color = rl.ColorLerp(color2, color1, ratio)
		anti_bg = rl.ColorLerp(color1, color2, ratio)
	} else if game.state == .ROLLING {
		game.bg_color = rl.ColorBrightness(COLOR_PLAYERS[game.current_player], COLOR_SHIFT)
		anti_bg = rl.ColorBrightness(
			COLOR_PLAYERS[(game.current_player + 1) % N_PLAYERS],
			COLOR_SHIFT,
		)
	}
	rl.ClearBackground(game.bg_color)

	rl.BeginMode3D(game.camera3d)

	// Draw a big cube to represent the area where the game.dice can move
	rl.DrawCube(rl.Vector3{0.0, -.6, .0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)
	rl.DrawCube(
		rl.Vector3{0.0, -.6, .0},
		AREA_SIZE + 1.,
		0.9,
		AREA_SIZE + 1.,
		rl.ColorBrightness(COLOR_TABLE, -0.2),
	)
	rl.DrawCubeWires(rl.Vector3{0.0, -.6, .0}, AREA_SIZE, 1.0, AREA_SIZE, rl.BLACK)

	if game.state == .WAIT_FOR_ROLL &&
	   (rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT)) {
		game.die_selected = -1
	}

	dice_hovered := -1
	for &dice, d in game.dice {
		if dice.state != .ALIVE do continue
		hoverable := game.state == .WAIT_FOR_ROLL
		if draw_die(dice, hoverable = hoverable) {
			dice_hovered = d
			if rl.IsMouseButtonPressed(.LEFT) {
				game.die_selected = i32(d)
			}
		}
	}

	show_particles(dt)
	rl.EndMode3D()

	info := game.state == .WAIT_FOR_ROLL // || game.state == .UPGRADE_DIE
	if info && game.die_selected != -1 {
		selected := game.die_selected != -1
		die := selected ? game.dice[game.die_selected] : game.dice[dice_hovered]
		draw_die_info(die)
	}

	// if len(game.antagonist.story_id) > 0 {
	// 	draw_antagonist_story()
	// }

	show_player_stuff(dt)
	#partial switch game.state {
	case .CHARGING:
		// fade_out()
		// Draw a power bar at the center of the screen
		width: f32 = 800.*S
		height: f32 = 80.*S
		x := (f32(L.width) - width) / 2.
		y := (f32(L.height) - height) / 2.
		rl.DrawRectangleV(
			{x, y},
			{game.power * width, height},
			game.players[game.current_player].color,
		)
		rl.DrawRectangleLinesEx({x, y, width, height}, 2.*S, rl.BLACK)
	case .GHOST_BOARD:
		show_ghost_board()
	case .WAIT_FOR_ROLL:
		text := "Press <SPACE> to continue"
		if button(
			text, {L.width / 2., L.height - 150*S},
			size = V2{300, 80}*S,
			font_size = L.font_size1,
			color = rl.BLANK, anchor = .CENTER,
		) {
			state_change(.CHARGING)
		}
	case .CARDS_OFFER:
		show_cards_offer()
	case .UPGRADE_DIE:
		show_upgrade_die()
	}

	if game.state == .VICTORY || game.state == .DEFEAT {
		text := "Press <SPACE> to continue"
		draw_text(
			text,
			{L.width / 2., L.height - 150*S},
			font_size = L.font_size1,
			color = rl.RAYWHITE,
			anchor = .CENTER,
		)
	}

	show_animations(dt)
}

wait :: proc(duration: real) {
	game.state_timer = duration / game.speed
}

state_change :: proc(new_state: GameState, wait: f32 = 0.) {
	game.state_before = game.state
	game.state = new_state
	game.state_clock = 0.
	game.state_timer = wait / game.speed

	if new_state == .CHARGING {
		camera_reset()
		game.die_selected = -1
	}
}

show_upgrade_die :: proc(){
	human := &game.players[0]
	mouse_pos := rl.GetMousePosition()

	selected_die: ^Die
	selected_face: i32 = -1
	for &die in game.dice {
		if die.state != .ALIVE || die.player != 0 do continue
		hovered_face := draw_die_info(die)
		if hovered_face != -1 {
			selected_die = &die
			selected_face = hovered_face
		}
	}
	// game.card_selected.triggered = game.die_selected >= 0 ? 1. : 0.

	text := "Choose a dice to assign this card to"
	draw_text(
		text,
		{L.width / 2., L.height - 150*S},
		L.font_size1,
		rl.RAYWHITE,
		anchor = .CENTER,
	)
	draw_card(game.card_selected, mouse_pos - {L.card_size.x / 2, L.card_size.y + 50*S})

	if rl.IsMouseButtonPressed(.LEFT) && selected_face != -1 {
		could_upgrade := card_assign(selected_die, game.card_selected, selected_face)
		game.card_selected = {}

		if !could_upgrade {
			add_text(
				selected_die.position,
				fmt.aprint("Die has no free upgrade slots!"),
				selected_die.color1,
				1.5,
			)
		}
		state_change(.WAIT_FOR_ROLL)
	} else if rl.IsMouseButtonPressed(.RIGHT) || rl.IsKeyPressed(.ESCAPE) {
		game.card_selected.triggered = 0.
		append(&human.cards, game.card_selected)
		game.card_selected = {}
		add_text(mouse_pos, fmt.aprint("Keep card in hand!"), human.color, 1.5)
		state_change(.WAIT_FOR_ROLL)
	}
}

draw_antagonist_story :: proc(){

	// Let's the bubble get bigger and smaller to make it more dynamic, and also changes the color a bit
	time_factor := 1. + 0.05 * math.sin(f32(rl.GetTime()) * 5)
	font_size := L.font_size1 * time_factor
	thickness: f32 = 4.
	max_width: f32 = 600*S * time_factor
	padding: f32 = 20.*S
	color_fill := rl.BLACK
	color_text := game.players[1].color
	message := get_text(game.antagonist.story_id, game.antagonist.index)
	size := measure_text(message, font_size, max_width = max_width) + padding
	position := Vector2{L.width - 40*S, L.height - 200*S} - size - padding

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
	draw_text(message, position + padding / 2., font_size, color_text, max_width = max_width)

	hovered := rl.CheckCollisionPointRec(
		rl.GetMousePosition(),
		{x = position.x, y = position.y, width = size.x, height = size.y},
	)
	clicked := hovered && rl.IsMouseButtonPressed(.LEFT)
	if clicked {
		antagonist_story_continue()
	}

	button_pos := position + size

	// if button(fmt.tprint("&gt;"), button_pos, font_size=L.font_size2, anchor=.RIGHT, text_color=color_text, hover_motion=false) {
	// 	antagonist_story_continue()
	// }
}

show_particles :: proc(dt: real) {
	for &particle in game.particles {
		if !particle.visible do continue

		// Apply some damping to the velocity so the game.particles eventually stop
		particle.lifetime -= dt
		if particle.lifetime < 0. {
			particle.visible = false
			continue
		}

		for i in 0 ..< len(particle.positions) {
			particle.positions[i] += particle.velocities[i] * dt
			particle.velocities[i] *= 0.95
		}
	}
	size: f32 = 0.35
	for particle in game.particles {
		if !particle.visible do continue

		color := particle.color
		if particle.lifetime < 0.5 {
			color.a = u8((particle.lifetime / 0.5) * 255)
		}
		for position in particle.positions {
			rl.DrawCube(position, size, size, size, color)
			rl.DrawCubeWires(position, size, size, size, {0, 0, 0, 255})
			// rl.DrawSphereWires(position, 0.3, 5, 5, {0, 0, 0, color.a})
		}
	}
}

show_animations :: proc(dt: real){
	for &animation in game.animations {
		if !animation.visible do continue

		if animation.delay > 0. {
			animation.delay -= dt * game.speed
			continue
		}
		animation.lifetime -= dt * game.speed
		if animation.lifetime <= 0. {
			animation.visible = false
			if len(animation.text) > 0 do delete(animation.text)
			continue
		}

		start_2d, end_2d: Vector2
		if start_3d, is_vec3 := animation.start.(Vector3); is_vec3 {
			start_2d = rl.GetWorldToScreen(start_3d, game.camera3d)
		} else do start_2d = animation.start.(Vector2)

		if end_3d, is_vec3 := animation.end.(Vector3); is_vec3 {
			end_2d = rl.GetWorldToScreen(end_3d, game.camera3d)
		} else do end_2d = animation.end.(Vector2)

		// adapt to zoom in
		font_size := L.font_size2 // * (1.+(1. - (game.camera3d.fovy-25)/5))

		life_ratio := animation.lifetime / animation.start_lifetime
		alpha := life_ratio > 0.3 ? 1.0 : life_ratio / 0.3
		size_factor := splash(life_ratio)
		font_size *= size_factor

		x := math.lerp(start_2d.x, end_2d.x, 1. - life_ratio)
		y := math.lerp(start_2d.y, end_2d.y, 1. - life_ratio)

		icon_id, has_icon := animation.icon_id.?
		if has_icon {
			icon_size: f32 =
				animation.icon_size > 0. ? animation.icon_size * size_factor : font_size * 4
			draw_texture(
				icon_id,
				{x - icon_size / 2, y - icon_size / 2},
				icon_size,
				rl.ColorAlpha(animation.color, alpha),
			)
		}

		if len(animation.text) == 0 do continue

		// text_size := measure_text(animation.text, font_size)
		// x -= text_size.x/2.
		// y -= text_size.y/2.

		// box_position := Vector2{x-5, y-5}
		// if animation.anchor == .LEFT do box_position.x += text_size.x/2.
		// if animation.anchor == .RIGHT do box_position.x -= text_size.x
		text_color := rl.ColorAlpha(animation.color, alpha)
		text_outline := rl.BLACK
		box_fill := rl.BLANK
		if !has_icon {
			box_fill = rl.ColorAlpha(animation.color, alpha)
			text_color = rl.ColorAlpha(rl.BLACK, alpha)
			text_outline = rl.BLANK
		}
		draw_text(
			animation.text,
			{x, y},
			font_size,
			text_color,
			outline = text_outline,
			boxed = box_fill,
			anchor = animation.anchor,
		)
	}

	draw_icon_particles(dt)
}

show_ghost_board :: proc(){
	human := &game.players[0]

	fade_out()

	board_size := rl.Vector2{920*S, L.height - 150*S}
	board_position := rl.Vector2{(L.width - board_size.x) / 2., 50*S}
	board_color := COLOR_PLAYERS[0] / 2
	board_color.a = 255

	draw_box(board_position, board_size, fill = board_color)

	ghost_cols: i32 = 10 // @TODO: make this dynamic based on the max number of ghosts a player can have
	ghost_size: f32 = L.font_size1 + 10*S
	ghost_padding: f32 = 5*S
	for i in 0 ..< human.ghosts_max {
		ghost_index := i32(i)
		row := ghost_index / ghost_cols
		col := ghost_index % ghost_cols
		position :=
			board_position +
			{20, 70}*S +
			(ghost_size + ghost_padding) * rl.Vector2{f32(col), f32(row)}

		if ghost_index >= i32(len(human.ghosts)) {
			thickness: f32 = 2*S
			draw_box(
				position + {0, 2}*S,
				{ghost_size, ghost_size - thickness} - thickness,
				fill = board_color / 2,
				thickness = thickness,
			)
			continue
		}

		ghost_number := human.ghosts[ghost_index]
		active := contains(game.ghosts_selected[:], i32(ghost_index))

		if dice_button(ghost_number, position, ghost_size, active_color = human.color, active = active, clickable = true) {
			free_index := -1
			for &slot, slot_index in game.ghosts_selected {
				if slot == ghost_index {
					slot = -1 // deselect if already selected
					free_index = -1 // no further action
					break
				}
				if slot == -1 {
					free_index = slot_index
					break
				}
			}
			if free_index >= 0 {
				game.ghosts_selected[free_index] = ghost_index
			}
		}
	}
	highlighted := [5]bool{}
	ghost_selected_numbers := [5]i32{}
	for i, ghost_index in game.ghosts_selected {
		if i == -1 do break

		ghost_selected_numbers[ghost_index] = human.ghosts[i]
	}
	enough_ghosts := !contains(game.ghosts_selected[:], i32(-1))
	ghost_size2: f32 = L.font_size2 + 10*S
	highest_score := 0.
	// highest_combo := CombinationType_None
	n_scored_combos := 0
	for combo_type, c in CombinationType {
		if combo_type == .None do continue

		position := board_position + rl.Vector2{20, 150 + f32(c) * L.font_size2 * 1.6}*S
		match, score, factor := test_combination(
			combo_type,
			ghost_selected_numbers[:],
			&highlighted,
		)
		already_scored := combo_type in human.cycle.scored_combinations
		if already_scored do n_scored_combos += 1
		draw_text(
			fmt.tprintf("%v", combo_type),
			position,
			L.font_size2,
			(match && !already_scored) ? rl.RAYWHITE : rl.GRAY,
			strikethrough = already_scored,
		)
		if !already_scored && match && enough_ghosts {
			if factor > 0 {
				draw_text(
					fmt.tprintf("+%.f, x%.f", score, factor),
					position + {600, 0}*S,
					color = rl.RAYWHITE,
				)
			} else {
				draw_text(fmt.tprintf("+%.f", score), position + {600, 0}*S, color = rl.RAYWHITE)
			}

			for ghost_number, g in ghost_selected_numbers {
				dice_button(
					ghost_number,
					position + {300 + f32(g) * (ghost_size2 + 5), -7}*S,
					ghost_size2,
					active_color = human.color,
					active = highlighted[g],
					clickable = false,
				)
			}

			if button("Score", position + {700, -4.}*S) {
				human.cycle.scored_combinations += {combo_type}
				human.roll.score += score // @TODO: Add it to roll score
				ghosts_copy := make([dynamic]i32, len(human.ghosts), cap(human.ghosts))
				defer delete(ghosts_copy)
				copy(ghosts_copy[:], human.ghosts[:])
				clear(&human.ghosts)

				ghosts_discount := 5 - human.ghosts_costs_per_combination
				for ghost, index in ghosts_copy {
					if !contains(game.ghosts_selected[:], i32(index)) {
						append(&human.ghosts, ghost)
						continue
					} else if ghosts_discount > 0 {
						append(&human.ghosts, ghost)
						ghosts_discount -= 1
					}
				}
				game.ghosts_selected = {} - 1 // deselect everything
				game.cards_offer = {}
				cards_generate(game.cards_offer[:3], .FlashRollAndDiceCards)
				state_change(.CARDS_OFFER)
			}
			if match && score > highest_score {
				highest_score = score
			}
		}
		highlighted = {}
	}

	text := "There is no matching combination"
	if len(human.ghosts) < 5 {
		text = fmt.tprint("Wait for at least 5 ghost dices to score combinations")
	} else if contains(game.ghosts_selected[:], i32(-1)) {
		text = fmt.tprintf(
			"Select %v more ghost dices to score combinations",
			count(game.ghosts_selected[:], i32(-1)),
		)
	} else if highest_score > 0 {
		text = fmt.tprintf("Your best combination is worth %v points", highest_score)
	}
	draw_text(text, board_position + rl.Vector2{20, 20}*S, color=rl.RAYWHITE)
	if button("ESC", board_position + rl.Vector2{board_size.x - 20, 20}*S, anchor = .RIGHT,) {
		state_change(.WAIT_FOR_ROLL)
		game.ghosts_selected = {-1, -1, -1, -1, -1}
	}
	if n_scored_combos == 15 {
		if button("FINISH CYCLE", board_position + board_size - {20, 70}*S, anchor = .RIGHT,) {
			add_text(
				board_position + board_size / 2.,
				fmt.aprint("CYCLE COMPLETED!"),
				human.color,
				2.,
				font_size = L.font_size1,
				anchor = TextAnchor.CENTER,
			)
			human.roll.score += math.floor(human.total_score) / 10.
			game.ghosts_selected = {} - 1 // deselect everything
			game.cards_offer = {}
			cards_generate(game.cards_offer[:3], .CycleCards)
			human.cycle.scored_combinations = {}
			state_change(.CARDS_OFFER)
		}
	} else if n_scored_combos > 9 {
		if len(game.antagonist.story_id) == 0 && !game.antagonist.tutorial_cycles {
			antagonist_story("antagonist_tutorial_cycles")
		}
		if button(
			"RUSH CYCLE",
			board_position + board_size - {20, 70}*S,
			L.font_size2,
			anchor = .RIGHT,
		) {
			add_text(
				board_position + board_size / 2.,
				fmt.aprint("CYCLE COMPLETED BY RUSHING!"),
				human.color,
				2.,
				font_size = L.font_size1,
				anchor = TextAnchor.CENTER,
			)
			game.ghosts_selected = {} - 1 // deselect everything
			game.cards_offer = {}
			cards_generate(game.cards_offer[:2], .CycleCards)
			human.cycle.scored_combinations = {}
			state_change(.CARDS_OFFER)
		}
	} else {
		draw_text(
			fmt.tprintf("%v/15 combinations scored", n_scored_combos),
			board_position + board_size - {20, 70}*S,
			anchor = .RIGHT,
		)
	}

	if len(game.antagonist.story_id) == 0 && !game.antagonist.tutorial_ghost_board {
		game.antagonist.tutorial_ghost_board = true
		antagonist_story("antagonist_tutorial_ghost_board")
	}
}

show_cards_offer :: proc(){
	fade_out()
	human := &game.players[0]
	game.die_selected = -1

	text := "Choose one of these cards"
	draw_text(
		text,
		{L.width / 2., L.height - 150*S},
		L.font_size1,
		rl.RAYWHITE,
		anchor = .CENTER,
	)

	n_cards: i32
	for card in game.cards_offer do if card.type != .CardNone do n_cards += 1

	margin: f32 = 50.*S
	mid_i32 := int(n_cards / 2)
	mid_f32 := f32(n_cards) / 2.

	hovered_card: ^Card = nil
	hovered_card_index: i32
	hovered_position: Vector2

	for &card, c in game.cards_offer {
		if card.type == .CardNone do continue

		position: Vector2 = {
			L.width / 2. - L.card_size.x / 2.,
			(L.height - L.card_size.y) / 2.,
		}
		if n_cards % 2 == 1 {
			if c == mid_i32 {
				// nothing ...
			} else if c < mid_i32 {
				position.x -= f32(mid_i32 - c) * (L.card_size.x + margin)
			} else {
				position.x += f32(c - mid_i32) * (L.card_size.x + margin)
			}
		}
		position.y += math.sin(f32(rl.GetTime()) + position.x) * SCALE(10)
		hovered := card_is_hovered(position)
		if hovered_card == nil && hovered {
			hovered_card = &card
			hovered_card_index = i32(c)
			hovered_position = position
		} else {
			draw_card(card, position, with_info=false, hoverable=false)
		}
	}

	if hovered_card != nil {
		actions := []string{"KEEP", "ACTIVATE"}
		if hovered_card.category == .DICE do actions = {"KEEP", "ASSIGN"}
		else if hovered_card.category == .CYCLE do actions = {"ACTIVATE"}
		_, action := draw_card(hovered_card^, hovered_position, actions = actions)
		if action == 1 {
			if hovered_card.category == .FLASH {
				card_activate(human, hovered_card)
				state_change(.WAIT_FOR_ROLL)
				game.cards_offer = {}
			} else if hovered_card.category == .ROLL {
				card_activate(human, hovered_card)
				append(&human.cards, hovered_card^)
				state_change(.WAIT_FOR_ROLL)
				game.cards_offer = {}
			} else if hovered_card.category == .DICE {
				game.card_selected = hovered_card^
				state_change(.UPGRADE_DIE)
				game.cards_offer = {}
			}
		} else if action == 0 {
			if hovered_card.category == .CYCLE {
				card_activate(human, hovered_card)
			} else {
				append(&human.cards, hovered_card^)
			}
			state_change(.WAIT_FOR_ROLL)
			game.cards_offer = {}
		}
	}

	if len(game.antagonist.story_id) == 0 && !game.antagonist.tutorial_cards {
		game.antagonist.tutorial_cards = true
		antagonist_story("antagonist_tutorial_cards")
	}
}

show_player_stuff :: proc(dt: real){
	for &player, p in game.players {
		// Draw ghost dice on the side:
		ghost_cols: i32 = 5 // @TODO: make this dynamic based on the max number of ghosts a player can have
		ghost_size: f32 = L.font_size1
		ghost_padding: f32 = 4*S
		ghost_dx := ghost_size + ghost_padding
		for i in 0 ..< player.ghosts_max {
			ghost_index := i32(i)
			row := ghost_index / ghost_cols
			col := ghost_index % ghost_cols
			if p == 1 do col *= -1 // flip the ghosts for the right player
			position := L.ghost_positions[p] + ghost_dx * rl.Vector2{f32(col), f32(row)}
			if p == 1 do position.x -= ghost_size + ghost_padding // shift the right player's ghosts to the left

			if ghost_index >= i32(len(player.ghosts)) {
				draw_box(
					position + {2, 2}*S,
					{ghost_size - 2*S, ghost_size - 2*S} - 2.*S,
					fill = {100, 100, 100, 120},
					thickness = 2.*S,
				)
				continue
			}
			ghost_number := player.ghosts[ghost_index]

			clickable := game.state == .WAIT_FOR_ROLL && p == 0
			if dice_button(
				ghost_number,
				position,
				ghost_size,
				active_color = player.color,
				clickable = clickable,
			) {
				state_change(.GHOST_BOARD)
				game.ghosts_selected[0] = i32(i)
			}
		}
		if p == 0 && game.state == .WAIT_FOR_ROLL {
			combos := possible_combinations(player.ghosts[:])
			combos_counter := 0
			for combo in combos {
				if combo == .None do continue
				if combo in player.cycle.scored_combinations do continue
				combos_counter += 1
			}
			if combos_counter > 0 {
				text := fmt.aprintf("%v COMBINATIONS!", combos_counter)
				position := L.ghost_positions[p]
				position.x += (ghost_dx * f32(ghost_cols)) / 2.
				position.y += ghost_size // + L.font_size2/.2
				font_size := L.font_size2 * (1. + 0.5 * splash(game.state_clock))
				draw_text(
					text,
					position,
					color = player.color,
					font_size = font_size,
					anchor = .CENTER,
					outline = rl.BLACK,
				)
			}
		}

		position := L.score_positions[p]
		text := fmt.tprintf("%.f", player.total_score)
		draw_text(
			text,
			{position.x, position.y + 40*S},
			L.font_size1,
			player.color,
			anchor = (p == 1) ? .RIGHT : .LEFT,
		)

		text = (p == 0) ? "YOU" : "ANTAGONIST"
		draw_text(
			text,
			{position.x, position.y + 100*S},
			L.font_size2,
			player.color,
			anchor = (p == 1) ? .RIGHT : .LEFT,
			overline = true,
		)

		if game.state == .DICE_SCORING || game.state == .SCORING_SUMMARY || player.roll.score > 0. {

			font_size := L.font_size1 * (1. + 0.5 * splash(player.roll.score_timer))
			player.roll.score_timer -= dt
			if player.is_scoring && player.roll.score > 0. {
				font_size += math.max((0.3 - game.state_clock), 0.1) * 100*S
			}
			if player.roll.factor > 0 {
				text = fmt.tprintf("+ %.f X %.f", player.roll.score, player.roll.factor)
			} else {
				text = fmt.tprintf("+ %.f", player.roll.score)
			}

			if p == 1 {
				// Shift the right player's score so it is always 50 pixels from the right side
				position.x = L.width - measure_text(text, font_size).x - 50*S
			}

			draw_text(text, position, font_size, player.color)
		}

		hovered_card: ^Card
		hovered_card_index: i32
		hovered_position: Vector2

		lowest_y := L.ghost_positions[p].y - 10.*S
		area_y := lowest_y - L.hand_positions[p].y - L.card_size.y
		for &card, c in player.cards {
			position := L.hand_positions[p]
			if f32(len(player.cards)) * (L.card_size.y + 40*S) > lowest_y {
				position.y += area_y / f32(len(player.cards)) * f32(c)
			} else {
				position.y += f32(c) * (L.card_size.y + 40*S)
			}
			position.x += f32(c % 2)
			hovered := card_is_hovered(position) && game.state == .WAIT_FOR_ROLL
			if hovered_card == nil && hovered {
				hovered_card = &card
				hovered_card_index = i32(c)
				hovered_position = position
			} else {
				draw_card(card, position, with_info = false, hoverable = false)
			}
		}

		if hovered_card != nil {
			fade_out()
			actions := []string{}
			if game.state == .WAIT_FOR_ROLL && p == 0 {
				if hovered_card.category < .DICE do actions = hovered_card.active ? {"DISCARD"} : {"DISCARD", "ACTIVATE"}
				else if hovered_card.category == .DICE do actions = {"DISCARD", "ASSIGN"}
				else if hovered_card.category == .CYCLE do actions = {"DISCARD", "ACTIVATE"}
			}
			_, action := draw_card(hovered_card^, hovered_position, actions = actions)

			if game.state == .WAIT_FOR_ROLL && action == 1 {
				if hovered_card.category == .FLASH {
					card_activate(&player, hovered_card)
					card_discard(&player, hovered_card_index, silent = true)
				} else if hovered_card.category == .ROLL {
					card_activate(&player, hovered_card)
				} else if hovered_card.category == .DICE {
					game.card_selected = hovered_card^
					card_discard(&player, hovered_card_index, silent = true)
					state_change(.UPGRADE_DIE)
				}
			} else if action == 0 {
				card_discard(&player, hovered_card_index)
			}
		}
	}
}
