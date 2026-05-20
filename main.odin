#+feature dynamic-literals
package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strings"
import rl "vendor:raylib"

sco :: f64
void :: struct{}

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
COLOR_SHIFT :: -0.3

CAMERA_HEIGHT :: 75.

DICE_HALF_SIZE :: 0.75
EntityState :: enum {NOT_USED, DEAD, ALIVE,}
Die :: struct {
	state: EntityState,
	using body: RigidBody,
	player: u8,
	color1: rl.Color,	// face color (back ground)
	color2: rl.Color,	// points and borders color
	faces: [6]i32, 	    // which numbers are shown on the faces, normally 1..6 but it can be manipulated
	current_face:   int, // which face/side is shown on top, from 0..5
	current_number: i32, // which number is shown on top face, depends on the numbers in .faces
	current_score: sco,
	already_scored: bool,
	upgrades: [6]Card,  // For each side is one upgrade possible:
	attack: sco,
	health: sco,
}
Antagonist :: struct {
	story_id: string,
	index: i32,
	wanted_power: f32,
	goal_score: sco,
	tutorial2: bool,
	tutorial_ghost_board: bool,
	tutorial_cards: bool,
	tutorial_cycles: bool,
}

GameState :: enum {
	EXIT,
	MENU,
	TUTORIAL,
	VICTORY,
	LOST,
	WAIT_FOR_ROLL,
	CHARGING,
	PRE_ROLLING,
	ROLLING,
	DICE_UPGRADES,
	CARDS_BATTLE,
	DICES_BATTLE,
	DICE_SCORING,
	CARDS_SCORING,
	SCORING_SUMMARY,	// only for the animations (all points are flying in)
	WAIT_FOR_AI,
	GHOST_BOARD,
	CARDS_OFFER,
	UPGRADE_DIE,
}

RollState :: struct{
	score: sco,
	score_counter: i32,
	score_timer: f32,
	multiplier: sco,
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
	n_dice: i32,
}

Cycle :: struct {
	current: i32,
	scored_combinations: bit_set[CombinationType],
}

Camera3D :: struct{
	using raylib: rl.Camera3D,
	desired_target: rl.Vector3,
	desired_position: rl.Vector3,
	desired_fovy: f32,
	timer: f64,
	angle: f32,
	trauma: f32,
}

BattleState :: enum{Over, Fighting, Retreating}
Battle :: struct {
    dice: [2]^Die,
    previous_positions: [2]Vector3,
    timer: f32,
    state: BattleState,
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
Application :: struct {
	// resources
	font: rl.Font,
	textures: []rl.Texture2D,
	sub_textures: map[string]Vector2,
	sounds: []rl.Sound,
	musics: []rl.Music,
	texts: map[string]string,

	// gui
	gui: GUI,
	last_mouse_position: rl.Vector2,
	camera3d: Camera3D,
	camera2d: rl.Camera2D,
	particles: [1000]Particles,
	animations: [200]Animation,

	// game world
	state: GameState,
	state_before: GameState,
	state_timer: f32,
	state_clock: f32,
	players: [N_PLAYERS]Player,
	current_player: u8,
	dice: [dynamic]Die,
	contacts: [dynamic]Contact,
	battle: Battle,
	antagonist: Antagonist,
	cards_offer: [5]Card, // Up to five cards can be selected
	card_selected: Card,
	ghosts_selected: [5]i32,
	die_selected: i32,
	power: f32,
}
app: Application

Config :: struct {
	game_speed: f32
}
config: Config

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

camera_shake :: proc(intensity: f32, duration: f32) {
	app.camera3d.trauma = math.max(app.camera3d.trauma, intensity)
	app.camera3d.timer = 0.
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
    rl.SetWindowState({.WINDOW_UNDECORATED, .BORDERLESS_WINDOWED_MODE})
    rl.SetWindowSize(screen_width, screen_height+300)
    rl.SetTargetFPS(60)

    // toggle the state
    // rl.ToggleBorderlessWindowed()
    // rl.MaximizeWindow()
    // rl.SetWindowPosition(0, 30)
    rl.SetExitKey(.KEY_NULL) // we don't want the window to be closed by accident
	target_ratio := 1080 / f32(screen_height)

	app = {
		// font = rl.LoadFont("assets/j_audio_cassette.otf"),
		font = rl.LoadFont("assets/fonts/Paperlogy-6SemiBold.ttf"),
		state = .MENU,
		state_before = .PRE_ROLLING,
		players = {
			{
				color=COLOR_PLAYERS[0], id=0, n_dice=6,
				ghosts_max=10, ghosts_costs_per_combination=5,
				max_lifetime_roll_cards=2, //ghosts={1, 2, 3, 4, 5}
			},
			{
				color=COLOR_PLAYERS[1], id=1, n_dice=6,
				ghosts_costs_per_combination=5, ghosts_max=10,
				max_lifetime_roll_cards=2, //ghosts={1, 2, 3, 4, 5}
			},
		},
		ghosts_selected = {-1, -1, -1, -1, -1},
		die_selected = -1,
	}
	defer rl.UnloadFont(app.font)
	rl.GenTextureMipmaps(&app.font.texture)
	rl.SetTextureFilter(app.font.texture, .TRILINEAR)

	app.gui = {
		width = f32(screen_width),
		height = f32(screen_height),
		font_size1 = 50*1.,
		font_size2 = 30*1.,
		bg_color = rl.ColorBrightness(COLOR_PLAYERS[0], COLOR_SHIFT),
		score_positions = {
			{50, f32(screen_height)-200},
			{f32(screen_width)-50, f32(screen_height)-200},
		},
		hand_positions = {
			{50, 50},
			{f32(screen_width)-50-CARD_SIZE.x, 50},
		},
		ghost_positions = {
			{50, f32(screen_height)-320},
			{f32(screen_width)-50, f32(screen_height)-320},
		},
	}
	app.gui.hand_area_height = app.gui.score_positions[0].y - 100

	app.textures = {
		rl.LoadTexture("assets/textures/die.png"),
		rl.LoadTexture("assets/textures/title.png"),
	}
	for &texture in app.textures{
		rl.GenTextureMipmaps(&texture)
		rl.SetTextureFilter(texture, .TRILINEAR)
	}
	defer {
		for texture in app.textures {
			rl.UnloadTexture(texture)
		}
	}
	menu(loading=true)

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
	music_files, music_files_ok := os.glob("C:/projects/rolls/assets/music/*.mp3", context.temp_allocator)
	if music_files_ok != nil{
		fmt.panicf("%v", music_files_ok)
		// os.exit(1)
	}
	current_music_file := strings.clone_to_cstring(rand.choice(music_files[:]))
	fmt.printfln("Playing music: %s", current_music_file)
	defer delete(current_music_file)
	app.musics = {
		rl.LoadMusicStream(current_music_file),
		// rl.LoadMusicStream("assets/sounds/music_2.ogg"),
	}
	rl.PlayMusicStream(app.musics[0])
	defer {
		for music in app.musics {
			rl.UnloadMusicStream(music)
		}
	}

	files: [2]string
	load_data(&files[0], "assets/cards.toml")
	load_data(&files[1], "assets/antagonist.toml")
	defer {
		for file in files do defer delete(file)
	}

	config.game_speed = 1.

	app.camera3d = {
		up={0.0, 0.0, -1.},
		projection=.ORTHOGRAPHIC,
	}
	camera_reset()

	app.camera2d = {}
    app.camera2d.target = {f32(screen_width)/2.0, f32(screen_height)/2.0 }
    app.camera2d.offset = {f32(screen_width)/2.0, f32(screen_height)/2.0 }
    // camera.rotation = 0.0f;
    // app.camera2d.zoom = target_ratio

	app.power = 2.
	dices_reset(first_round=true)

	app.antagonist.tutorial2 = true
	app.antagonist.tutorial_cards = true
	app.antagonist.tutorial_ghost_board = true
	app.antagonist.tutorial_cycles = true
	// antagonist_story("antagonist_tutorial1")

	// Main game loop
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		if (!rl.IsWindowFocused())
        {
            rl.MinimizeWindow();
            rl.BeginDrawing();
            rl.EndDrawing();
            continue;
        }

		// rl.UpdateMusicStream(app.musics[0])

		app.state_timer = max(0., app.state_timer-dt)
		app.state_clock += dt

		if app.state == .MENU{
			menu(dt)
			continue
		}
		if app.state == .EXIT{
			break
		}

		// Zoom in and out:
		// mouse_wheel := rl.GetMouseWheelMove()
		// if mouse_wheel != 0.0 {
		// 	app.camera3d.desired_position.y += 200. * mouse_wheel * dt
		// }

		if rl.IsMouseButtonDown(.MIDDLE){
			// app.camera_rotat
			delta := rl.GetMouseDelta()
			app.camera3d.angle += (delta.x+delta.y) * math.RAD_PER_DEG * dt * 5
		}

		app.camera3d.trauma = math.max(0., app.camera3d.trauma - dt*2)
		camera_target := app.camera3d.trauma*random_vector(-1, 1) + app.camera3d.desired_target
		app.camera3d.target = linalg.lerp(app.camera3d.target, camera_target, f32(dt)*5)
		camera_position := app.camera3d.desired_position + app.camera3d.trauma*random_vector(-1, 1)
		app.camera3d.position = linalg.lerp(app.camera3d.position, camera_position, f32(dt)*5)
		app.camera3d.fovy = linalg.lerp(app.camera3d.fovy, app.camera3d.desired_fovy, f32(dt)*5)

		// Update the camera
		if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
			if app.state == .GHOST_BOARD {
				state_change(.WAIT_FOR_ROLL)
				app.ghosts_selected = {-1, -1, -1, -1, -1}
			} else if app.state == .UPGRADE_DIE || app.state == .CARDS_OFFER {
				// @FIXME: we have to solve this better..
			} else {
				state_change(.MENU)
			}
		}

		if rl.IsKeyPressed(rl.KeyboardKey.F){
			app.cards_offer = {}
			cards_generate(app.cards_offer[:3], .RollAndDiceCards)
			state_change(.CARDS_OFFER)
		}
		if rl.IsKeyPressed(rl.KeyboardKey.D){
			app.cards_offer = {}
			cards_generate(app.cards_offer[:1], .RollAndDiceCards)
			state_change(.CARDS_OFFER)
		}
		if rl.IsKeyPressed(rl.KeyboardKey.G){
			app.cards_offer = {}
			cards_generate(app.cards_offer[:5], .RollAndDiceCards)
			state_change(.CARDS_OFFER)
		}
		if rl.IsKeyPressed(rl.KeyboardKey.H){
			app.cards_offer = {}
			cards_generate(app.cards_offer[:5], .CycleCards)
			state_change(.CARDS_OFFER)
		}

		if app.state == .WAIT_FOR_ROLL && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			state_change(.CHARGING)
			app.antagonist.wanted_power = rand.float32_range(0.3, 1.)
		}
		// Max power is reached after 3 seconds of charging)
		app.power = f32(math.min(1.0, app.state_clock / 0.25))
		if app.state == .CHARGING &&
			((app.current_player == 0 && (rl.IsKeyReleased(rl.KeyboardKey.SPACE) || rl.IsMouseButtonReleased(.LEFT))) ||
			(app.current_player == 1 && app.power >= app.antagonist.wanted_power)) {
				dices_reset()
				state_change(.PRE_ROLLING)
				camera_shake(2.0, 0.5)
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
		} else if app.state_timer == 0.{
			#partial switch app.state{
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
			case .DICE_SCORING:
				dice_scoring(dt)
			case .CARDS_SCORING:
				cards_scoring(dt)
			case .SCORING_SUMMARY:
				scoring_summary(dt)
			case .WAIT_FOR_AI:
				wait_for_ai()
			case .WAIT_FOR_ROLL:
				if len(app.antagonist.story_id) == 0 && !app.antagonist.tutorial2 {
					app.antagonist.tutorial2 = true
					antagonist_story("antagonist_tutorial2")
				}
			case .VICTORY:
				end_of_level(dt)
			case .LOST:
				end_of_level(dt)
			}
		}

		// draw everything:
		draw(dt)

		// Free the temp arena at the end of the frame
		free_all(context.temp_allocator)
	}
}

dice_init :: proc(die: ^Die, position:=Vector3{0, 1000, 0}){
	half_size :f32= DICE_HALF_SIZE
	mass := math.pow(half_size, 3) * 8.
	orientation := die.orientation
	rotation := die.rotation
	acceleration := die.acceleration

	die ^= {
		state=.DEAD,
		shape=ShapeBox{half_size=half_size},
		position=position,
		velocity=die.velocity,
		orientation=random_orientation(),
		rotation=random_vector(-20.0, 20.0),
		acceleration=Vector3{0.0, -50.0, 0.0},
		linear_damping=0.99,
		angular_damping=0.9,
		inverse_mass=1./mass,
		can_sleep=true,
		player=die.player,
		color1=die.color1,
		color2=die.color2,
		current_number=0,
		current_score=0,
		attack=1,
		health=1,
		upgrades=die.upgrades,
		faces={1, 2, 3, 4, 5, 6},
	}
}

dices_reset :: proc(power:f32=1., first_round:bool=false) {
	if first_round {
		clear(&app.dice)
		for player, p in app.players{
			for i in 0..<player.n_dice {
				append(&app.dice, Die{player=player.id, color1=player.color, color2=rl.BLACK})
			}
		}
	}

	for &dice, d in app.dice {
		if dice.player == app.current_player || first_round
		{
			position := random_vector(-AREA_SIZE/8.0, AREA_SIZE/8.0)
			position.z += -AREA_SIZE/2.0
			position.y += AREA_SIZE/4.0 + 10.
			velocity := app.power * Vector3{
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
	for &dice, d in app.dice{
		for &upgrade, u in dice.upgrades{
			#partial switch upgrade.type {
			case .CardDice_Optimist:
			    dice.faces = {4, 4, 5, 5, 6, 6}
			case .CardDice_Pessimist:
			    dice.faces = {1, 1, 2, 2, 3, 3}
			}
		}
	}
}

rolling :: proc(duration: real) {
	for &dice, d in app.dice{
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
	for &dice, d in app.dice{
		if len(app.contacts) > 1000 do break

		collision_wall := false
		for wall in walls {
			collision_wall |= collision_detect_box_plane(&dice, wall, &app.contacts)
		}

		collision_other_dice := false
		for &other_dice, od in app.dice{
			if dice == other_dice || other_dice.state != .ALIVE do continue

			collision_other_dice |= collision_detect_box_box(&dice, &other_dice, &app.contacts)
		}

		if collision_wall && dice.motion > 0.97{
			volume := math.min(1.0, linalg.length(dice.velocity) / 200.0)
			pitch := rand.float32_range(.7, 1.1)
			play_sound(rand.int32_range(0, 4), volume=volume, pitch=pitch)
		}
		if collision_other_dice && dice.motion > 0.9 && app.state_clock > 1.0{
			volume := math.min(1.0, linalg.length(dice.velocity) / 140.0)
			pitch := rand.float32_range(1., 1.5)
			play_sound(rand.int32_range(0, 4), volume=volume, pitch=pitch)
		}
	}

	if len(app.contacts) > 0 {
		resolver := ContactResolver{
			position_iterations=i32(len(app.contacts))*16, velocity_iterations=i32(len(app.contacts))*16
		}
		contact_resolve_contacts(&resolver, app.contacts[:], duration)
	}

	for &dice, d in app.dice{
		if dice.state != .ALIVE do continue

		// Either wait until all app.dice are not moving that much anymore
		// or until enough time has past
		if dice.motion > 0.9 && app.state_clock < 5. {
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
				dice.current_face = i
				dice.current_number = dice.faces[i]
			}
		}
		dice.already_scored = false
	}

	// We move to the next app.state
	state_change(.DICE_UPGRADES)
}

dice_upgrades :: proc (dt: real){
    for &dice, d in app.dice{
		if dice.state != .ALIVE do continue

		// Apply dice card effects
		for &upgrade, u in dice.upgrades{
			position := dice.position - f32(u) * Vector3{0, 2, 0}
			text: string

			#partial switch upgrade.type {
			case .CardDice_Assassin:
			    dice.attack += 2
				text = fmt.aprint("ASSASSIN: +2 ATTACK!")
			case .CardDice_Tank:
			    dice.health += 2.
				text = fmt.aprint("TANK: +2 HEALTH!")
			case:
				continue
			}
			add_text(position, text, dice.color1)
			wait(1.0)
		}
	}

	state_change(.CARDS_BATTLE, wait=0.5)
}

cards_battle :: proc (dt: real) {
	for &player, p in app.players {
		player.roll.effects = {}
		other_player := &app.players[(p+1)%N_PLAYERS]

		for &card, c in player.cards{
			if !card.active || card.already_scored do continue

			player.roll.effects[card.type] = {}

			position := app.gui.hand_positions[p]+CARD_SIZE/2.
			if len(player.cards) > 5 {
				position.y += app.gui.hand_area_height/f32(len(player.cards))*f32(c)
			} else {
				position.y += f32(c)*(30+CARD_SIZE.y)
			}
			#partial switch card.type {
			case .CardRoll_Attack:
				for &dice, d in app.dice{
					if dice.state != .ALIVE || dice.player != u8(p) do continue
					dice.attack += 2
					add_text(dice.position, fmt.aprint("+2 ATTACK"), COLOR_CARDS[card.category], lifetime=0.6)
				}
			case .CardRoll_Defense:
				for &dice, d in app.dice{
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
					add_text(position, fmt.aprint("REROLLED GHOSTS!"), player.color, lifetime=1.)
				} else {
					add_text(position, fmt.aprint("NO GHOSTS TO REROLL!"), player.color, lifetime=1.)
				}
			case .CardRoll_GhostHour:
				ghost_score: sco
				for ghost in player.ghosts do ghost_score += sco(ghost)
				player.roll.score += ghost_score
				add_text(position, fmt.aprintf("+%.f FROM GHOSTS!", ghost_score), COLOR_CARDS[card.category], lifetime=1.)
			case .CardRoll_HappyHour:
				player.roll.multiplier += 2
				add_text(position, fmt.aprint("ROLL SCORE X2"), player.color, lifetime=1.)
			case .CardRoll_MarketCrash:
				for &dice, d in app.dice{
					for &upgrade, u in dice.upgrades{
						position := dice.position - f32(u) * Vector3{0, 2, 0}
						text: string

						#partial switch upgrade.type {
						case .CardDice_Investor:
							upgrade.var1 *= 0.5
							add_text(dice.position, fmt.aprint("MARKET CRASH: LOSING 50%"), COLOR_CARDS[card.category])
						}
					}
				}
			case .CardRoll_Suidice:
				// Find dice with highest number
    			suidice_index := -1
    			suidice_number :i32= 0
    			for &dice, d in app.dice{
    				if dice.state != .ALIVE || dice.player != u8(p) do continue

    				if dice.current_number > suidice_number {
    					suidice_index = d
    					suidice_number = dice.current_number
    				}
    			}

    			if suidice_index != -1{
    				suidice := &app.dice[suidice_index]

    				dice_killed(suidice)
    				add_text(suidice.position, fmt.aprint("SUIDICE!"), suidice.color1)

    				for &dice, d in app.dice{
    					if dice.state != .ALIVE || dice.player == u8(p) do continue

    					dice_killed(&dice, suidice)
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

			pitch :f32= 1.0 + ((p == 0) ? 0.1 : -0.1) * f32(player.roll.score_counter)
			play_sound(6, volume=0.5, pitch=pitch)

			card.triggered = 1.0
			card.already_scored = true
			return
		}
	}

	state_change(.DICES_BATTLE, 0.3)
}

dice_battle :: proc(dt: real) {
	if app.battle.state != .Over{
	    battle := &app.battle
        battle.timer += dt
        target_time :f32= 0.3

        clash_position := (battle.previous_positions[0] + battle.previous_positions[1]) / 2.
        clash_position.y += 6.

        #partial switch battle.state{
        case .Fighting:
            for &die, d in app.battle.dice{
                die.position = linalg.lerp(battle.previous_positions[d], clash_position, battle.timer/target_time)
                body_calculate_derived_data(die)     // to update the transformation matrix, etc...
            }
            if battle.timer > target_time {
                die1 := app.battle.dice[0]
                die2 := app.battle.dice[1]
                die1.health = math.max(die1.health-die2.attack, 0)
				die2.health = math.max(die2.health-die1.attack, 0)

				if die1.health == 0{
					dice_killed(die1, killer=die2)
				} else {
					add_text(die1.position, fmt.aprint("HIT!"), die1.color1)
				}

				if die2.health == 0{
					dice_killed(die2, killer=die1)
				} else  {
					add_text(die2.position, fmt.aprint("HIT!"), die2.color1)
				}

				sound := app.sounds[5]
				rl.SetSoundVolume(sound, rand.float32_range(0.8, 1.)) // Set volume based on bounce speed
				rl.SetSoundPitch(sound, 0.1+f32(app.players[die1.player].roll.kills)/f32(len(app.dice)/2.)) // Add some random pitch variation
				rl.PlaySound(sound)

				battle.state = (die1.state == .ALIVE || die2.state == .ALIVE) ? .Retreating : .Over
				battle.timer = 0.
            }
        case .Retreating:
            for &die, d in app.battle.dice{
                if die.state == .ALIVE do continue
                die.position = linalg.lerp(die.position, battle.previous_positions[d], battle.timer/target_time)
                body_calculate_derived_data(die)     // to update the transformation matrix, etc...
            }
            if battle.timer > target_time {
                battle.state = .Over
                battle.timer = 0.
            }
        }
        return
	}

	// We eliminate all app.dice from each player that show the same numbers.
	// E.g. if player 1 has two app.dice showing a 3 and player 2 has one dice showing a 3,
	// one dice each is eliminated and won't give points to either player.

	for &dice, d in app.dice{
		if dice.state != .ALIVE do continue
		for &other_dice, o in app.dice{
			if d == o || other_dice.state != .ALIVE || dice.player == other_dice.player do continue
			if dice.current_number == other_dice.current_number {
			    dice_fight(&dice, &other_dice)
				return
			}
		}
	}

	// We move to the next app.state
	state_change(.DICE_SCORING, 0.5)
}

dice_scoring :: proc(dt: real) {
	for &player, p in app.players{
		other_player := &app.players[(p+1)%N_PLAYERS]

		player.is_scoring = true
		n_alive := 0
		for dice in app.dice {
			if dice.state == .ALIVE && u8(p) == dice.player do n_alive += 1
		}

		for &die, d in app.dice {
			if die.state != .ALIVE || die.already_scored || u8(p) != die.player do continue

			die.current_score = sco(die.current_number)

			// Apply dice card effects
			n_events := 0
			delay: f32
			duration :f32: 0.8
			for &upgrade, u in die.upgrades{
			    is_active := die.current_face == u
				text: string

				#partial switch upgrade.type {
				case .CardDice_Antenna:
					multiplier := 0.
					for other_dice, o in app.dice{
                        if d == o || other_dice.state != .ALIVE || die.player != other_dice.player do continue

                        if die_has_upgrade(other_dice, .CardDice_Antenna) {
							// add_text(other_dice.position, fmt.aprint("ANTENNA BOOST!"), COLOR_UPGRADES[.CardDice_Antenna], lifetime=0.6)
							multiplier += sco(other_dice.current_number)
						}
                    }
                    if multiplier > 0. {
  						text = fmt.aprintf("x%.f!", multiplier)
  						die.current_score *= multiplier
                    }

				case .CardDice_Journalist:
					if .CardRoll_FakeNews in player.roll.effects || .CardRoll_FakeNews in other_player.roll.effects{
						player.roll.multiplier += 0.5
						text = fmt.aprint("x0.5 ROLL SCORE")
					} else {
						player.roll.multiplier += 2
						text = fmt.aprint("x2 ROLL SCORE")
					}
				case .CardDice_Influencer:
					if is_active {
						append(&player.cards, Card{})
						cards_generate(player.cards[len(player.cards)-1:], .RollCards)
						text = fmt.aprint("+1 ROLL CARD")
					}
				case .CardDice_Engineer:
					if is_active {
						append(&player.cards, Card{})
						cards_generate(player.cards[len(player.cards)-1:], .DiceCards)
						text = fmt.aprint("+1 DICE CARD")
					}
				case .CardDice_Investor:
					if is_active {
						text = fmt.aprintf("PAYOUT +%.f", upgrade.var1)
						die.current_score += math.floor(upgrade.var1)
						upgrade.var1 = 0.
					} else {
						upgrade.var1 += die.current_score
						upgrade.var1 *= 1.1
						die.current_score = 0
						text = fmt.aprintf("SAVING %.1f", upgrade.var1)
					}
				case .CardDice_General:
					if n_alive > 1{
						text = fmt.aprintf("x%v", n_alive)
						die.current_score *= sco(n_alive)
					}
				case .CardDice_Historian:
				    if upgrade.var1 != 0. {
    					text = fmt.aprintf("+%.f", upgrade.var1)
    					die.current_score += upgrade.var1
					}
				case .CardDice_Researcher:
				    if upgrade.var1 != 0. {
    					text = fmt.aprintf("X%.f", upgrade.var1)
    					player.roll.multiplier += upgrade.var1
					}
				case .CardDice_Medium:
					text = fmt.aprintf("+%v", len(player.ghosts))
					die.current_score += sco(len(player.ghosts))
				case .CardDice_Optimist:
				    if is_active {
						bonus := 0.
						for other_dice, o in app.dice{
                            if d == o || other_dice.state != .ALIVE || die.player != other_dice.player || other_dice.current_number < 4 do continue
                            bonus += sco(other_dice.current_number)
                        }
						text = fmt.aprintf("+%.f", bonus)
						die.current_score += bonus
					}
				case .CardDice_PlusOne:
				    plus_score := 1
					if is_active do plus_score += n_alive-1
					text = fmt.aprintf("+%v", plus_score)
					die.current_score += sco(plus_score)
				case .CardDice_Pessimist:
				    if is_active {
						multiplier := 0.
						for other_dice, o in app.dice{
                            if d == o || other_dice.state != .ALIVE || die.player != other_dice.player || other_dice.current_number > 3 do continue
                            multiplier += sco(other_dice.current_number)
                        }
                        if multiplier > 0. {
    						text = fmt.aprintf("x%.f", multiplier)
    						die.current_score *= multiplier
                        }
					}
				case .CardDice_Train:
					bonus := 0.
					n_dice := 0
					for die2, d2 in app.dice{
                        if d == d2 || die2.state != .ALIVE || die.player != die2.player || die2.current_number <= die.current_number do continue
                        bonus += sco(die2.current_number)
                        add_text(die2.position, fmt.aprintf("+%v", die2.current_number), die2.color1,
                        	delay=delay, lifetime=duration, icon_id=icon_index_from_id("CardDice_Train"))
                        delay += duration/3.
                    }
                    if bonus > 0. {
						text = fmt.aprintf("+%.f", bonus)
						die.current_score += bonus
                    }
				case .CardDice_Librarian:
    				if upgrade.var1 != 0. {
       					text = fmt.aprintf("+%.f", upgrade.var1)
                        die.current_score += upgrade.var1
       	            }
				case .CardDice_PowerDice:
					text = fmt.aprintf("X%.f", die.current_score)
					die.current_score *= die.current_score
				case:
					continue
				}
				if len(text) > 0{
					position, anchor := ring_position_3d(n_events+1, 2.0)
					add_text(die.position, text, die.color1, anchor=anchor,
							delay=delay, lifetime=duration,
							icon_id=icon_index_from_id(reflect.enum_string(upgrade.type)))
					delay += duration
				}
			}

			if die.current_score != 0 || delay > 0 {
				// camera_zoom(die.position)

				die.already_scored = true
				player.roll.score += die.current_score
				player.roll.score_timer = 1.
				player.roll.score_counter += 1

				pitch :f32= 1.0 + ((p == 0) ? 0.1 : -0.1) * f32(player.roll.score_counter)
				play_sound(6, pitch=pitch)

				add_text(die.position,
					fmt.aprintf("+%.f", die.current_score), die.color1,
					delay=delay, lifetime=duration*1.2)
				wait(delay + 1.2*duration)
			}

			return
		}
		player.is_scoring = false
	}

	state_change(.CARDS_SCORING, 0.2)
}


cards_scoring :: proc(dt: real) {
	state_change(.SCORING_SUMMARY, wait=0.4)
}

play_sound :: proc(sound_id: i32, volume: f32=1., pitch: f32=1.) {
	sound := app.sounds[sound_id]
	rl.StopSound(sound)
	rl.SetSoundVolume(sound, volume*1.)
	rl.SetSoundPitch(sound, pitch)
	rl.PlaySound(sound)
}

scoring_summary :: proc(dt: real) {
	roll_scores := [2]sco{}
	for &player, p in app.players {
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

		// Tidy up all cards that should be inactive now...
		cards_copy := make([dynamic]Card, len(player.cards), cap(player.cards))
		defer delete(cards_copy)
		copy(cards_copy[:], player.cards[:])
		clear(&player.cards)

		for &card, index in cards_copy{
            if card.active do card.lifetime -= 1
			if !card.active || card.lifetime > 0 {
			    append(&player.cards, card)
			} else {
				play_sound(11)
			}
		}
	}

	if app.players[0].total_score >= app.antagonist.goal_score{
		antagonist_story("antagonist_lost")
		state_change(.VICTORY)
		return
	} else if app.players[1].total_score >= app.antagonist.goal_score{
		antagonist_story("antagonist_wins")
		state_change(.LOST)
		return
	}

	app.current_player = (app.current_player + 1) % N_PLAYERS
	state_change(.WAIT_FOR_AI)

	camera_reset()
}

end_of_level :: proc(dt: real){
	if app.state_timer != 0. do return
	app.state_timer = 0.5

	victor: u8= app.state == .VICTORY ? 0 : 1
	loser: u8= app.state == .LOST ? 0 : 1
	for &die, d in app.dice{
		if die.state != .ALIVE do continue
		if die.player == loser {
			die.state = .DEAD
		} else {
			add_particles(die.position, die.color1)
		}
	}
	for i in 0..<10{
		particles := &app.particles[i]
		if !particles.visible || particles.lifetime > .7 do continue
		for position, p in particles.positions{
			add_particles(position, particles.color)
			if p > 1 do break
		}
	}
	// state_change(.WAIT_FOR_ROLL)
}

wait_for_ai :: proc(){
    // Some actions that the AI could do...
    ai := &app.players[1]

    if len(ai.ghosts) >= 5 {
	    // @TODO: how do we find the best selection of dice?
	    counter := [6]i32{}	// dice number -> count
	    for ghost_number, i in ai.ghosts{
	    	counter[ghost_number-1] += 1
	    }
	    lower_straight := slice.min(counter[:5]) > 0
	    upper_straight := slice.min(counter[1:]) > 0
	    has_pairs := slice.max(counter[:]) > 1

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
	    } else if has_pairs {
	    	// If we have pairs, we want to keep all the numbers that are part of a pair
			#reverse for ghost_number, i in ai.ghosts{
				if counter[ghost_number-1] > 1 && len(best_indices) < 5 {
					append(&best_indices, i32(i))
				}
			}

			// Fill up with other dice:
			#reverse for ghost_number, i in ai.ghosts{
				if len(best_indices) < 5 && !contains(best_indices[:], i32(i)) {
					append(&best_indices, i32(i))
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
		// If there are many dice left, the chances are high that there are many ghost
		// dice next round
		n_alive :i32= 0
		for &die, d in app.dice{
			// The max number of ghosts next round, is the number of ghosts we have now
			// + the number of alive dice of the defensive player (roll cards not included)
			if die.state == .ALIVE && die.player != app.current_player do n_alive += 1
		}
		if best_score > 0 && (best_score > 20 || i32(len(ai.ghosts))+n_alive > ai.ghosts_max) {
			ai.roll.score += best_score

			cards := [1]Card{}
			cards_generate(cards[:], .RollAndDiceCards)
			append(&ai.cards, cards[0])

			ghosts_copy := make([dynamic]i32, len(ai.ghosts), cap(ai.ghosts))
			defer delete(ghosts_copy)
			copy(ghosts_copy[:], ai.ghosts[:])
			clear(&ai.ghosts)

			for ghost, index in ghosts_copy{
				if !contains(best_indices[:5], i32(index)) do append(&ai.ghosts, ghost)
			}
		}
    }

    if len(ai.cards) > 0{
    	cards_to_discard := [dynamic]i32{}
     	defer delete(cards_to_discard)
    	for &card, c in ai.cards{
     		if card.active do continue

       		#partial switch card.category{
         	case .ROLL:
				card_activate(ai, &card)
			case .DICE:
				for &die in app.dice{
					if die.state != .ALIVE || die.player != 1 do continue
					if card_assign(&die, card) {
						append(&cards_to_discard, i32(c))
						break
					}
				}
			}
     	}

      	#reverse for index in cards_to_discard{
	 		ordered_remove(&ai.cards, index)
	 	}
    }

	state_change(.WAIT_FOR_ROLL)
}

draw :: proc(dt: real) {
	human := &app.players[0]

	rl.BeginDrawing()
	defer rl.EndDrawing()

	anti_bg := rl.Color{}
	if app.state == .WAIT_FOR_ROLL{
		ratio := app.state_timer / 3.
		color1 := rl.ColorBrightness(COLOR_PLAYERS[app.current_player], COLOR_SHIFT)
		color2 := rl.ColorBrightness(COLOR_PLAYERS[(app.current_player+1)%N_PLAYERS], COLOR_SHIFT)
		app.gui.bg_color = rl.ColorLerp(color2, color1, ratio)
		anti_bg = rl.ColorLerp(color1, color2, ratio)
	} else if app.state == .ROLLING{
		app.gui.bg_color = rl.ColorBrightness(COLOR_PLAYERS[app.current_player], COLOR_SHIFT)
		anti_bg = rl.ColorBrightness(COLOR_PLAYERS[(app.current_player+1)%N_PLAYERS], COLOR_SHIFT)
	}
	rl.ClearBackground(app.gui.bg_color)

	rl.BeginMode3D(app.camera3d)

	// Draw a big cube to represent the area where the app.dice can move
	rl.DrawCube(rl.Vector3{0.0, -.6, .0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)
	rl.DrawCubeWires(rl.Vector3{0.0, -.6, .0}, AREA_SIZE, 1.0, AREA_SIZE, rl.BLACK)

	if app.state == .WAIT_FOR_ROLL && (rl.IsMouseButtonPressed(.LEFT) || rl.IsMouseButtonPressed(.RIGHT)){
		app.die_selected = -1
	}

	dice_hovered := -1
	for &dice, d in app.dice{
		if dice.state != .ALIVE do continue
		hoverable := app.state == .WAIT_FOR_ROLL || (app.state == .UPGRADE_DIE && dice.player == 0)
		if draw_die(dice, hoverable=hoverable) {
			dice_hovered = d
			if rl.IsMouseButtonPressed(.LEFT) {
				app.die_selected = i32(d)
			}
		}
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

	// rl.BeginMode2D()
	// defer rl.EndMode2D()

	rl.DrawFPS(10, 10)

	screen_height := f32(rl.GetScreenHeight())
	screen_width := f32(rl.GetScreenWidth())
	mouse_pos := rl.GetMousePosition()

	for &player, p in app.players{
		discard_card := -1
		discard_silent := false

		// We draw them in reverse, so we don't get a z-order problem with the cards (the hovered one should be on top)
		#reverse for &card, c in player.cards{
			position := app.gui.hand_positions[p]
			if f32(len(player.cards))*(CARD_SIZE.y+30) > app.gui.hand_area_height {
				position += {0, app.gui.hand_area_height/f32(len(player.cards))*f32(c)}
			} else {
				position += {0, f32(c)*(30+CARD_SIZE.y)}
			}
			actions := []string{}
			if app.state == .WAIT_FOR_ROLL && p == 0 {
				if card.category == .ROLL do actions = card.active ? {"DISCARD"} : {"DISCARD", "ACTIVATE"}
				else if card.category == .DICE do actions = {"DISCARD", "ASSIGN"}
				else if card.category == .CYCLE do actions = {"DISCARD", "ACTIVATE"}
			}

			hovered, action := draw_card(card, position, actions=actions)
			if app.state == .WAIT_FOR_ROLL && action == 1 {
				if card.category == .ROLL{
					card_activate(&player, &card)
				} else if card.category == .DICE {
					app.card_selected = card
					discard_card = c
					discard_silent = true
					state_change(.UPGRADE_DIE)
				}
			} else if action == 0{
				discard_card = c
			}
		}
		if discard_card != -1 {
			card_discard(&player, i32(discard_card), silent=discard_silent)
		}

		// Draw ghost dice on the side:
		ghost_cols :i32= 5 // @TODO: make this dynamic based on the max number of ghosts a player can have
		ghost_size :f32= app.gui.font_size1
		ghost_padding :f32= 4
		ghost_dx := ghost_size + ghost_padding
		for i in 0..<player.ghosts_max {
			ghost_index := i32(i)
			row := ghost_index / ghost_cols
			col := ghost_index % ghost_cols
			if p == 1 do col *= -1	// flip the ghosts for the right player
			position := app.gui.ghost_positions[p] + ghost_dx*rl.Vector2{f32(col), f32(row)}
			if p == 1 do position.x -= ghost_size+ghost_padding	// shift the right player's ghosts to the left

			if ghost_index >= i32(len(player.ghosts)) {
				thickness :f32= 2
				draw_box(position+{2, 2}, {ghost_size-2, ghost_size-2}-thickness, fill={100, 100, 100, 120}, thickness=thickness)
				continue
			}
			ghost_number := player.ghosts[ghost_index]

			clickable := app.state == .WAIT_FOR_ROLL && p == 0
			if dice_button(ghost_number, position, ghost_size, active_color=player.color, clickable=clickable) {
				state_change(.GHOST_BOARD)
				app.ghosts_selected[0] = i32(i)
			}
		}
		if p == 0{
			combos := possible_combinations(player.ghosts[:])
			combos_counter := 0
			for combo in combos{
				if combo == .None do continue
				if combo in player.cycle.scored_combinations do continue
				combos_counter += 1
			}
			if combos_counter > 0 {
				text := fmt.aprintf("%v COMBINATIONS!", combos_counter)
				position := app.gui.ghost_positions[p]
				position.x += (ghost_dx*f32(ghost_cols))/2.
				position.y += ghost_size// + app.gui.font_size2/.2
				draw_text(text, position, color=player.color, anchor=.CENTER, outline=rl.BLACK)
			}
		}

		position := app.gui.score_positions[p]
		text := fmt.tprintf("%.f", player.total_score)
		draw_text(text, {position.x, position.y+40}, app.gui.font_size1, player.color, anchor=(p == 1) ? .RIGHT : .LEFT)

		text = (p == 0) ? "YOU" : "ANTAGONIST"
		draw_text(text, {position.x, position.y+100}, app.gui.font_size2, player.color, anchor=(p == 1) ? .RIGHT : .LEFT, overline=true)

		if app.state == .DICE_SCORING || app.state == .SCORING_SUMMARY || player.roll.score > 0. {

			font_size := app.gui.font_size1 * (1.+0.5*splash(player.roll.score_timer))
			player.roll.score_timer -= dt
			if player.is_scoring && player.roll.score > 0. {
				font_size += math.max((0.3-app.state_clock), 0.1) * 100
			}
			if player.roll.multiplier > 0 {
				text = fmt.tprintf("+ %.f X %.f", player.roll.score, player.roll.multiplier)
			} else {
				text = fmt.tprintf("+ %.f", player.roll.score)
			}

			if p == 1{
				// Shift the right player's score so it is always 50 pixels from the right side
				position.x = screen_width-measure_text(text, font_size).x- 50
			}

			draw_text(text, position, font_size, player.color,)
		}
	}

	info := app.state == .WAIT_FOR_ROLL// || app.state == .UPGRADE_DIE
	if info && app.die_selected != -1 {
	    selected := app.die_selected != -1
		die := selected ? app.dice[app.die_selected] : app.dice[dice_hovered]
		position := rl.GetWorldToScreen(die.position, app.camera3d)
		icon_size := f32(80.)
        padding := f32(6.)
		#reverse for upgrade, u in die.upgrades{
		    color := die.color1
			upgrade_pos, anchor := ring_position_2d(u+1, icon_size+4*padding)//f32(u)*Vector2{icon_size+4*padding, 0.}
			upgrade_pos += position
			switch anchor{
			case .CENTER:
				upgrade_pos -= icon_size/2.
			case .RIGHT:
				upgrade_pos -= {icon_size, icon_size/2.}
			case .LEFT:
				upgrade_pos -= {0, icon_size/2.}
			}
            ts := TextureFaceSize
            tp := ts.yx * {0., 1.}  // Standard question mark...
           	upgrade_type_string := reflect.enum_string(upgrade.type)
           	if upgrade_type_string in app.sub_textures {
                tp = ts.yx * app.sub_textures[upgrade_type_string].yx
            } else if upgrade.type == .CardNone {
                // show the numbers...
                tp = ts.yx * Vector2{f32(die.faces[u]-1), 0}
                color /= 2
            }

            upgraded := upgrade.type != .CardNone
           	dest := rl.Rectangle{x=upgrade_pos.x, y=upgrade_pos.y, width=icon_size, height=icon_size}
           	draw_box({dest.x, dest.y}-padding/2, {}+icon_size+2*padding/2, fill=upgraded ? color : color/2, thickness=2)
           	rl.DrawTexturePro(app.textures[0], {tp.x, tp.y, ts.x, ts.y}, dest, {}, 0., upgraded ? rl.BLACK : rl.RAYWHITE/2)

            hovered := rl.CheckCollisionPointRec(mouse_pos, dest)
            if upgrade.type != .CardNone && hovered {
            	card_position := upgrade_pos + {-CARD_SIZE.x/2.+icon_size/2., icon_size+10}
                draw_card(upgrade, card_position, with_icon=false)
            }
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

	if app.state == .CHARGING{
		// Draw a power bar at the center of the screen
		width: f32 = 800.
		height: f32 = 80.
		x := (f32(screen_width) - width) / 2.
		y := (f32(screen_height) - height) / 2.
		rl.DrawRectangleV({x, y}, {app.power * width, height}, app.players[app.current_player].color)
		rl.DrawRectangleLinesEx({x, y, width, height}, 2., rl.BLACK)
	}

	if app.state == .GHOST_BOARD {
		board_size := rl.Vector2{920, app.gui.height-150}
		board_position := rl.Vector2{(app.gui.width-board_size.x)/2., 50}
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
				for &slot, slot_index in app.ghosts_selected{
					if slot == i32(ghost_index) {
						slot = -1 // deselect if already selected
						free_index = -1 // no further action
						break
					}
					if slot == -1 {
						free_index = slot_index
						break
					}
				}
				// if free_index == -1 {
				// 	// We didn't find any empty slot, we move all selected ghosts
				// 	// to the left and remove the left-most
				// 	slice.rotate_left(app.ghosts_selected[:], 1)
				// 	app.ghosts_selected[4] = i32(ghost_index)
				// } else
				if free_index >= 0 {
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
		} else if contains(app.ghosts_selected[:], i32(-1)) {
			text = fmt.tprintf("Select %v more ghost dices to score combinations", count(app.ghosts_selected[:], i32(-1)))
		} else if highest_score > 0 {
			text = fmt.tprintf("Your best combination is worth %v points", highest_score)
		}
		draw_text(text, board_position + rl.Vector2{20, 20}, app.gui.font_size2, rl.RAYWHITE)
		if button("ESC", board_position + rl.Vector2{board_size.x - 20, 20}, app.gui.font_size2, anchor=.RIGHT) {
			state_change(.WAIT_FOR_ROLL)
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
				state_change(.CARDS_OFFER)
			}
		} else if n_scored_combos > 9{
			if len(app.antagonist.story_id) == 0 && !app.antagonist.tutorial_cycles {
				antagonist_story("antagonist_tutorial_cycles")
			}
			if button("RUSH CYCLE", board_position+board_size-{20, 70}, app.gui.font_size2, anchor=.RIGHT) {
				add_text(board_position+board_size/2.,
					fmt.aprint("CYCLE COMPLETED BY RUSHING!"), human.color, 2.,
					font_size=app.gui.font_size1, anchor=TextAnchor.CENTER)
				app.ghosts_selected = {}-1 // deselect everything
				app.cards_offer = {}
				cards_generate(app.cards_offer[:2], .CycleCards)
				human.cycle.scored_combinations = {}
				state_change(.CARDS_OFFER)
			}
		} else {
			draw_text(fmt.tprintf("%v/15 combinations scored", n_scored_combos),
				board_position+board_size-{20, 70}, anchor=.RIGHT)
		}

		if len(app.antagonist.story_id) == 0 && !app.antagonist.tutorial_ghost_board {
			app.antagonist.tutorial_ghost_board = true
			antagonist_story("antagonist_tutorial_ghost_board")
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
			state_change(.CHARGING)
		}
	}

	if app.state == .CARDS_OFFER {
		app.die_selected = -1

		text := "Choose one of these cards"
		draw_text(text, {screen_width/2., screen_height - 150}, app.gui.font_size1, rl.RAYWHITE, anchor=.CENTER)

		n_cards: f32
		for card in app.cards_offer do if card.type != .CardNone do n_cards += 1

		margin :f32= 10
		for &card, c in app.cards_offer{
			if card.type == .CardNone do continue

			position := Vector2{
			    margin+(f32(c)+1)*(app.gui.width-2.*margin)/(n_cards+1)-CARD_SIZE.x/2.,
				(app.gui.height-CARD_SIZE.y)/2.
			}

			actions := []string{"KEEP", "ACTIVATE"}
			if card.category == .DICE do actions = {"KEEP", "ASSIGN"}
			else if card.category == .CYCLE do actions = {"ACTIVATE"}
			_, action := draw_card(card, position, actions=actions)
			if action == 1 {
				if card.category == .ROLL{
					card_activate(human, &card)
					append(&human.cards, card)
					card = {}
					state_change(.WAIT_FOR_ROLL)
				} else if card.category == .DICE {
					app.card_selected = card
					state_change(.UPGRADE_DIE)
				}
			} else if action == 0{
				if card.category == .CYCLE {
					card_activate(human, &card)
				} else {
					append(&human.cards, card)
				}
				card = {}
				state_change(.WAIT_FOR_ROLL)
			}
		}

		if len(app.antagonist.story_id) == 0 && !app.antagonist.tutorial_cards {
			app.antagonist.tutorial_cards = true
			antagonist_story("antagonist_tutorial_cards")
		}
	}

	if app.state == .UPGRADE_DIE {
		// app.card_selected.triggered = app.die_selected >= 0 ? 1. : 0.

		text := "Choose a dice to assign this card to"
		draw_text(text, {screen_width/2., screen_height - 150}, app.gui.font_size1, rl.RAYWHITE, anchor=.CENTER)
		draw_card(app.card_selected, mouse_pos - {CARD_SIZE.x/2, CARD_SIZE.y+50})

		if app.die_selected >= 0 && app.dice[app.die_selected].player == 0 {
			die := &app.dice[app.die_selected]
			could_upgrade := card_assign(die, app.card_selected)
			app.card_selected = {}

			if !could_upgrade {
				add_text(die.position, fmt.aprint("Die has no free upgrade slots!"), die.color1, 1.5)
				app.die_selected = -1
			}
			state_change(.WAIT_FOR_ROLL)
		} else if rl.IsMouseButtonPressed(.RIGHT) || rl.IsKeyPressed(.ESCAPE) {
			app.card_selected.triggered = 0.
			append(&human.cards, app.card_selected)
			app.card_selected = {}
			add_text(mouse_pos, fmt.aprint("Keep card in hand!"), human.color, 1.5)
			state_change(.WAIT_FOR_ROLL)
		}
		app.die_selected = -1
	}

	for &animation in app.animations{
		if !animation.visible do continue

		if animation.delay > 0. {
			animation.delay -= dt
			continue
		}
		animation.lifetime -= dt
		if animation.lifetime < 0.{
			animation.visible = false
			delete(animation.text)
			continue
		}

		start_2d, end_2d: Vector2
		if start_3d, is_vec3 := animation.start.(Vector3); is_vec3 {
			start_2d = rl.GetWorldToScreen(start_3d, app.camera3d)
		} else do start_2d = animation.start.(Vector2)

		if end_3d, is_vec3 := animation.end.(Vector3); is_vec3 {
			end_2d = rl.GetWorldToScreen(end_3d, app.camera3d)
		} else do end_2d = animation.end.(Vector2)

		// adapt to zoom in
		font_size := app.gui.font_size2// * (1.+(1. - (app.camera3d.fovy-25)/5))

		life_ratio := animation.lifetime / animation.start_lifetime
		alpha := life_ratio > 0.3 ? 1.0 : life_ratio/0.3
		font_size *= splash(life_ratio)

		// end_2d = start_2d// + {0, -20}

		x := math.lerp(start_2d.x, end_2d.x, 1.-life_ratio)
		y := math.lerp(start_2d.y, end_2d.y, 1.-life_ratio)

		icon_id, has_icon := animation.icon_id.?
		if has_icon{
			icon_size :f32= font_size * 4
			draw_texture(icon_id, {x-icon_size/2, y-icon_size/2}, icon_size,
				rl.ColorAlpha(animation.color, alpha)
			)
		}

		if len(animation.text) == 0 do continue

		text_size := measure_text(animation.text, font_size)
		x -= text_size.x/2.
		y -= text_size.y/2.

		box_position := Vector2{x-5, y-5}
		// if animation.anchor == .CENTER do box_position.x -= text_size.x/2.
		// if animation.anchor == .RIGHT do box_position.x -= text_size.x
		text_color := rl.ColorAlpha(animation.color, alpha)
		text_outline := rl.BLACK
		if !has_icon{
			draw_box(box_position, {text_size.x+10, text_size.y+10},
				fill=rl.ColorAlpha(animation.color, alpha), thickness=2,
				outline=rl.ColorAlpha(rl.BLACK, alpha))
			text_color = rl.ColorAlpha(rl.BLACK, alpha)
			text_outline = rl.BLANK
		}
		draw_text(animation.text, {x, y}, font_size, text_color, outline=text_outline)
	}
}

wait :: proc(duration: real){
	app.state_timer = duration / config.game_speed
}

state_change :: proc(new_state: GameState, wait: f32=0.) {
	app.state_before = app.state
	app.state = new_state
	app.state_clock = 0.
	app.state_timer = wait / config.game_speed

	if new_state == .CHARGING {
		camera_reset()
		app.die_selected = -1
	}
}
