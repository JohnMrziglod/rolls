package game

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:os"
import "core:reflect"
import vmem "core:mem/virtual"
import "core:strings"
import rl "vendor:raylib"

sco :: f64

AREA_SIZE :: 30.0
// COLOR_BACKGROUND := rl.Color{203, 161, 53, 255}
CARD_TYPE :: enum {ROLL, UPGRADE, CYCLE}
COLOR_CARDS := [CARD_TYPE]rl.Color{
	.ROLL=rl.Color{200, 224, 193, 255},
	.UPGRADE=rl.Color{245, 105, 96, 255},
	.CYCLE=rl.Color{106, 168, 168, 255},
}
COLOR_TABLE := rl.Color{196, 109, 94, 255}
COLOR_PLAYERS := [2]rl.Color{
	rl.Color{243, 201, 139, 255},
	rl.Color{156, 246, 246, 255},
}


N_PLAYERS :: 2
Player :: struct {
	color: rl.Color,
	total_score: sco,
	roll_score: sco,
	roll_multiplier: sco,
	roll_antennas: sco,
	roll_kills: i32,
	is_scoring: bool,

	cards: []Cards,
	ghosts: [dynamic]i32,
	ghosts_max: i32,
	cycle: Cycle,
}

N_DICES :: 12
EntityState :: enum {NOT_USED, DEAD, ALIVE,}
Dice :: struct {
	state: EntityState,
	using body: RigidBody,
	player: u8,
	color: rl.Color,
	current_number: i32, // which number is shown on top face
	current_score: sco,
	already_scored: bool,
	upgrades: [5]Cards,
	attack: sco,
	health: sco,
}

Particles :: struct{
	positions: [9]Vector3,
	velocities: [9]Vector3,
	color: rl.Color,
	visible: bool,
	lifetime: f32
}

TextAnimation :: struct{
	start: Vector2,
	end: Vector2,
	text: string,
	color: rl.Color,
	visible: bool,
	font_size: f32,
	lifetime: f32,
	start_lifetime: f32
}
Opponent :: struct {
	message: string,
	speaking: bool
}

GameState :: enum {
	WAIT_FOR_ROLL,
	CHARGING,
	ROLLING,
	BATTLE,
	SCORING,
	SCORING_SUMMARY,	// only for the animations (all points are flying in)
	WAIT_FOR_AI,
	GHOST_BOARD,
}

GUI :: struct {
	font_size1: f32,
	font_size2: f32,
	score_positions: [N_PLAYERS]rl.Vector2,
	hand_positions: [N_PLAYERS]rl.Vector2,
	hand_area_height: f32,
	card_size: rl.Vector2,
	ghost_positions: [N_PLAYERS]rl.Vector2,
	width: f32,
	height: f32,
	bg_color: rl.Color,
}

Cycle :: struct {
	current: i32,
	scored_combinations: bit_set[CombinationType],
}

Application :: struct {
	// resources
	font: rl.Font,
	textures: []rl.Texture2D,
	sounds: []rl.Sound,
	texts: map[string]string,
	texts_buffer: string,

	// gui
	gui: GUI,
	camera3d: rl.Camera3D,
	camera2d: rl.Camera2D,
	particles: [1000]Particles,
	text_animations: [200]TextAnimation,
	ghosts_selected: [5]i32,

	// game world
	state: GameState,
	state_timer: f32,
	players: [N_PLAYERS]Player,
	current_player: u8,
	dices: [dynamic]Dice,
	contacts: [dynamic]Contact,
	opponent: Opponent,

}
app: Application

main :: proc() {
	// Initialize window
	screen_width := rl.GetScreenWidth()
	screen_height := rl.GetScreenHeight()

	rl.InitWindow(1920, 1080, "Rolls")
	// rl.ToggleFullscreen() // Start in fullscreen mode
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	display := rl.GetCurrentMonitor();
    // if we are not full screen, set the window size to match the monitor we are on
    screen_width = rl.GetMonitorWidth(display)
    screen_height = rl.GetMonitorHeight(display)
    // rl.SetWindowState({rl.ConfigFlag.WINDOW_UNDECORATED})
    rl.SetWindowSize(screen_width, screen_height+300)

    // toggle the state
    // rl.ToggleBorderlessWindowed()
    // rl.MaximizeWindow()
    rl.SetWindowPosition(0, 30)
    rl.SetExitKey(.KEY_NULL) // we don't want the window to be closed by accident

	// screen_width = rl.GetScreenWidth()
	// screen_height = rl.GetScreenHeight()
	target_ratio := 1080 / f32(screen_height)

	app = {
		font = rl.LoadFont("assets/j_audio_cassette.otf"),
		state = .ROLLING,
		players = {
			{
				color=COLOR_PLAYERS[0], roll_multiplier=1,
				// cards={CardUpgrade_Antenna{}, CardUpgrade_Journalist{}, },
				ghosts_max=10,
			},
			{
				color=COLOR_PLAYERS[1], roll_multiplier=1,
				// cards={CardUpgrade_Journalist{}, CardUpgrade_Antenna{},},
				ghosts_max=10,
			},
		},
		opponent = {
			message = "Let's see who reaches\n1000 points first!",
			speaking = false,
		},
		ghosts_selected = {-1, -1, -1, -1, -1},
	}
	defer rl.UnloadFont(app.font)
	app.gui = {
		width = f32(screen_width),
		height = f32(screen_height),
		font_size1 = 50,
		font_size2 = 30,
		bg_color = COLOR_PLAYERS[app.current_player]/2,
		score_positions = {
			{50, f32(screen_height)-150},
			{f32(screen_width)-50, f32(screen_height)-150},
		},
		card_size = {400, 170},
		hand_positions = {
			{50, 50},
			{f32(screen_width)-450, 50},
		},
		ghost_positions = {
			{50, f32(screen_height)-270},
			{f32(screen_width)-50, f32(screen_height)-270},
		},
	}
	app.gui.hand_area_height = app.gui.score_positions[0].y - 100

	CAMERA_HEIGHT: f32 = 65.0
	app.camera3d = {}
	app.camera3d.position = rl.Vector3{30, CAMERA_HEIGHT, 0.}
	app.camera3d.target = rl.Vector3{0.0, 0.0, 0.0}
	app.camera3d.up = rl.Vector3{0.0, 1.0, 0.0}
	app.camera3d.fovy = f32(30) // Camera field-of-view Y
	app.camera3d.projection = .PERSPECTIVE // Camera mode type

	app.camera2d = {}
    app.camera2d.target = {f32(screen_width)/2.0, f32(screen_height)/2.0 }
    app.camera2d.offset = {f32(screen_width)/2.0, f32(screen_height)/2.0 }
    // camera.rotation = 0.0f;
    // app.camera2d.zoom = target_ratio

	// Make some app.dices:
	dices_reset(first_round=true)


	{ // Clear everything so we don't get welcomed by a white screen
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		rl.BeginMode3D(app.camera3d)
		defer rl.EndMode3D()

		 // Draw a big cube to represent the area where the app.dices can move
		rl.DrawCube(rl.Vector3{0.0, -0.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)
	}

	rl.SetTargetFPS(60)

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	app.sounds = {
		rl.LoadSound("assets/sounds/dice_1.wav"),
		rl.LoadSound("assets/sounds/dice_2.wav"),
		rl.LoadSound("assets/sounds/dice_3.wav"),
		rl.LoadSound("assets/sounds/dice_4.wav"),
		rl.LoadSound("assets/sounds/dice_5.wav"),
		rl.LoadSound("assets/sounds/dice_elimination.wav"),
		rl.LoadSound("assets/sounds/dice_scores.wav"),
	}
	defer {
		for sound in app.sounds {
			rl.UnloadSound(sound)
		}
	}
	app.textures = {rl.LoadTexture("assets/textures/dice.png")}
	defer {
		for texture in app.textures {
			rl.UnloadTexture(texture)
		}
	}
	file, file_ok := os.read_entire_file("assets/texts.csv")
	if !file_ok{
		fmt.println("Error loading texts!")
		os.exit(1)
	}
	app.texts_buffer = string(file)
	defer delete(app.texts_buffer)
	parsing_key := true
	key_start, key_end := 0, 0
	for r, i in app.texts_buffer {
		if parsing_key && r == '|' {
			key_end = i
			parsing_key = false
		} else if !parsing_key && r == '\n' {
			key := app.texts_buffer[key_start:key_end]
			value := app.texts_buffer[key_end+1:i-1] // -1 to remove the \r before \n
			app.texts[key] = value
			key_start = i+1
			parsing_key = true
		}
	}

	// Main game loop

	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		app.state_timer += dt

		if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
			if app.state == .GHOST_BOARD {
				app.state = .WAIT_FOR_ROLL
				app.state_timer = 0.
				app.ghosts_selected = {-1, -1, -1, -1, -1}
			} else {
				// quit the game
				break
			}
		}

		if app.state == .WAIT_FOR_ROLL && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			app.state = .CHARGING
			app.state_timer = 0.
		}

		// Max power is reached after 3 seconds of charging)
		power := f32(math.min(1.0, app.state_timer / 0.25))

		if app.state == .CHARGING &&
			((app.current_player == 0 && rl.IsKeyReleased(rl.KeyboardKey.SPACE)) ||
			(app.current_player == 1 && power >= 1.0)) {
				dices_reset(power=power)
				app.state_timer = 0.0
				app.state = .ROLLING
		}

		if rl.IsKeyPressed(rl.KeyboardKey.S) {
			for dice, d in app.dices{
				if dice.state != .ALIVE do continue
				if dice.player == app.current_player do fmt.println(d, dice)
			}
		}

		// Zoom in and out:
		mouse_wheel := rl.GetMouseWheelMove()
		if mouse_wheel != 0.0 {
			app.camera3d.position.y += 200. * mouse_wheel * dt
		}

		// update app.particles:
		for &particle in app.particles{
			if !particle.visible do continue

			// Apply some damping to the velocity so the app.particles eventually stop
			particle.lifetime -= dt
			if particle.lifetime < 0.{
				particle.visible = false
				continue
			}

			for i in 0..< len(particle.positions) {
				particle.positions[i] += particle.velocities[i] * dt
				particle.velocities[i] *= 0.95
			}
		}

		// update app.text_animations:
		for &text in app.text_animations{
			if !text.visible do continue

			text.lifetime -= dt
			if text.lifetime < 0.{
				text.visible = false
				delete(text.text)
			}
		}

		if app.opponent.speaking {
			if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
				app.opponent.speaking = false
				app.state_timer = 0.0
			}
		} else {
			if app.state == .ROLLING{
				physics(dt)
				rolling(dt)
			} else if app.state == .BATTLE {
				battle(dt)
			} else if app.state == .SCORING {
				scoring(dt)
			} else if app.state == .SCORING_SUMMARY {
				scoring_summary(dt)
			} else if app.state == .WAIT_FOR_AI {
				wait_for_ai()
			}
		}

		// draw everything:
		draw(power)

		// Free the temp arena at the end of the frame
		free_all(context.temp_allocator)
	}
}

dices_reset :: proc(power:f32=1., first_round:bool=false) {
	if first_round {
		clear(&app.dices)
		for i in 0..<N_DICES {
			append(&app.dices, Dice{player=u8((i < N_DICES / 2) ? 0 : 1)})
		}
	}

	upgrades := [5]Cards{}
	// upgrades[0] = CardUpgrade_Antenna{}
	// upgrades[1] = CardUpgrade_Journalist{}

	for &dice, d in app.dices {
		half_size :f32= .75
		mass := math.pow(half_size, 3) * 8.
		position := dice.position+Vector3{0, 10, 0}
		velocity := Vector3{0, -5, 0}
		orientation := dice.orientation
		rotation := dice.rotation
		acceleration := dice.acceleration

		if dice.player == app.current_player || first_round
		{
			position := random_vector(-AREA_SIZE/8.0, AREA_SIZE/8.0)
			position.z += -AREA_SIZE/2.0
			position.y += AREA_SIZE/4.0 + 10.
			velocity := power * Vector3{
				rand.float32_range(-20, 20),
				rand.float32_range(-20, -10),
				rand.float32_range(-1, 100),
			}

			dice = {
				state=.ALIVE,
				shape=ShapeBox{half_size=half_size},
				position=position,
				velocity=velocity,
				orientation=random_orientation(),
				rotation=random_vector(-20.0, 20.0),
				acceleration=Vector3{0.0, -50.0, 0.0},
				linear_damping=0.99,
				angular_damping=0.9,
				inverse_mass=1./mass,
				can_sleep=true,
				player=dice.player,
				color=app.players[dice.player].color,
				current_number=0,
				current_score=0,
				attack=1,
				health=1,
				upgrades=upgrades
			}
		}
		body_set_awake(&dice)

		// body_clear_accumulators(&dice)
		body_set_block_inertia_tensor(&dice, dice.shape.(ShapeBox).half_size, 1./dice.inverse_mass)
		body_calculate_derived_data(&dice)
	}
}

physics :: proc(duration: real) {
	for &dice, d in app.dices{
		body_integrate(&dice, duration)
	}

	// walls and ground
	walls := []Plane{
		{direction={0.0, 1.0, 0.0}},
		{direction={1.0, 0.0, 0.0}, offset=-AREA_SIZE/2.0},
		{direction={-1.0, 0.0, 0.0}, offset=-AREA_SIZE/2.0},
		{direction={0.0, 0.0, 1.0}, offset=-AREA_SIZE/2.0},
		{direction={0.0, 0.0, -1.0}, offset=-AREA_SIZE/2.0},
	}

	clear(&app.contacts)
	for &dice, d in app.dices{
		if len(app.contacts) > 1000 do break

		collision_wall := false
		for wall in walls {
			collision_wall |= collision_detect_box_plane(&dice, wall, &app.contacts)
		}

		collision_other_dice := false
		for &other_dice, od in app.dices{
			if dice == other_dice || other_dice.state != .ALIVE do continue

			collision_other_dice |= collision_detect_box_box(&dice, &other_dice, &app.contacts)
		}

		if collision_wall && dice.motion > 0.97{
			sound := rand.choice(app.sounds[:4])
			rl.SetSoundVolume(sound, math.min(1.0, linalg.length(dice.velocity) / 140.0)) // Set volume based on bounce speed
			rl.SetSoundPitch(sound, rand.float32_range(0.7, 1.1)) // Add some random pitch variation
			rl.PlaySound(sound)
		}
		if collision_other_dice && dice.motion > 0.9 && app.state_timer > 1.0{
			sound := rand.choice(app.sounds[:4])
			rl.SetSoundVolume(sound, math.min(1.0, linalg.length(dice.velocity) / 80.0)) // Set volume based on bounce speed
			rl.SetSoundPitch(sound, rand.float32_range(1., 1.5)) // Add some random pitch variation
			rl.PlaySound(sound)
		}
	}

	if len(app.contacts) > 0 {
		if app.state != .ROLLING {
			fmt.println("Resolving", len(app.contacts), "app.contacts")
		}
		resolver := ContactResolver{
			position_iterations=i32(len(app.contacts))*16, velocity_iterations=i32(len(app.contacts))*16
		}
		contact_resolve_contacts(&resolver, app.contacts[:], duration)
	}
}

rolling :: proc(dt: real){

	for &dice, d in app.dices{
		if dice.state != .ALIVE do continue

		// Either wait until all app.dices are not moving that much anymore
		// or until enough time has past
		if dice.motion > 0.9 && app.state_timer < 5. {
			return
		}

		faces := []Vector3{
			{0, 0, 1}, // (1)
			{-1, 0, 0},
			{0, 1, 0},
			{0, -1, 0},
			{1, 0, 0},
			{0, 0,0 -1}, // 6
		}

		highest_face_height :f32= -1.
		for face, i in faces{
			height := body_get_point_in_world_space(&dice, face).y
			if height > highest_face_height {
				highest_face_height = height
				dice.current_number = i32(i)+1
			}
		}
		dice.already_scored = false
	}

	// We move to the next app.state
	app.state = .BATTLE
	app.state_timer = 0.
}

add_text :: proc{add_text_vec3, add_text_vec3_vec2, add_text_vec2}
add_text_vec3_vec2 :: proc (start: Vector3, end: rl.Vector2, text: string, color: rl.Color, lifetime:f32=2.0, font_size:f32=30) {
	start_2d := rl.GetWorldToScreen(start, app.camera3d)
	add_text_vec2(start_2d, {f32(end.x), f32(end.y)}, text, color, lifetime, font_size)
}
add_text_vec3 :: proc (start: Vector3, text: string, color: rl.Color, lifetime:f32=2.0, font_size:f32=30) {
	start_2d := rl.GetWorldToScreen(start, app.camera3d)
	add_text_vec2(start_2d, start_2d + Vector2{0, -100}, text, color, lifetime, font_size)
}
add_text_vec2 :: proc (start, end: Vector2, text: string, color: rl.Color, lifetime:f32, font_size: f32) {
	for &t in app.text_animations{
		if t.visible do continue

		t = {
			start = start,
			end = end,
			text = text,
			color = color,
			start_lifetime = lifetime,
			lifetime = lifetime,
			visible = true,
			font_size=font_size,
		}
		return
	}
}

dice_kills :: proc(killer, victim: ^Dice){
	add_particles(victim.position, victim.color)
	add_text(victim.position, fmt.aprint("GHOST!"), victim.color, 1.5, font_size=app.gui.font_size2)

	victim.state = .DEAD
	victim.position.y = 1000.

	player := &app.players[victim.player]
	if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
	append(&player.ghosts, victim.current_number)

	app.players[killer.player].roll_kills += 1
}

battle :: proc(dt: real) {
	if app.state_timer < 0.3 do return

	// We eliminate all app.dices from each player that show the same numbers.
	// E.g. if player 1 has two app.dices showing a 3 and player 2 has one dice showing a 3,
	// one dice each is eliminated and won't give points to either player.

	for &dice, d in app.dices{
		if dice.state != .ALIVE do continue

		for &other_dice, o in app.dices{
			if d == o || other_dice.state != .ALIVE || dice.player == other_dice.player do continue
			if dice.current_number == other_dice.current_number {
				dice.health = math.max(dice.health-other_dice.attack, 0)
				other_dice.health = math.max(other_dice.health-dice.attack, 0)

				if other_dice.health == 0{
					dice_kills(&dice, &other_dice)
				} else {
					add_text(other_dice.position, fmt.aprint("HIT!"), other_dice.color, 1.5, font_size=app.gui.font_size2)
				}

				if dice.health == 0{
					dice_kills(&other_dice, &dice)
				} else  {
					add_text(dice.position, fmt.aprint("HIT!"), dice.color, 1.5, font_size=40)
				}

				sound := app.sounds[5]
				rl.SetSoundVolume(sound, rand.float32_range(0.8, 1.)) // Set volume based on bounce speed
				rl.SetSoundPitch(sound, 0.1+f32(app.players[dice.player].roll_kills)/f32(len(app.dices)/2.)) // Add some random pitch variation
				rl.PlaySound(sound)

				// we make a small dramatic pause...
				app.state_timer = 0.0
				return
			}
		}
	}

	// We move to the next app.state
	app.state = .SCORING
	app.state_timer = 0.0
}

scoring :: proc(dt: real) {
	n_dices_alive := 0
	for dice in app.dices {
		if dice.state == .ALIVE	do n_dices_alive += 1
	}

	if n_dices_alive != 0 && app.state_timer < 2.0/f32(n_dices_alive) do return	// some pauses for counting
	app.state_timer = 0.0

	// First round of scoring, every dice calculates its own current score
	// n_dices_player := [N_PLAYERS]i32{}
	// for &dice, i in app.dices{
	// 	if dice.state != .ALIVE do continue
	// 	n_dices_player[dice.player] += 1
	// }

	for &player, p in app.players{
		player.is_scoring = true
		for &dice, i in app.dices {
			if dice.state != .ALIVE || dice.already_scored || u8(p) != dice.player do continue

			dice.current_score = sco(dice.current_number)

			// Apply dice card effects
			for upgrade, i in dice.upgrades{
				#partial switch u in upgrade {
				case CardUpgrade_Antenna:
					if player.roll_antennas == 0 {
						player.roll_antennas = dice.current_score
					} else {
						player.roll_antennas *= dice.current_score
					}

					dice.current_score = 0
				}

				if upgrade == nil do continue

				position := dice.position - f32(i) * Vector3{0, 2, 0}
				title_id := fmt.tprintf("title/%v", reflect.union_variant_type_info(upgrade))
				text := fmt.aprintf("%v!", app.texts[title_id])
				add_text(position, text, dice.color, 1.5, font_size=app.gui.font_size2)
			}

			app.players[dice.player].roll_score += dice.current_score
			dice.already_scored = true

			sound := app.sounds[6]
			rl.SetSoundVolume(sound, 1.)
			pitch :f32= (p == 0) ? 1.1 : 0.6
			pitch += rand.float32_range(-0.2, 0.2)
			rl.SetSoundPitch(sound, pitch)
			rl.PlaySound(sound)

			// add_particles(dice.position, dice.color)
			if dice.current_score != 0 {
				add_text(dice.position, app.gui.score_positions[p],
						 fmt.aprintf("+%v", dice.current_score), dice.color, 2.0/f32(n_dices_alive), font_size=app.gui.font_size1)
			}

			return
		}
		player.is_scoring = false
	}

	app.state = .SCORING_SUMMARY
	app.state_timer = 0
}

scoring_summary :: proc(dt: real) {
	if app.state_timer < 0.4 do return	// some pauses for counting

	for &player, i in app.players {
		player.roll_score += player.roll_antennas
		player.roll_score *= player.roll_multiplier

		player.total_score += player.roll_score
		player.roll_score = 0
		player.roll_multiplier = 1
		player.roll_antennas = 0
		player.roll_kills = 0
	}

	app.current_player = (app.current_player + 1) % N_PLAYERS

	app.state = .WAIT_FOR_AI
	app.state_timer = 0
}

wait_for_ai :: proc(){
    // Some actions that the AI could do...
    ai := &app.players[1]

    if len(ai.ghosts) < 5 {
		app.state = .WAIT_FOR_ROLL
		app.state_timer = 0
		return
    }

     // @TODO: how do we find the best selection of dices?
    indices := [dynamic]i32{}
    for i in 0..<len(ai.ghosts) do append(&indices, i32(i))
    rand.shuffle(indices[:])
    best_dices := [5]i32{}
    for index, i in indices[:5] do best_dices[i] = ai.ghosts[index]

    best_score := 0.
    best_combo :CombinationType= .None
    highlighted := [5]bool{}

	for combo_type, c in CombinationType{
		if combo_type == .None do continue

		match, score := test_combination(combo_type, best_dices[:], &highlighted)
		if match && score > best_score {
			best_score = score
			best_combo = combo_type
		}
	}

	// Only use ghosts if we expect a high score or if we might lose our ghosts...
	if best_score > 0. && (best_score > 20 || len(ai.ghosts) > 7){
		ai.roll_score += best_score // @TODO: Add it to roll score
		ghosts_copy := make([dynamic]i32, len(ai.ghosts), cap(ai.ghosts))
		defer delete(ghosts_copy)
		copy(ghosts_copy[:], ai.ghosts[:])
		clear(&ai.ghosts)

		for ghost, index in ghosts_copy{
			if !contains(indices[:5], i32(index)) do append(&ai.ghosts, ghost)
		}
	}

	delete(indices)

    app.state = .WAIT_FOR_ROLL
	app.state_timer = 0
}

draw :: proc(power: f32) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	if app.state == .WAIT_FOR_ROLL{
		ratio := app.state_timer / 3.
		color1, color2 := COLOR_PLAYERS[app.current_player], COLOR_PLAYERS[(app.current_player+1)%N_PLAYERS]
		app.gui.bg_color = rl.ColorLerp(color2/2, color1/2, ratio)
	}
	rl.ClearBackground(app.gui.bg_color)

	rl.BeginMode3D(app.camera3d)

	// Draw a big cube to represent the area where the app.dices can move
	rl.DrawCube(rl.Vector3{0.0, -.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)
	rl.DrawCubeWires(rl.Vector3{0.0, -.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, rl.BLACK)

	for &dice, d in app.dices{
		if dice.state != .ALIVE do continue

		draw_dice(dice, app.textures[0])
	}
	size :f32= 0.35
	for particle in app.particles{
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
	rl.EndMode3D()

	// rl.BeginMode2D(app.camera2d)

	rl.DrawFPS(10, 10)

	screen_height := f32(rl.GetScreenHeight())
	screen_width := f32(rl.GetScreenWidth())
	mouse_pos := rl.GetMousePosition()

	for player, p in app.players{
		for card, c in player.cards{
			position := app.gui.hand_positions[p]
			if len(player.cards) > 5 {
				position += {0, app.gui.hand_area_height/f32(len(player.cards))*f32(c)}
			} else {
				position += {0, f32(c)*(30+app.gui.card_size.y)}
			}
			draw_card(reflect.union_variant_typeid(card), position)
		}

		ghost_cols := 5 // @TODO: make this dynamic based on the max number of ghosts a player can have
		ghost_size :f32= app.gui.font_size1
		ghost_padding :f32= 2
		for ghost_number, i in player.ghosts{
			row := i / ghost_cols
			col := i % ghost_cols
			if p == 1 do col *= -1	// flip the ghosts for the right player
			position := app.gui.ghost_positions[p] + (ghost_size+ghost_padding)*rl.Vector2{f32(col), f32(row)}
			if p == 1 do position.x -= ghost_size+ghost_padding	// shift the right player's ghosts to the left

			clickable := app.state == .WAIT_FOR_ROLL && p == 0
			if dice_button(ghost_number, position, ghost_size, player.color/2, active_color=player.color, clickable=clickable) {
				app.state = .GHOST_BOARD
			}
		}

		text := fmt.tprintf("%v", player.total_score)
		position := app.gui.score_positions[p]

		width := measure_text(text, app.gui.font_size1).x
		if p == 1{
			// Shift the right player's score so it is always 100 pixels from the right side
			position.x -= width
		}

		draw_text(text, {position.x, position.y+50}, app.gui.font_size1, player.color)

		if app.state == .SCORING || app.state == .SCORING_SUMMARY || player.roll_score > 0. {

			font_size := app.gui.font_size1
			player_roll_score := (player.roll_score+player.roll_antennas)*player.roll_multiplier
			if player.is_scoring && player_roll_score != 0. {
				font_size += math.max((0.3-app.state_timer), 0.1) * 100
			}
			text = fmt.tprintf("+%v", player_roll_score)

			if p == 1{
				// Shift the right player's score so it is always 100 pixels from the right side
				position.x = screen_width-measure_text(text, font_size).x- 50
			}

			draw_text(text, position, font_size, player.color,)
		}
	}

	for text in app.text_animations{
		if !text.visible do continue

		x := math.lerp(text.start.x, text.end.x, 1.-text.lifetime/text.start_lifetime)
		y := math.lerp(text.start.y, text.end.y, 1.-text.lifetime/text.start_lifetime)
		draw_text(text.text, {x+2, y+2}, text.font_size+1, rl.BLACK)
		draw_text(text.text, {x, y}, text.font_size, text.color)
	}

	if app.opponent.speaking {
		fs := app.gui.font_size1
		width :=measure_text(app.opponent.message, fs).x
		draw_text(app.opponent.message,
			{screen_width/2. - width/2., screen_height/2.}, fs, rl.RAYWHITE
		)
	}

	if app.state == .CHARGING && app.current_player == 0 {
		// Draw a power bar at the center of the screen
		width: f32 = 800.
		height: f32 = 80.
		x := (f32(screen_width) - width) / 2.
		y := (f32(screen_height) - height) / 2.
		rl.DrawRectangleV({x, y}, {power * width, height}, app.players[0].color)
		rl.DrawRectangleLinesEx({x, y, width, height}, 2., rl.BLACK)
	}

	if app.state == .GHOST_BOARD {
		board_size := rl.Vector2{920, screen_height-150}
		board_position := rl.Vector2{(screen_width-board_size.x)/2., 50}
		board_color := COLOR_PLAYERS[0]/2
		board_color.a = 255
		// rl.DrawRectangleV(board_position, board_size, app.gui.bg_color)
		player := app.players[0]

		draw_box(board_position, board_size, fill=board_color)

		ghost_cols := 10 // @TODO: make this dynamic based on the max number of ghosts a player can have
		ghost_size :f32= app.gui.font_size1
		ghost_padding :f32= 2
		for ghost_number, ghost_index in player.ghosts{
			row := ghost_index / ghost_cols
			col := ghost_index % ghost_cols
			position := board_position + {20, 60} + (ghost_size+ghost_padding)*rl.Vector2{f32(col), f32(row)}
			active := contains(app.ghosts_selected[:], i32(ghost_index))

			if dice_button(ghost_number, position, ghost_size, player.color/2, active_color=player.color, active=active, clickable=true) {
				free_index := -1
				for &slot, s in app.ghosts_selected{
					if slot == -1 && free_index == -1 {
						free_index = s
					}
					if slot == i32(ghost_index) {
						slot = -1 // deselect if already selected
						free_index = -1
						break
					}
				}
				if free_index != -1 {
					app.ghosts_selected[free_index] = i32(ghost_index)
				}

			}
		}
		highlighted := [5]bool{}
		ghost_selected_numbers := [5]i32{}
		for i, ghost_index in app.ghosts_selected{
			if i == -1 do break

			ghost_selected_numbers[ghost_index] = app.players[0].ghosts[i]
		}
		enough_ghosts := !contains(app.ghosts_selected[:], i32(-1))
		ghost_size2 :f32= app.gui.font_size2 + 10
		highest_score := 0.
		// highest_combo := CombinationType_None
		for combo_type, c in CombinationType{
			if combo_type == .None do continue

			position := board_position + rl.Vector2{20, 150 + f32(c)*app.gui.font_size2*1.6}
			match, score := test_combination(combo_type, ghost_selected_numbers[:], &highlighted)
			already_scored := combo_type in player.cycle.scored_combinations
			draw_text(fmt.tprintf("%v", combo_type), position, app.gui.font_size2, (match && !already_scored) ? rl.RAYWHITE : rl.GRAY, strikethrough=already_scored)
			if !already_scored && match && enough_ghosts {
				draw_text(fmt.tprintf("+%v", score), position+{600, 0}, app.gui.font_size2, rl.RAYWHITE)

				for ghost_number, g in ghost_selected_numbers{
					dice_button(ghost_number, position+{300+f32(g)*(ghost_size2+5), -7}, ghost_size2, player.color/2, active_color=player.color, active=highlighted[g], clickable=false)
				}

				if button("Score", position+{700, 0}, color=player.color/2, active_color=player.color) {
					app.players[0].cycle.scored_combinations += {combo_type}
					fmt.println("Scored combination", combo_type, "for", score, "points!")
					fmt.println(app.players[0].cycle.scored_combinations)

					app.players[0].roll_score += score // @TODO: Add it to roll score
					ghosts_copy := make([dynamic]i32, len(player.ghosts), cap(player.ghosts))
					defer delete(ghosts_copy)
					copy(ghosts_copy[:], player.ghosts[:])
					clear(&app.players[0].ghosts)

					for ghost, index in ghosts_copy{
						if !contains(app.ghosts_selected[:], i32(index)) do append(&app.players[0].ghosts, ghost)
					}
					app.ghosts_selected = {-1, -1, -1, -1, -1} // deselect everything
				}
				if match && score > highest_score {
					highest_score = score
				}
			}
			highlighted = {}
		}

		text := "There is no matching combination"
		if len(player.ghosts) < 5 {
			text = "You need at least 5 ghost dices to score combinations"
		} else if contains(app.ghosts_selected[:], i32(-1)) {
			text = fmt.tprintf("Select %v ghost dices to score combinations", count(app.ghosts_selected[:], i32(-1)))
		} else if highest_score > 0 {
			text = fmt.tprintf("Your best combination is worth %v points", highest_score)
		}
		draw_text(text, board_position + rl.Vector2{20, 20}, app.gui.font_size2, rl.RAYWHITE)
	}
}
