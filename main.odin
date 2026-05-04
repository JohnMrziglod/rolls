package game

import "core:strconv"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:os"
import "core:reflect"
import vmem "core:mem/virtual"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

sco :: f64
void :: struct{}

COLORS := []rl.Color{
	rl.LIGHTGRAY,
	rl.GRAY,
	rl.DARKGRAY,
	rl.YELLOW,
	rl.GOLD,
	rl.ORANGE,
	rl.PINK,
	rl.RED,
	rl.MAROON,
	rl.GREEN,
	rl.LIME,
	rl.DARKGREEN,
	rl.SKYBLUE,
	rl.BLUE,
	rl.DARKBLUE,
	rl.PURPLE,
	rl.VIOLET,
	rl.DARKPURPLE,
	rl.BEIGE,
	rl.BROWN,
	rl.DARKBROWN,
}

random_color :: proc(contrast_color: rl.Color) -> rl.Color{
	index := rand.int32_range(0, i32(len(COLORS)))
	color := COLORS[index]
	// make sure the color is not too similar to the contrast color:
	return color

	// r := rand.int32_range(0, 255)
	// g := rand.int32_range(0, 255)
	// b := rand.int32_range(0, 255)

	// // make sure the color is not too similar to the contrast color:
	// if math.abs(r-i32(contrast_color.r)) < 50 do r = (r + 100) % 256
	// if math.abs(g-i32(contrast_color.g)) < 50 do g = (g + 100) % 256
	// if math.abs(b-i32(contrast_color.b)) < 50 do b = (b + 100) % 256

	// return rl.Color{u8(r), u8(g), u8(b), 255}
}

AREA_SIZE :: 30.0
COLOR_BACKGROUND := rl.Color{203, 161, 53, 255}
COLOR_CARDS := [CardCategory]rl.Color{
	.NONE=rl.BLACK,
	.ROLL=rl.Color{200, 224, 193, 255},
	.DICE=rl.Color{245, 105, 96, 255},
	.CYCLE=rl.Color{106, 168, 168, 255},
}
COLOR_TABLE := rl.Color{196, 109, 94, 255}
COLOR_PLAYERS := [2]rl.Color{
	rl.Color{243, 201, 139, 255},
	rl.Color{156, 246, 246, 255},
}

N_DICES :: 12
DICE_HALF_SIZE :: 0.75
EntityState :: enum {NOT_USED, DEAD, ALIVE,}
Dice :: struct {
	state: EntityState,
	using body: RigidBody,
	player: u8,
	color1: rl.Color,	// face color (back ground)
	color2: rl.Color,	// points and borders color
	numbers: [6]i32, 	// which numbers are shown on the faces, normally 1..6 but it can be manipulated
	current_number: i32, // which number is shown on top face
	current_score: sco,
	already_scored: bool,
	upgrades: [6]Card,  // For each side is one upgrade possible:
	attack: sco,
	health: sco,
}
Antagonist :: struct {
	story_id: string,
	index: i32,
	tutorial: i32,		// step through the tutorial...
}

GameState :: enum {
	TUTORIAL,
	WAIT_FOR_ROLL,
	CHARGING,
	PRE_ROLLING,
	ROLLING,
	CARDS_BATTLE,
	DICES_BATTLE,
	DICES_SCORING,
	CARDS_SCORING,
	SCORING_SUMMARY,	// only for the animations (all points are flying in)
	WAIT_FOR_AI,
	GHOST_BOARD,
	CARDS_OFFER,
	ASSIGN_CARD,
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

RollState :: struct{
	score: sco,
	score_counter: i32,
	multiplier: sco,
	antennas: sco,
	kills: i32,
	effects: map[CardType]void,
}

N_PLAYERS :: 2
Player :: struct {
	id: u8,
	color: rl.Color,
	color2: rl.Color,
	total_score: sco,
	roll: RollState,
	is_scoring: bool,

	cards: [dynamic]Card,	// used for some roll cards
	max_lifetime_roll_cards: i32,
	ghosts: [dynamic]i32,
	ghosts_max: i32,
	ghosts_costs_per_combination: i32,
	cycle: Cycle,
	n_dices: i32,
}

Cycle :: struct {
	current: i32,
	scored_combinations: bit_set[CombinationType],
}

Camera3D :: struct{
	using raylib: rl.Camera3D,
	desired_target: rl.Vector3,
	timer: f64,
	angle: f32,
}

Application :: struct {
	// resources
	font: rl.Font,
	textures: []rl.Texture2D,
	sub_textures: map[string]Vector2,
	sounds: []rl.Sound,
	texts: map[string]string,

	// gui
	gui: GUI,
	last_mouse_position: rl.Vector2,
	camera3d: Camera3D,
	camera2d: rl.Camera2D,
	particles: [1000]Particles,
	text_animations: [200]TextAnimation,

	// game world
	state: GameState,
	state_timer: f32,
	players: [N_PLAYERS]Player,
	current_player: u8,
	dices: [dynamic]Dice,
	contacts: [dynamic]Contact,
	antagonist: Antagonist,
	cards_offer: [5]Card, // Up to five cards can be selected
	card_selected: Card,
	ghosts_selected: [5]i32,
}
app: Application

antagonist_story :: proc(story_id: string, index:i32=1){
	app.antagonist.story_id = story_id
	app.antagonist.index = index
}
antagonist_story_continue :: proc(){
	if len(app.antagonist.story_id) == 0 do return

	app.antagonist.index += 1
	text_id := fmt.aprintf("%s/%d", app.antagonist.story_id, app.antagonist.index)
	if text_id in app.texts {
		antagonist_story(app.antagonist.story_id, app.antagonist.index)
	} else {
		app.antagonist.story_id = ""
		app.antagonist.index = 0
	}
}

load_data :: proc(texts_buffer: ^string, path: string) {
	file, file_ok := os.read_entire_file(path)
	if !file_ok{
		fmt.println("Error loading texts!")
		os.exit(1)
	}
	texts_buffer ^= string(file)

	Token :: enum{Root, Section, Key, Value}
	token: Token
	expect_section_or_key := true
	section_start, section_end := 0, 0
	key_start, key_end := 0, 0
	for r, i in texts_buffer {
		if token == .Root && r == '/' {
			key_start = i
			token = .Key
		} else if token == .Key && r == '=' {
			key_end = i // we don't need the =
			token = .Value
		} else if token == .Value && r == '\n' {
		    section := texts_buffer[section_start:section_end]
			local_key := texts_buffer[key_start+1:key_end]
			global_key := strings.join({section, local_key}, "/")
			value := texts_buffer[key_end+2:i-2] // +2 for =", -2 to remove " and the \r before \n
			if texts_buffer[key_end+1] == '"' {
			    app.texts[global_key] = value
			} else if texts_buffer[key_end+1] == '[' && local_key == "texture_id"{
			    values := strings.split(value, ",", context.temp_allocator)
				x_coord, x_ok := strconv.parse_int(values[0])
				y_coord, y_ok := strconv.parse_int(values[1])
				if x_ok && y_ok {
                    app.sub_textures[section] = {
                        f32(x_coord),
                        f32(y_coord),
                    }
				} else {
				    fmt.println("Error parsing texture coordinates for ", section)
				}
            } else {
                fmt.printfln("Warning: value for key %s in section %s is neither a string nor a texture id:\n%s", local_key, section, value)
            }


			token = .Root
		} else if token == .Section && r == '\n'{
			section_end = i-1
			token = .Root
		} else if token == .Root && !strings.is_space(r) {
			section_start = i
			token = .Section
		}
	}
}

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
	target_ratio := 1080 / f32(screen_height)

	app = {
		// font = rl.LoadFont("assets/j_audio_cassette.otf"),
		font = rl.LoadFont("assets/fonts/Paperlogy-6SemiBold.ttf"),
		state = .PRE_ROLLING,
		players = {
			{
				color=COLOR_PLAYERS[0], id=0, n_dices=6,
				ghosts_max=10, ghosts_costs_per_combination=5,
				max_lifetime_roll_cards=2,
			},
			{
				color=COLOR_PLAYERS[1], id=1, n_dices=6,
				ghosts_costs_per_combination=5, ghosts_max=10,
				max_lifetime_roll_cards=2,
			},
		},
		ghosts_selected = {-1, -1, -1, -1, -1},
	}
	defer rl.UnloadFont(app.font)
	app.gui = {
		width = f32(screen_width),
		height = f32(screen_height),
		font_size1 = 50*1.,
		font_size2 = 30*1.,
		bg_color = COLOR_PLAYERS[0]/2,
		score_positions = {
			{50, f32(screen_height)-200},
			{f32(screen_width)-50, f32(screen_height)-200},
		},
		card_size = {500, 200},
		hand_positions = {
			{50, 50},
			{f32(screen_width)-450, 50},
		},
		ghost_positions = {
			{50, f32(screen_height)-320},
			{f32(screen_width)-50, f32(screen_height)-320},
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
		// rl.DrawCube(rl.Vector3{0.0, -0.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)
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
		rl.LoadSound("assets/sounds/dice_scores_1.wav"),
		rl.LoadSound("assets/sounds/dice_scores_2.wav"),
		rl.LoadSound("assets/sounds/dice_scores_3.wav"),
		rl.LoadSound("assets/sounds/dice_scores_4.wav"),
		rl.LoadSound("assets/sounds/card_activate.wav"),
		rl.LoadSound("assets/sounds/card_discard.wav"),
		rl.LoadSound("assets/sounds/button.wav"),
	}
	defer {
		for sound in app.sounds {
			rl.UnloadSound(sound)
		}
	}
	app.textures = {rl.LoadTexture("assets/textures/die.png")}
	defer {
		for texture in app.textures {
			rl.UnloadTexture(texture)
		}
	}

	files: [2]string
	load_data(&files[0], "assets/cards.toml")
	load_data(&files[1], "assets/antagonist.toml")
	defer {
		for file in files do defer delete(file)
	}
	fmt.println("Loaded texts: ", app.sub_textures)

	app.antagonist.tutorial = 2
	// antagonist_story("antagonist_intro1")

	// Main game loop
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		app.state_timer += dt

		app.camera3d.target = linalg.lerp(app.camera3d.target, app.camera3d.desired_target, f32(dt)*5)

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

		if rl.IsKeyPressed(rl.KeyboardKey.G){
			app.cards_offer = {}
			cards_generate(app.cards_offer[:5], .RollAndDiceCards)
			state_switch(.CARDS_OFFER)
		}
		if rl.IsKeyPressed(rl.KeyboardKey.H){
			app.cards_offer = {}
			cards_generate(app.cards_offer[:5], .CycleCards)
			state_switch(.CARDS_OFFER)
		}

		if app.state == .WAIT_FOR_ROLL && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			state_switch(.CHARGING)
		}

		// Max power is reached after 3 seconds of charging)
		power := f32(math.min(1.0, app.state_timer / 0.25))

		if app.state == .CHARGING &&
			((app.current_player == 0 && (rl.IsKeyReleased(rl.KeyboardKey.SPACE) || rl.IsMouseButtonReleased(.LEFT))) ||
			(app.current_player == 1 && power >= 1.0)) {
				dices_reset(power=power)
				app.state_timer = 0.0
				app.state = .PRE_ROLLING
		}

		// Zoom in and out:
		mouse_wheel := rl.GetMouseWheelMove()
		if mouse_wheel != 0.0 {
			app.camera3d.position.y += 200. * mouse_wheel * dt
		}

		if rl.IsMouseButtonDown(.MIDDLE){
			// app.camera_rotat
			delta := rl.GetMouseDelta()
			app.camera3d.angle += (delta.x+delta.y) * math.RAD_PER_DEG * dt * 5
			app.camera3d.position = {math.cos(app.camera3d.angle)*30., app.camera3d.position.y, math.sin(app.camera3d.angle)*30.}
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

		for &player, i in app.players {
			for &card, c in player.cards{
				card.triggered -= dt
				if card.triggered < 0. do card.triggered = 0.
			}
		}

		if len(app.antagonist.story_id) > 0 {
			if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
				antagonist_story_continue()
			}
		} else {
			#partial switch app.state{
			case .PRE_ROLLING:
				apply_dice_upgrades(dt)
				state_switch(.ROLLING)
			case .ROLLING:
				physics(dt)
				rolling(dt)
			case .CARDS_BATTLE:
				cards_battle(dt)
			case .DICES_BATTLE:
				dices_battle(dt)
			case .DICES_SCORING:
				dices_scoring(dt)
			case .CARDS_SCORING:
				cards_scoring(dt)
			case .SCORING_SUMMARY:
				scoring_summary(dt)
			case .WAIT_FOR_AI:
				wait_for_ai()
			case .WAIT_FOR_ROLL:
				if len(app.antagonist.story_id) == 0 && app.antagonist.tutorial == 0 {
					app.antagonist.tutorial += 1
					antagonist_story("antagonist_intro2")
				}
			}
		}

		// draw everything:
		draw(power)

		// Free the temp arena at the end of the frame
		free_all(context.temp_allocator)
	}
}

dice_init :: proc(dice: ^Dice, position:=Vector3{0, 1000, 0}){
	half_size :f32= DICE_HALF_SIZE
	mass := math.pow(half_size, 3) * 8.
	orientation := dice.orientation
	rotation := dice.rotation
	acceleration := dice.acceleration

	dice ^= {
		state=.DEAD,
		shape=ShapeBox{half_size=half_size},
		position=position,
		velocity=dice.velocity,
		orientation=random_orientation(),
		rotation=random_vector(-20.0, 20.0),
		acceleration=Vector3{0.0, -50.0, 0.0},
		linear_damping=0.99,
		angular_damping=0.9,
		inverse_mass=1./mass,
		can_sleep=true,
		player=dice.player,
		color1=dice.color1,
		color2=dice.color2,
		current_number=0,
		current_score=0,
		attack=1,
		health=1,
		upgrades=dice.upgrades,
		numbers={1, 2, 3, 4, 5, 6},
	}
}

dices_reset :: proc(power:f32=1., first_round:bool=false) {
	if first_round {
		clear(&app.dices)
		for player, p in app.players{
			for i in 0..<player.n_dices {
				append(&app.dices, Dice{player=player.id, color1=player.color, color2=rl.BLACK})
			}
		}
	}

	for &dice, d in app.dices {
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

			dice_init(&dice, position)
			dice.state = .ALIVE
			dice.velocity = velocity
		}
		body_set_awake(&dice)

		// body_clear_accumulators(&dice)
		body_set_block_inertia_tensor(&dice, dice.shape.(ShapeBox).half_size, 1./dice.inverse_mass)
		body_calculate_derived_data(&dice)
	}
}

apply_dice_upgrades :: proc(dt: real){
	for &dice, d in app.dices{
		for &upgrade, u in dice.upgrades{
			#partial switch upgrade.type {
			case .CardDice_Optimist:
				for n, i in dice.numbers{
					dice.numbers[i] = n < 6 ? n+1 : n
				}
			case .CardDice_Pessimist:
				for n, i in dice.numbers{
					dice.numbers[i] = n > 1 ? n-1 : n
				}
			}
		}
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
				dice.current_number = dice.numbers[i]
			}
		}
		dice.already_scored = false
	}

	// We move to the next app.state
	state_switch(.CARDS_BATTLE)
}

cards_battle :: proc (dt: real) {
	if app.state_timer < 0.5 do return	// some pauses for counting
	app.state_timer = 0.0

	for &player, p in app.players {
		player.roll.effects = {}
		other_player := &app.players[(p+1)%N_PLAYERS]

		for &card, c in player.cards{
			if !card.active || card.already_scored do continue

			player.roll.effects[card.type] = {}

			position := app.gui.hand_positions[p]+app.gui.card_size/2.
			if len(player.cards) > 5 {
				position.y += app.gui.hand_area_height/f32(len(player.cards))*f32(c)
			} else {
				position.y += f32(c)*(30+app.gui.card_size.y)
			}
			#partial switch card.type {
			case .CardRoll_Attack:
				for &dice, d in app.dices{
					if dice.state != .ALIVE || dice.player != u8(p) do continue
					dice.attack += 2
					add_text(dice.position, fmt.aprint("+2 ATTACK"), COLOR_CARDS[card.category], lifetime=0.6)
				}
			case .CardRoll_Defense:
				for &dice, d in app.dices{
					if dice.state != .ALIVE || dice.player != u8(p) do continue
					dice.health += 2
					add_text(dice.position, fmt.aprint("+2 HEALTH"), COLOR_CARDS[card.category], lifetime=0.6)
				}
			case .CardRoll_Doppelgeist:
				ghosts := player.ghosts
				for ghost in ghosts{
					if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
					append(&player.ghosts, ghost)
				}
				slice.sort(player.ghosts[:])
			case .CardRoll_GraveRoll:
				if len(player.ghosts) > 0{
					for &ghost in player.ghosts{
						ghost = rand.int32_range(1, 7)
					}
					slice.sort(player.ghosts[:])
					add_text(position, fmt.aprint("REROLLED YOUR GHOSTS!"), player.color, lifetime=1.)
				} else {
					add_text(position, fmt.aprint("NO GHOSTS TO REROLL!"), player.color, lifetime=1.)
				}
			case .CardRoll_GhostHour:
				ghost_score: sco
				for ghost in player.ghosts do ghost_score += sco(ghost)
				player.roll.score += ghost_score
				add_text(position, fmt.aprintf("+%.f FROM GHOSTS!", ghost_score), COLOR_CARDS[card.category], lifetime=1.)
			case .CardRoll_HappyHour:
				player.roll.multiplier += 3
				add_text(position, fmt.aprint("ROLL SCORE X3"), player.color, lifetime=1.)
			case .CardRoll_MarketCrash:
				for &dice, d in app.dices{
					for &upgrade, u in dice.upgrades{
						position := dice.position - f32(u) * Vector3{0, 2, 0}
						text: string

						#partial switch upgrade.type {
						case .CardDice_Investor:
							upgrade.var1 *= 0.5
							add_text(dice.position, fmt.aprint("MARKET CRASH: LOSING 50%"), COLOR_CARDS[card.category], lifetime=0.6)
						}
					}
				}
			case .CardRoll_TombRaider:
				if len(other_player.ghosts) == 0 {
					add_text(position, fmt.aprint("NO GHOSTS TO STEAL"), COLOR_CARDS[card.category], lifetime=1.)
				} else {
					if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
					index_stolen := rand.int32_range(0, i32(len(other_player.ghosts)))
					append(&player.ghosts, other_player.ghosts[index_stolen])
					ordered_remove(&other_player.ghosts, index_stolen)
					add_text(position, fmt.aprint("STEALING GHOSTS!"), COLOR_CARDS[card.category], lifetime=1.)
				}
				// Sort the ghost dices (makes other things easier later on also for the human player)
				slice.sort(player.ghosts[:])
			case:
				continue
			}

			player.roll.score_counter += 1

			sound := app.sounds[6]
			rl.StopSound(sound)
			rl.SetSoundVolume(sound, 1.)
			pitch :f32= 1.0 + ((p == 0) ? 0.1 : -0.1) * f32(player.roll.score_counter)
			rl.SetSoundPitch(sound, pitch)
			rl.PlaySound(sound)

			card.triggered = 1.0
			card.already_scored = true
			card.lifetime -= 1
			if card.lifetime <= 0 {
				card_discard(&player, i32(c))
				// It is import that we return afterwards, otherwise we might get in trouble with the indices...
			}
			return
		}
	}

	state_switch(.DICES_BATTLE)
}

dices_battle :: proc(dt: real) {
	if app.state_timer < 0.3 do return

	for &player, p in app.players{
		if .CardRoll_Suidice in player.roll.effects{

			// Find dice with highest number
			suidice_index := -1
			suidice_number :i32= 0
			for &dice, d in app.dices{
				if dice.state != .ALIVE || dice.player != u8(p) do continue

				if dice.current_number > suidice_number {
					suidice_index = d
					suidice_number = dice.current_number
				}
			}

			if suidice_index != -1{
				suidice := &app.dices[suidice_index]

				dice_killed(suidice)
				add_text(suidice.position, fmt.aprint("SUIDICE!"), suidice.color1, 2.0, font_size=app.gui.font_size2)

				for &dice, d in app.dices{
					if dice.state != .ALIVE || dice.player == u8(p) do continue

					dice_killed(&dice, suidice)
				}
			}
		}
	}

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
					dice_killed(&other_dice, killer=&dice)
				} else {
					add_text(other_dice.position, fmt.aprint("HIT!"), other_dice.color1, 1.5, font_size=app.gui.font_size2)
				}

				if dice.health == 0{
					dice_killed(&dice, killer=&other_dice)
				} else  {
					add_text(dice.position, fmt.aprint("HIT!"), dice.color1, 1.5, font_size=40)
				}

				sound := app.sounds[5]
				rl.SetSoundVolume(sound, rand.float32_range(0.8, 1.)) // Set volume based on bounce speed
				rl.SetSoundPitch(sound, 0.1+f32(app.players[dice.player].roll.kills)/f32(len(app.dices)/2.)) // Add some random pitch variation
				rl.PlaySound(sound)

				// we make a small dramatic pause...
				app.state_timer = 0.0
				return
			}
		}
	}

	// We move to the next app.state
	app.state = .DICES_SCORING
	app.state_timer = 0.0
}

get_text :: proc{get_text_string_int, get_text_id_string}
get_text_string_int :: proc(id: string, key: i32) -> string{
	return app.texts[fmt.tprintf("%v/%d", id, key)]
}
get_text_id_string :: proc(id: any, key: string) -> string{
	return app.texts[fmt.tprintf("%v/%v", id, key)]
}

dices_scoring :: proc(dt: real) {
	n_dices_alive := 0
	for dice in app.dices {
		if dice.state == .ALIVE	do n_dices_alive += 1
	}

	wait_time :f32= 0.3 //2.0/f32(n_dices_alive)
	if n_dices_alive != 0 && app.state_timer < wait_time do return	// some pauses for counting
	app.state_timer = 0.0

	for &player, p in app.players{
		other_player := &app.players[(p+1)%N_PLAYERS]

		player.is_scoring = true
		n_alive := 0
		for dice in app.dices {
			if dice.state == .ALIVE && u8(p) == dice.player do n_alive += 1
		}

		for &dice, i in app.dices {
			if dice.state != .ALIVE || dice.already_scored || u8(p) != dice.player do continue

			dice.current_score = sco(dice.current_number)

			// Apply dice card effects
			for &upgrade, u in dice.upgrades{
				position := dice.position - f32(u) * Vector3{0, 2, 0}
				text: string

				#partial switch upgrade.type {
				case .CardDice_Antenna:
					if player.roll.antennas == 0 {
						player.roll.antennas = dice.current_score
					} else {
						player.roll.antennas *= dice.current_score
					}
					text = fmt.aprintf("ANTENNA NETWORK %.f!", dice.current_score)

					dice.current_score = 0
				case .CardDice_Journalist:
					if .CardRoll_FakeNews in player.roll.effects || .CardRoll_FakeNews in other_player.roll.effects{
						player.roll.multiplier += 0.5
						text = fmt.aprint("FAKE NEWS : X0.5!")
					} else {
						player.roll.multiplier += 2
						text = fmt.aprint("JOURNALIST: X2!")
					}
				case .CardDice_Influencer:
					if dice.current_number == 1 {
						append(&player.cards, Card{})
						cards_generate(player.cards[len(player.cards)-1:], .RollCards)
						text = fmt.aprint("INFLUENCER: +1 ROLL CARD")
					}
				case .CardDice_Engineer:
					if dice.current_number == 1 {
						append(&player.cards, Card{})
						cards_generate(player.cards[len(player.cards)-1:], .DiceCards)
						text = fmt.aprint("ENGINEER: +1 DICE CARD")
					}
				case .CardDice_Investor:
					if dice.current_number == 1 {
						text = fmt.aprintf("PAYOUT +%.f", upgrade.var1)
						dice.current_score += math.floor(upgrade.var1)
						upgrade.var1 = 0.
					} else {
						upgrade.var1 += dice.current_score
						upgrade.var1 *= 1.1
						dice.current_score = 0
						text = fmt.aprintf("INVESTING +%.1f", upgrade.var1)
					}
				case .CardDice_General:
					text = fmt.aprintf("GENERAL: +%.f!", n_alive)
					dice.current_score += sco(n_alive)
				case .CardDice_Historian:
					text = fmt.aprintf("HISTORIAN: +%.f!", upgrade.var1)
					dice.current_score += upgrade.var1
				case .CardDice_Medium:
					text = fmt.aprintf("MEDIUM: +%v!", len(player.ghosts))
					dice.current_score += sco(len(player.ghosts))
				case .CardDice_Librarian:
					text = fmt.aprintf("LIBRARIAN: +%.1f!", upgrade.var1)
					dice.current_score += upgrade.var1
				case .CardDice_PowerDice:
					text = fmt.aprintf("POWER UP: %.f X %.f!", dice.current_score, dice.current_score)
					dice.current_score *= dice.current_score
				case:
					continue
				}
				add_text(position, text, dice.color1, 2.0, font_size=app.gui.font_size2)
			}

			app.players[dice.player].roll.score += dice.current_score
			dice.already_scored = true
			player.roll.score_counter += 1

			sound := app.sounds[6]
			rl.StopSound(sound)
			rl.SetSoundVolume(sound, 1.)
			pitch :f32= 1.0 + ((p == 0) ? 0.1 : -0.1) * f32(player.roll.score_counter)
			rl.SetSoundPitch(sound, pitch)
			rl.PlaySound(sound)

			// add_particles(dice.position, dice.color1)
			if dice.current_score != 0 {
				add_text(dice.position, app.gui.score_positions[p],
						 fmt.aprintf("+%.f", dice.current_score), dice.color1, wait_time, font_size=app.gui.font_size1)
			}

			return
		}
		player.is_scoring = false
	}

	app.state = .CARDS_SCORING
	app.state_timer = 0
}

card_add_to_hand :: proc(player: ^Player, card: Card) {
	if len(player.cards) >= 10 do return
	append(&player.cards, card)
}

cards_scoring :: proc(dt: real) {
	if app.state_timer < 0.4 do return	// some pauses for counting
	app.state_timer = 0.0

	for &player, p in app.players {
		for &card, c in player.cards{
			if !card.active || card.already_scored do continue

			#partial switch card.type {
			case .CardRoll_HappyHour:
				player.roll.multiplier += 3
				position := app.gui.hand_positions[p]+app.gui.card_size/2.
				if len(player.cards) > 5 {
					position.y += app.gui.hand_area_height/f32(len(player.cards))*f32(c)
				} else {
					position.y += f32(c)*(30+app.gui.card_size.y)
				}

				add_text(position, app.gui.score_positions[p], fmt.aprint("X3"), COLOR_CARDS[card.category], lifetime=0.4)
				card.triggered = 1.0
			}

			player.roll.score_counter += 1

			sound := rand.choice(app.sounds[6:10])
			rl.SetSoundVolume(sound, 1.)
			pitch :f32= 1.0 + ((p == 0) ? 0.1 : -0.1) * f32(player.roll.score_counter)
			rl.SetSoundPitch(sound, pitch)
			rl.PlaySound(sound)

			card.triggered = 1.0
			card.already_scored = true
			card.lifetime -= 1
			if card.lifetime <= 0 {
				card_discard(&player, i32(c))
				// It is import that we return afterwards, otherwise we might get in trouble with the indices...
			}
			return
		}
	}

	app.state = .SCORING_SUMMARY
	app.state_timer = 0
}

scoring_summary :: proc(dt: real) {
	if app.state_timer < 0.4 do return	// some pauses for counting

	roll_scores := [2]sco{}
	for &player, p in app.players {
		player.roll.score += player.roll.antennas
		if player.roll.multiplier > 0. {
			player.roll.score *= player.roll.multiplier
		}

		// We delay it due to the Revenge Roll Card
		roll_scores[p] = player.roll.score
		player.roll = {}

		for &card, c in player.cards{
			card.already_scored = false
		}
	}

	if .CardRoll_Revenge in app.players[0].roll.effects && roll_scores[0] < roll_scores[1]{
		roll_scores = {roll_scores[1], roll_scores[0]}
	}
	if .CardRoll_Revenge in app.players[1].roll.effects && roll_scores[1] < roll_scores[0]{
		roll_scores = {roll_scores[1], roll_scores[0]}
	}
	for &player, p in app.players {
		player.total_score += roll_scores[p]
	}

	if app.players[0].total_score > 350{
		antagonist_story("antagonist_lost")
	} else if app.players[1].total_score > 350{
		antagonist_story("antagonist_wins")
	}

	app.current_player = (app.current_player + 1) % N_PLAYERS
	state_switch(.WAIT_FOR_AI)
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
    counter := [6]i32{}	// dice number -> count
    for ghost_number, i in ai.ghosts{
    	counter[ghost_number-1] += 1
    }
    lower_straight := slice.min(counter[:5]) > 1
    upper_straight := slice.min(counter[1:]) > 1

    best_indices := [dynamic]i32{}
    defer delete(best_indices)

    if lower_straight || upper_straight {
		// If we have a straight, we want to keep all the numbers that are part
		// of the straight and get rid of the others
		last_number :i32= 0
		for ghost_number, i in ai.ghosts{
			if ghost_number > last_number {
				append(&best_indices, i32(i))
				last_number = ghost_number
			}
		}
    } else {
    	// Choose random dices...
	    for i in 0..<len(ai.ghosts) do append(&best_indices, i32(i))
	    rand.shuffle(best_indices[:])
    }

    best_numbers := [5]i32{}
    for index, i in best_indices[:5] do best_numbers[i] = ai.ghosts[index]

    best_score := 0.
    best_combo :CombinationType= .None
    highlighted := [5]bool{}

	for combo_type, c in CombinationType{
		if combo_type == .None do continue

		match, score := test_combination(combo_type, best_numbers[:], &highlighted)
		if match && score > best_score {
			best_score = score
			best_combo = combo_type
		}
	}

	// Only use ghosts if we expect a high score or if we might lose our ghosts...
	if best_score > 0. && (best_score > 20 || len(ai.ghosts) > 7){
		ai.roll.score += best_score // @TODO: Add it to roll score
		ghosts_copy := make([dynamic]i32, len(ai.ghosts), cap(ai.ghosts))
		defer delete(ghosts_copy)
		copy(ghosts_copy[:], ai.ghosts[:])
		clear(&ai.ghosts)

		for ghost, index in ghosts_copy{
			if !contains(best_indices[:5], i32(index)) do append(&ai.ghosts, ghost)
		}
	}


    app.state = .WAIT_FOR_ROLL
	app.state_timer = 0
}

draw :: proc(power: f32) {
	human := &app.players[0]

	rl.BeginDrawing()
	defer rl.EndDrawing()

	anti_bg := rl.Color{}
	if app.state == .WAIT_FOR_ROLL{
		ratio := app.state_timer / 3.
		color1 := COLOR_PLAYERS[app.current_player]
		color2 := COLOR_PLAYERS[(app.current_player+1)%N_PLAYERS]
		app.gui.bg_color = rl.ColorLerp(color2/2, color1/2, ratio)
		anti_bg = rl.ColorLerp(color1/2, color2/2, ratio)
	} else if app.state == .ROLLING{
		app.gui.bg_color = COLOR_PLAYERS[app.current_player]/2
		anti_bg = COLOR_PLAYERS[(app.current_player+1)%N_PLAYERS]/2
	}
	rl.ClearBackground(app.gui.bg_color)

	rl.BeginMode3D(app.camera3d)

	// Draw a big cube to represent the area where the app.dices can move
	rl.DrawCube(rl.Vector3{0.0, -.6, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)
	rl.DrawCubeWires(rl.Vector3{0.0, -.6, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, rl.BLACK)

	dice_selected := -1
	dice_hovered := -1
	for &dice, d in app.dices{
		if dice.state != .ALIVE do continue
		hoverable := app.state != .ROLLING && (app.state != .ASSIGN_CARD || dice.player == 0)
		if draw_die(dice, hoverable=hoverable) {
			dice_hovered = d
			if rl.IsMouseButtonPressed(.LEFT) {
				dice_selected = d
				app.camera3d.desired_target = dice.position
			}
		}
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

	for &player, p in app.players{
		discard_card := -1
		discard_silent := false
		for &card, c in player.cards{
			position := app.gui.hand_positions[p]
			if len(player.cards) > 5 {
				position += {0, app.gui.hand_area_height/f32(len(player.cards))*f32(c)}
			} else {
				position += {0, f32(c)*(30+app.gui.card_size.y)}
			}
			actions := []string{}
			if app.state == .WAIT_FOR_ROLL {
				if card.category == .ROLL do actions = card.active ? {"DISCARD"} : {"DISCARD", "ACTIVATE"}
				else if card.category == .DICE do actions = {"DISCARD", "ASSIGN"}
				else if card.category == .CYCLE do actions = {"DISCARD", "ACTIVATE"}
			}

			action := draw_card(card, position, actions=actions)
			if app.state == .WAIT_FOR_ROLL && action == 1 {
				if card.category == .ROLL{
					card_activate(&player, &card)
				} else if card.category == .DICE {
					app.card_selected = card
					discard_card = c
					discard_silent = true
					state_switch(.ASSIGN_CARD)
				}
			} else if action == 0{
				discard_card = c
			}
		}
		if discard_card != -1 {
			card_discard(&player, i32(discard_card), silent=discard_silent)
		}

		ghost_cols :i32= 5 // @TODO: make this dynamic based on the max number of ghosts a player can have
		ghost_size :f32= app.gui.font_size1
		ghost_padding :f32= 4
		for i in 0..<player.ghosts_max {
			ghost_index := i32(i)
			row := ghost_index / ghost_cols
			col := ghost_index % ghost_cols
			if p == 1 do col *= -1	// flip the ghosts for the right player
			position := app.gui.ghost_positions[p] + (ghost_size+ghost_padding)*rl.Vector2{f32(col), f32(row)}
			if p == 1 do position.x -= ghost_size+ghost_padding	// shift the right player's ghosts to the left

			if ghost_index >= i32(len(player.ghosts)) {
				thickness :f32= 2
				draw_box(position+{2, 2}, {ghost_size-2, ghost_size-2}-thickness, fill={100, 100, 100, 120}, thickness=thickness)
				continue
			}
			ghost_number := player.ghosts[ghost_index]

			clickable := app.state == .WAIT_FOR_ROLL && p == 0
			if dice_button(ghost_number, position, ghost_size, active_color=player.color, clickable=clickable) {
				app.state = .GHOST_BOARD
				app.ghosts_selected[0] = i32(i)
			}
		}



		position := app.gui.score_positions[p]
		text := fmt.tprintf("%.f", player.total_score)
		draw_text(text, {position.x, position.y+40}, app.gui.font_size1, player.color, anchor=(p == 1) ? .RIGHT : .LEFT)

		text = (p == 0) ? "YOU" : "ANTAGONIST"
		draw_text(text, {position.x, position.y+100}, app.gui.font_size2, player.color, anchor=(p == 1) ? .RIGHT : .LEFT, overline=true)

		roll_score := player.roll.score+player.roll.antennas
		if app.state == .DICES_SCORING || app.state == .SCORING_SUMMARY || roll_score > 0. {

			font_size := app.gui.font_size1
			if player.is_scoring && roll_score > 0. {
				font_size += math.max((0.3-app.state_timer), 0.1) * 100
			}
			if player.roll.multiplier > 0 {
				text = fmt.tprintf("+ %.f X %.f", roll_score, player.roll.multiplier)
			} else {
				text = fmt.tprintf("+ %.f", roll_score)
			}

			if p == 1{
				// Shift the right player's score so it is always 50 pixels from the right side
				position.x = screen_width-measure_text(text, font_size).x- 50
			}

			draw_text(text, position, font_size, player.color,)
		}
	}

	if dice_hovered != -1 {
		dice := app.dices[dice_hovered]
		upgrades := [6]string{}
		count := 0
		for upgrade, i in dice.upgrades{
			if upgrade.type == .CardNone do continue
			upgrades[i] = get_text(upgrade.type, "title")
			count += 1
		}
		position := rl.GetMousePosition() + Vector2{10, 10}
		if count > 0 {
			text := strings.join(upgrades[:count], ", ", context.temp_allocator)
			draw_text(text, position, app.gui.font_size2, dice.color1)
		}
	}

	if len(app.antagonist.story_id) > 0 {
		// Let's the bubble get bigger and smaller to make it more dynamic, and also changes the color a bit
		time_factor := 1. + 0.05 * math.sin(f32(rl.GetTime())*5)
		font_size := app.gui.font_size1 * time_factor
		thickness :f32= 4.
		max_width :f32= 600 * time_factor
		padding :f32= 20.
		color_fill := rl.BLACK
		color_text := app.players[1].color
		message := get_text(app.antagonist.story_id, app.antagonist.index)
		size := measure_text(message, font_size, max_width=max_width) + padding
		position := Vector2{app.gui.width-40, app.gui.height - 200 } - size - padding

		rl.DrawRectangleV(position, size, color_fill)
		rl.DrawRectangleLinesEx(
			{position.x-thickness, position.y-thickness, size.x+2*thickness, size.y+2*thickness}, thickness, rl.BLACK)
		draw_text(message, position + padding/2., font_size, color_text, max_width=max_width)

		hovered := rl.CheckCollisionPointRec(mouse_pos, {x=position.x, y=position.y, width=size.x, height=size.y})
		clicked := hovered && rl.IsMouseButtonPressed(.LEFT)
		if clicked {
			antagonist_story_continue()
		}

		button_pos := position + size

		// if button(fmt.tprint("&gt;"), button_pos, font_size=app.gui.font_size2, anchor=.RIGHT, text_color=color_text, hover_motion=false) {
		// 	antagonist_story_continue()
		// }
	}

	if app.state == .CHARGING && app.current_player == 0 {
		// Draw a power bar at the center of the screen
		width: f32 = 800.
		height: f32 = 80.
		x := (f32(screen_width) - width) / 2.
		y := (f32(screen_height) - height) / 2.
		rl.DrawRectangleV({x, y}, {power * width, height}, human.color)
		rl.DrawRectangleLinesEx({x, y, width, height}, 2., rl.BLACK)
	}

	if app.state == .GHOST_BOARD {
		board_size := rl.Vector2{920, screen_height-150}
		board_position := rl.Vector2{(screen_width-board_size.x)/2., 50}
		board_color := COLOR_PLAYERS[0]/2
		board_color.a = 255

		draw_box(board_position, board_size, fill=board_color)

		ghost_cols :i32= 10 // @TODO: make this dynamic based on the max number of ghosts a player can have
		ghost_size :f32= app.gui.font_size1 + 10
		ghost_padding :f32= 5
		for i in 0..<human.ghosts_max {
			ghost_index := i32(i)
			row := ghost_index / ghost_cols
			col := ghost_index % ghost_cols
			position := board_position + {20, 70} + (ghost_size+ghost_padding)*rl.Vector2{f32(col), f32(row)}

			if ghost_index >= i32(len(human.ghosts)) {
				thickness :f32= 2
				draw_box(position+{0, 2}, {ghost_size, ghost_size-2}-thickness, fill=board_color/2, thickness=thickness)
				continue
			}

			ghost_number := human.ghosts[ghost_index]
			active := contains(app.ghosts_selected[:], i32(ghost_index))

			if dice_button(ghost_number, position, ghost_size, active_color=human.color, active=active, clickable=true) {
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

			ghost_selected_numbers[ghost_index] = human.ghosts[i]
		}
		enough_ghosts := !contains(app.ghosts_selected[:], i32(-1))
		ghost_size2 :f32= app.gui.font_size2 + 10
		highest_score := 0.
		// highest_combo := CombinationType_None
		n_scored_combos := 0
		for combo_type, c in CombinationType{
			if combo_type == .None do continue

			position := board_position + rl.Vector2{20, 150 + f32(c)*app.gui.font_size2*1.6}
			match, score := test_combination(combo_type, ghost_selected_numbers[:], &highlighted)
			already_scored := combo_type in human.cycle.scored_combinations
			if already_scored do n_scored_combos += 1
			draw_text(fmt.tprintf("%v", combo_type), position, app.gui.font_size2, (match && !already_scored) ? rl.RAYWHITE : rl.GRAY, strikethrough=already_scored)
			if !already_scored && match && enough_ghosts {
				draw_text(fmt.tprintf("+%.f", score), position+{600, 0}, app.gui.font_size2, rl.RAYWHITE)

				for ghost_number, g in ghost_selected_numbers{
					dice_button(ghost_number, position+{300+f32(g)*(ghost_size2+5), -7},
								ghost_size2, active_color=human.color,
								active=highlighted[g], clickable=false)
				}

				if button("Score", position+{700, 0}) {
					human.cycle.scored_combinations += {combo_type}
					human.roll.score += score // @TODO: Add it to roll score
					ghosts_copy := make([dynamic]i32, len(human.ghosts), cap(human.ghosts))
					defer delete(ghosts_copy)
					copy(ghosts_copy[:], human.ghosts[:])
					clear(&human.ghosts)

					ghosts_discount := 5-human.ghosts_costs_per_combination
					for ghost, index in ghosts_copy{
						if !contains(app.ghosts_selected[:], i32(index)) {
							append(&human.ghosts, ghost)
							continue
						} else if ghosts_discount > 0{
							append(&human.ghosts, ghost)
							ghosts_discount -= 1
						}
					}
					app.ghosts_selected = {}-1 // deselect everything
					app.cards_offer = {}
					cards_generate(app.cards_offer[:3], .RollAndDiceCards)
					state_switch(.CARDS_OFFER)
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
		} else if contains(app.ghosts_selected[:], i32(-1)) {
			text = fmt.tprintf("Select %v more ghost dices to score combinations", count(app.ghosts_selected[:], i32(-1)))
		} else if highest_score > 0 {
			text = fmt.tprintf("Your best combination is worth %v points", highest_score)
		}
		draw_text(text, board_position + rl.Vector2{20, 20}, app.gui.font_size2, rl.RAYWHITE)
		if button("ESC", board_position + rl.Vector2{board_size.x - 20, 20}, app.gui.font_size2, anchor=.RIGHT) {
			state_switch(.WAIT_FOR_ROLL)
			app.ghosts_selected = {-1, -1, -1, -1, -1}
		}
		if n_scored_combos == 15 {
			if button("FINISH CYCLE", board_position+board_size-{20, 70}, app.gui.font_size2, anchor=.RIGHT) {
				add_text(board_position+board_size/2.,
					fmt.aprint("CYCLE COMPLETED!"), human.color, 2.,
					font_size=app.gui.font_size1, anchor=TextAnchor.CENTER)
				human.roll.score += math.floor(human.total_score) / 10.
				app.ghosts_selected = {}-1 // deselect everything
				app.cards_offer = {}
				cards_generate(app.cards_offer[:3], .CycleCards)
				human.cycle.scored_combinations = {}
				state_switch(.CARDS_OFFER)
			}
		} else if n_scored_combos > 9{
			if button("RUSH CYCLE", board_position+board_size-{20, 70}, app.gui.font_size2, anchor=.RIGHT) {
				add_text(board_position+board_size/2.,
					fmt.aprint("CYCLE COMPLETED BY RUSHING!"), human.color, 2.,
					font_size=app.gui.font_size1, anchor=TextAnchor.CENTER)
				app.ghosts_selected = {}-1 // deselect everything
				app.cards_offer = {}
				cards_generate(app.cards_offer[:2], .CycleCards)
				human.cycle.scored_combinations = {}
				state_switch(.CARDS_OFFER)
			}
		}
	}

	// if app.state == .WAIT_FOR_AI {
	// 	text := "The antagonist is thinking..."
	// 	draw_text(text, {screen_width/2. - measure_text(text, app.gui.font_size1).x/2., screen_height/2.}, app.gui.font_size1, rl.RAYWHITE)
	// }
	if app.state == .WAIT_FOR_ROLL {
		// A button named "ROLL!" in the bottom, lower part of the screen
		text := "Press <SPACE> to continue" //app.current_player == 0 ? "ROLL!" : "ANTAGONIST ROLLS"
		if button(text, {screen_width/2., screen_height - 150}, size={300, 80}, font_size=app.gui.font_size1,
				color=app.gui.bg_color, anchor=.CENTER) {
			state_switch(.CHARGING)
		}
	}

	if app.state == .CARDS_OFFER {
		text := "Choose one of these cards"
		draw_text(text, {screen_width/2., screen_height - 150}, app.gui.font_size1, rl.RAYWHITE, anchor=.CENTER)

		for &card, c in app.cards_offer{
			if card.type == .CardNone do continue

			position := rl.Vector2{(app.gui.width-app.gui.card_size.x)/2., 300}
			position += {0, f32(c)*(30+app.gui.card_size.y)}
			actions := []string{"KEEP", "ACTIVATE"}
			if card.category == .DICE do actions = {"KEEP", "ASSIGN"}
			else if card.category == .CYCLE do actions = {"ACTIVATE"}
			action := draw_card(card, position, actions=actions)
			if action == 1 {
				if card.category == .ROLL{
					card_activate(human, &card)
					append(&human.cards, card)
					card = {}
					state_switch(.WAIT_FOR_ROLL)
				} else if card.category == .DICE {
					app.card_selected = card
					state_switch(.ASSIGN_CARD)
				}
			} else if action == 0{
				if card.category == .CYCLE {
					card_activate(human, &card)
				} else {
					append(&human.cards, card)
				}
				card = {}
				state_switch(.WAIT_FOR_ROLL)
			}
		}
	}

	if app.state == .ASSIGN_CARD {
		app.card_selected.triggered = dice_selected >= 0 ? 1. : 0.

		text := "Choose a dice to assign this card to"
		draw_text(text, {screen_width/2., screen_height - 150}, app.gui.font_size1, rl.RAYWHITE, anchor=.CENTER)
		draw_card(app.card_selected, mouse_pos - {app.gui.card_size.x/2, app.gui.card_size.y+50})

		if dice_selected >= 0 && app.dices[dice_selected].player == 0 {
			dice := &app.dices[dice_selected]
			could_upgrade := false
			for &upgrade, i in dice.upgrades{
				if upgrade.type == .CardNone {
					upgrade = app.card_selected
					card_activate(human, &upgrade)
					apply_dice_upgrades(0.)	// @FIXME: Is that good?
					app.card_selected = {}
					could_upgrade = true
					add_text(dice.position, fmt.aprintf("Upgraded to %v!", get_text(upgrade.type, "title")), dice.color1, 1.5)
					state_switch(.WAIT_FOR_ROLL)
					break
				}
			}

			if !could_upgrade {
				add_text(dice.position, fmt.aprint("Dice has no free upgrade slots!"), dice.color1, 1.5)
			}
		} else if rl.IsMouseButtonPressed(.RIGHT) {
			app.card_selected.triggered = 0.
			append(&human.cards, app.card_selected)
			app.card_selected = {}
			add_text(mouse_pos, fmt.aprint("Keep card in hand!"), rl.RAYWHITE, 1.5)
			state_switch(.WAIT_FOR_ROLL)
		}
	}

	for text in app.text_animations{
		if !text.visible do continue

		x := math.lerp(text.start.x, text.end.x, 1.-text.lifetime/text.start_lifetime)
		y := math.lerp(text.start.y, text.end.y, 1.-text.lifetime/text.start_lifetime)
		text_size := measure_text(text.text, text.font_size)
		box_position := Vector2{x-10, y-10}
		if text.anchor == .CENTER do box_position.x -= text_size.x/2.
		if text.anchor == .RIGHT do box_position.x -= text_size.x
		rl.DrawRectangleV(box_position, {text_size.x+20, text_size.y+20}, text.color/2.)
		draw_text(text.text, {x, y}, text.font_size, text.color, anchor=text.anchor)
	}
}

state_switch :: proc(new_state: GameState, timer: f32=0.) {
	app.state = new_state
	app.state_timer = timer

	if new_state == .CHARGING do app.camera3d.desired_target = {}
}
