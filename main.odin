package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:math/linalg"
import vmem "core:mem/virtual"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

sco :: f64

AREA_SIZE :: 30.0
COLOR_TABLE := rl.Color{102, 51, 153, 255}
COLOR_PLAYERS := [2]rl.Color{
	rl.Color{203, 161, 53, 255},
	rl.Color{255, 41, 156, 255},
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
	gui_score_position: [2]i32,
}
players: [N_PLAYERS]Player
current_player_id: u8 = 0

State :: enum {
	WAIT_FOR_ROLL,
	CHARGING,
	ROLLING,
	BATTLE,
	SCORING,
	SCORING_SUMMARY,	// only for the animations (all points are flying in)
}
state := State.ROLLING // We start with rolling
state_countdown: f32 = 0.0

EntityState :: enum {
	NOT_USED,
	DEAD,
	ALIVE,
}

Card :: struct {

}
cards := [1000]Card{}

N_DICES :: 12
Dice :: struct {
	state: EntityState,
	using body: RigidBody,
	player: u8,
	color: rl.Color,
	current_number: i32, // which number is shown on top face
	current_score: sco,
	already_scored: bool,
	upgrades: [5]DiceUpgrade,
	attack: sco,
	health: sco,
}
dices := [dynamic]Dice{}

// All contact are stored here:
contacts := [dynamic]Contact{}

// We use this to limit the throwing area
Plane :: struct {
	direction: Vector3,
	offset: real,
}

Particles :: struct{
	positions: [9]Vector3,
	velocities: [9]Vector3,
	color: rl.Color,
	visible: bool,
	lifetime: f32
}
particles := [1000]Particles{}

Text :: struct{
	start: Vector2,
	end: Vector2,
	text: string,
	color: rl.Color,
	visible: bool,
	font_size: i32,
	lifetime: f32,
	start_lifetime: f32
}
texts := [200]Text{}

sounds := []rl.Sound{}
camera : rl.Camera3D

Opponent :: struct {
	message: string,
	speaking: bool
}
opponent: Opponent

main :: proc() {
	// Initialize window
	screen_width := rl.GetScreenWidth()
	screen_height := rl.GetScreenHeight()

	rl.InitWindow(screen_width, screen_height, "Rolls")
	rl.ToggleFullscreen() // Start in fullscreen mode
	rl.SetTargetFPS(60)
	defer rl.CloseWindow()

	screen_width = rl.GetScreenWidth()
	screen_height = rl.GetScreenHeight()

	players = {
		{color=COLOR_PLAYERS[0], roll_multiplier=1,
			gui_score_position={100, screen_height - 300}},
		{color=COLOR_PLAYERS[1], roll_multiplier=1,
			gui_score_position={screen_width-100, screen_height - 300,}},
	}

	// Make some dices:
	dices_reset(first_round=true)

	CAMERA_HEIGHT: f32 = 65.0
	camera = {}
	camera.position = rl.Vector3{30, CAMERA_HEIGHT, 0.}
	camera.target = rl.Vector3{0.0, 0.0, 0.0}
	camera.up = rl.Vector3{0.0, 1.0, 0.0}
	camera.fovy = f32(30) // Camera field-of-view Y
	camera.projection = .PERSPECTIVE // Camera mode type

	{ // Clear everything so we don't get welcomed by a white screen
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		rl.BeginMode3D(camera)
		defer rl.EndMode3D()

		 // Draw a big cube to represent the area where the dices can move
		rl.DrawCube(rl.Vector3{0.0, -0.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)
	}

	rl.SetTargetFPS(60)

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	sounds = {
		rl.LoadSound("assets/sounds/dice_1.wav"),
		rl.LoadSound("assets/sounds/dice_2.wav"),
		rl.LoadSound("assets/sounds/dice_3.wav"),
		rl.LoadSound("assets/sounds/dice_4.wav"),
		rl.LoadSound("assets/sounds/dice_5.wav"),
		rl.LoadSound("assets/sounds/dice_elimination.wav"),
		rl.LoadSound("assets/sounds/dice_scores.wav"),
	}
	defer {
		for sound in sounds {
			rl.UnloadSound(sound)
		}
	}
	textures := [?]rl.Texture2D{rl.LoadTexture("assets/textures/dice.png")}
	defer {
		for texture in textures {
			rl.UnloadTexture(texture)
		}
	}

	opponent = {
		message = "Let's see who reaches\n1000 points first!",
		speaking = true,
	}

	// Main game loop
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		state_countdown += dt

		if state == .WAIT_FOR_ROLL && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			state = .CHARGING
			state_countdown = 0.
		}

		// Max power is reached after 3 seconds of charging)
		power := f32(math.min(1.0, state_countdown / 0.25))

		if state == .CHARGING &&
			((current_player_id == 0 && rl.IsKeyReleased(rl.KeyboardKey.SPACE)) ||
			(current_player_id == 1 && power >= 1.0)) {
				dices_reset(power=power)
				state_countdown = 0.0
				state = .ROLLING
		}

		if rl.IsKeyPressed(rl.KeyboardKey.S) {
			for dice, d in dices{
				if dice.state != .ALIVE do continue
				if dice.player == current_player_id do fmt.println(d, dice)
			}
		}

		// Zoom in and out:
		mouse_wheel := rl.GetMouseWheelMove()
		if mouse_wheel != 0.0 {
			camera.position.y += 200. * mouse_wheel * dt
		}

		// update particles:
		for &particle in particles{
			if !particle.visible do continue

			// Apply some damping to the velocity so the particles eventually stop
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

		// update texts:
		for &text in texts{
			if !text.visible do continue

			text.lifetime -= dt
			if text.lifetime < 0.{
				text.visible = false
				delete(text.text)
			}
		}

		if opponent.speaking {
			if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
				opponent.speaking = false
				state_countdown = 0.0
			}
		} else {
			if state == .ROLLING{
				physics(dt)
				rolling(dt)
			} else if state == .BATTLE {
				battle(dt)
			} else if state == .SCORING {
				scoring(dt)
			} else if state == .SCORING_SUMMARY {
				scoring_summary(dt)
			}
		}

		// draw everything:
		draw(camera, textures[:], power)

		// Free the temp arena at the end of the frame
		free_all(context.temp_allocator)
	}
}

dices_reset :: proc(power:f32=1., first_round:bool=false) {
	if first_round {
		clear(&dices)
		for i in 0..<N_DICES {
			append(&dices, Dice{player=u8((i < N_DICES / 2) ? 0 : 1)})
		}
	}

	upgrades := [5]DiceUpgrade{}
	// upgrades[0] = DiceUpgrade_Antenna{}

	for &dice, d in dices {
		half_size :f32= .75
		mass := math.pow(half_size, 3) * 8.
		position := dice.position+Vector3{0, 10, 0}
		velocity := Vector3{0, -5, 0}
		orientation := dice.orientation
		rotation := dice.rotation
		acceleration := dice.acceleration

		if dice.player == current_player_id || first_round
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
				color=players[dice.player].color,
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
	for &dice, d in dices{
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

	clear(&contacts)
	for &dice, d in dices{
		if len(contacts) > 1000 do break

		collision_wall := false
		for wall in walls {
			collision_wall |= collision_detect_box_plane(&dice, wall, &contacts)
		}

		collision_other_dice := false
		for &other_dice, od in dices{
			if dice == other_dice || other_dice.state != .ALIVE do continue

			collision_other_dice |= collision_detect_box_box(&dice, &other_dice, &contacts)
		}

		if collision_wall && dice.motion > 0.97{
			sound := rand.choice(sounds[:4])
			rl.SetSoundVolume(sound, math.min(1.0, linalg.length(dice.velocity) / 140.0)) // Set volume based on bounce speed
			rl.SetSoundPitch(sound, rand.float32_range(0.7, 1.1)) // Add some random pitch variation
			rl.PlaySound(sound)
		}
		if collision_other_dice && dice.motion > 0.9 && state_countdown > 1.0{
			sound := rand.choice(sounds[:4])
			rl.SetSoundVolume(sound, math.min(1.0, linalg.length(dice.velocity) / 80.0)) // Set volume based on bounce speed
			rl.SetSoundPitch(sound, rand.float32_range(1., 1.5)) // Add some random pitch variation
			rl.PlaySound(sound)
		}
	}

	if len(contacts) > 0 {
		if state != .ROLLING {
			fmt.println("Resolving", len(contacts), "contacts")
		}
		resolver := ContactResolver{
			position_iterations=i32(len(contacts))*16, velocity_iterations=i32(len(contacts))*16
		}
		contact_resolve_contacts(&resolver, contacts[:], duration)
	}
}

rolling :: proc(dt: real){

	for &dice, d in dices{
		if dice.state != .ALIVE do continue

		// Either wait until all dices are not moving that much anymore
		// or until enough time has past
		if dice.motion > 0.9 && state_countdown < 5. {
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

	// We move to the next state
	state = .BATTLE
	state_countdown = 0.
}

add_text :: proc{add_text_vec3, add_text_vec3_vec2, add_text_vec2}
add_text_vec3_vec2 :: proc (start: Vector3, end: [2]i32, text: string, color: rl.Color, lifetime:f32=2.0, font_size:i32=30) {
	start_2d := rl.GetWorldToScreen(start, camera)
	add_text_vec2(start_2d, {f32(end.x), f32(end.y)}, text, color, lifetime, font_size)
}
add_text_vec3 :: proc (start: Vector3, text: string, color: rl.Color, lifetime:f32=2.0, font_size:i32=30) {
	start_2d := rl.GetWorldToScreen(start, camera)
	add_text_vec2(start_2d, start_2d + Vector2{0, -100}, text, color, lifetime, font_size)
}
add_text_vec2 :: proc (start, end: Vector2, text: string, color: rl.Color, lifetime:f32, font_size: i32) {
	for &t in texts{
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

battle :: proc(dt: real) {
	if state_countdown < 0.3 do return

	// We eliminate all dices from each player that show the same numbers.
	// E.g. if player 1 has two dices showing a 3 and player 2 has one dice showing a 3,
	// one dice each is eliminated and won't give points to either player.

	for &dice, d in dices{
		if dice.state != .ALIVE do continue

		for &other_dice, o in dices{
			if d == o || other_dice.state != .ALIVE || dice.player == other_dice.player do continue
			if dice.current_number == other_dice.current_number {
				dice.health = math.max(dice.health-other_dice.attack, 0)
				other_dice.health = math.max(other_dice.health-dice.attack, 0)

				if other_dice.health == 0{
					add_particles(other_dice.position, other_dice.color/2.)
					add_text(other_dice.position, fmt.aprint("DEAD!"), other_dice.color, 1.5, font_size=40)

					other_dice.state = .DEAD
					other_dice.position.y = 1000.

					players[dice.player].roll_kills += 1
				} else {
					add_text(other_dice.position, fmt.aprint("HIT!"), other_dice.color, 1.5, font_size=40)
				}

				if dice.health == 0{
					add_particles(dice.position, dice.color/2.)
					add_text(dice.position, fmt.aprint("DEAD!"), dice.color, 1.5, font_size=40)

					dice.state = .DEAD
					dice.position.y = 1000.

					players[other_dice.player].roll_kills += 1
				} else  {
					add_text(dice.position, fmt.aprint("HIT!"), dice.color, 1.5, font_size=40)
				}

				sound := sounds[5]
				rl.SetSoundVolume(sound, rand.float32_range(0.8, 1.)) // Set volume based on bounce speed
				rl.SetSoundPitch(sound, 0.1+f32(players[dice.player].roll_kills)/f32(len(dices)/2.)) // Add some random pitch variation
				rl.PlaySound(sound)

				// we make a small dramatic pause...
				state_countdown = 0.0
				return
			}
		}
	}

	// We move to the next state
	state = .SCORING
	state_countdown = 0.0
}

scoring :: proc(dt: real) {
	n_dices_alive := 0
	for dice in dices {
		if dice.state == .ALIVE	do n_dices_alive += 1
	}

	if n_dices_alive != 0 && state_countdown < 2.0/f32(n_dices_alive) do return	// some pauses for counting
	state_countdown = 0.0

	// First round of scoring, every dice calculates its own current score
	for &player, p in players{
		player.is_scoring = true
		for &dice, i in dices {
			if dice.state != .ALIVE || dice.already_scored || u8(p) != dice.player do continue

			dice.current_score = sco(dice.current_number)

			// Apply dice card effects
			for upgrade in dice.upgrades{
				#partial switch u in upgrade {
				case DiceUpgrade_Antenna:
					if player.roll_antennas == 0 {
						player.roll_antennas = dice.current_score
					} else {
						player.roll_antennas *= dice.current_score
					}
					add_text(dice.position, fmt.aprintf("+%v ANTENNA", dice.current_score), dice.color, 1.5, font_size=40)
					dice.current_score = 0
				}
			}

			players[dice.player].roll_score += dice.current_score
			dice.already_scored = true

			sound := sounds[6]
			rl.SetSoundVolume(sound, 1.)
			pitch :f32= (p == 0) ? 1.1 : 0.6
			pitch += rand.float32_range(-0.2, 0.2)
			rl.SetSoundPitch(sound, pitch)
			rl.PlaySound(sound)

			// add_particles(dice.position, dice.color)
			if dice.current_score != 0 {
				add_text(dice.position, player.gui_score_position,
						 fmt.aprintf("+%v", dice.current_score), dice.color, 2.0/f32(n_dices_alive), font_size=60)
			}

			return
		}
		player.is_scoring = false
	}

	state = .SCORING_SUMMARY
	state_countdown = 0
}

scoring_summary :: proc(dt: real) {
	if state_countdown < 0.4 do return	// some pauses for counting

	for &player, i in players {
		player.roll_score += player.roll_antennas
		player.roll_score *= player.roll_multiplier

		player.total_score += player.roll_score
		player.roll_score = 0
		player.roll_multiplier = 1
		player.roll_antennas = 0
		player.roll_kills = 0
	}

	state = .WAIT_FOR_ROLL
	state_countdown = 0

	current_player_id = (current_player_id + 1) % N_PLAYERS
}

draw :: proc(camera: rl.Camera3D, textures: []rl.Texture2D, power: f32) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)

	rl.BeginMode3D(camera)

	// Draw a big cube to represent the area where the dices can move
	rl.DrawCube(rl.Vector3{0.0, -.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE)

	for &dice, d in dices{
		if dice.state != .ALIVE do continue

		draw_dice(dice, textures[0])
	}
	size :f32= 0.35
	for particle in particles{
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

	rl.DrawFPS(10, 10)

	screen_height := i32(rl.GetScreenHeight())
	screen_width := i32(rl.GetScreenWidth())

	for player, i in players{
		font_size: i32 = 100
		text := fmt.tprintf("%v", player.total_score)
		position := [2]i32{player.gui_score_position.x, player.gui_score_position.y}

		if i == 1{
			// Shift the right player's score so it is always 100 pixels from the right side
			position.x -= rl.MeasureText(strings.clone_to_cstring(text), font_size)
		}

		rl.DrawText(
			// strings.clone_to_cstring(text, context.temp_allocator),
			strings.clone_to_cstring(text),
			position.x, position.y+100,
			font_size, player.color,
		)

		if state == .SCORING || state == .SCORING_SUMMARY {
			text = fmt.tprintf("+%v", player.roll_score)

			player_roll_score := (player.roll_score+player.roll_antennas)*player.roll_multiplier
			if player.is_scoring && player_roll_score != 0. {
				font_size += i32(math.max((0.3-state_countdown), 0.1) * 100)
			}

			if i == 1{
				// Shift the right player's score so it is always 100 pixels from the right side
				position.x = screen_width-100-rl.MeasureText(strings.clone_to_cstring(text), font_size)
			}

			rl.DrawText(
				// strings.clone_to_cstring(text, context.temp_allocator),
				strings.clone_to_cstring(text),
				position.x, position.y,
				font_size, player.color,
			)
		}
	}

	text := fmt.tprintf("Current player: %v", current_player_id)

	rl.DrawText(
		// strings.clone_to_cstring(text, context.temp_allocator),
		strings.clone_to_cstring(text),
		50, 50, 50, rl.RAYWHITE
	)

	for text in texts{
		if !text.visible do continue

		x := i32(math.lerp(text.start.x, text.end.x, 1.-text.lifetime/text.start_lifetime))
		y := i32(math.lerp(text.start.y, text.end.y, 1.-text.lifetime/text.start_lifetime))
		rl.DrawText(
			strings.clone_to_cstring(text.text, context.temp_allocator),
			x+2, y+2, text.font_size+1, rl.BLACK,
		)
		rl.DrawText(
			strings.clone_to_cstring(text.text, context.temp_allocator),
			x, y, text.font_size, text.color,
		)
	}

	if opponent.speaking {
		fs :i32= 100
		width := rl.MeasureText(strings.clone_to_cstring(opponent.message, context.temp_allocator), fs)
		rl.DrawText(
			strings.clone_to_cstring(opponent.message, context.temp_allocator),
			screen_width/2 - width/2, screen_height/2,
			fs, rl.RAYWHITE
		)
	}

	if state == .CHARGING && current_player_id == 0 {
		// Draw a power bar at the center of the screen
		width: i32 = 800
		height: i32 = 80
		x: i32 = (screen_width - width) / 2
		y: i32 = (screen_height - height) / 2
		rl.DrawRectangle(x, y, i32(power * f32(width)), height, rl.GREEN)
		rl.DrawRectangleLines(x, y, width, height, rl.BLACK)
	}
}
