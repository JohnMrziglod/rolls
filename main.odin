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
}
players: [N_PLAYERS]Player
current_player_id: u8 = 0

State :: enum {
	WAIT_FOR_ROLL,
	CHARGING,
	ROLLING,
	BATTLE,
	SCORING,
	SCORING_ANIMATION,	// only for the animations (all points are flying in)
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

DiceUpgrade_Antenna :: struct {}

DiceUpgrade :: union{
	DiceUpgrade_Antenna,
}

N_DICES :: 12
Dice :: struct {
	state: EntityState,
	using box: Box,
	player: u8,
	color: rl.Color,
	current_number: i32, // which number is shown on top face
	current_score: sco,
	already_scored: bool,
	upgrades: [5]DiceUpgrade,
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
	start: Vector3,
	end: Vector3,
	text: string,
	color: rl.Color,
	visible: bool,
	lifetime: f32
}
scoring_texts := [1000]Text{}
scoring_texts_arena: string

sounds := []rl.Sound{}

main :: proc() {
	// scoring_texts_arena_allocator = vmem.arena_allocator(&arena)

	players = {
		{color=COLOR_PLAYERS[0], roll_multiplier=1},
		{color=COLOR_PLAYERS[1], roll_multiplier=1},
	}

	// Make some dices:
	dices_reset(first_round=true)

	// Initialize window
	screen_width := rl.GetScreenWidth()
	screen_height := rl.GetScreenHeight()

	rl.InitWindow(screen_width, screen_height, "Rolls")
	rl.ToggleFullscreen() // Start in fullscreen mode
	defer rl.CloseWindow()

	CAMERA_HEIGHT: f32 = 65.0
	camera := rl.Camera3D{}
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
				current_player_id = (current_player_id + 1) % N_PLAYERS
		}

		// Zoom in and out:
		mouse_wheel := rl.GetMouseWheelMove()
		if mouse_wheel != 0.0 {
			camera.position.y += 200. * mouse_wheel * dt
		}

		// update physics:
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

		if state == .ROLLING {
			rolling(dt)
		} else if state == .BATTLE {
			battle(dt)
		} else if state == .SCORING {
			scoring(dt)
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
			append(&dices, Dice{})
		}
	}

	upgrades := [5]DiceUpgrade{}
	upgrades[0] = DiceUpgrade_Antenna{}

	for &dice, d in dices {
		// if dice.player == current_player_id || first_round {
		{
			half_size :f32= .75
			mass := math.pow(half_size, 3) * 8.
			player := u8((d < N_DICES / 2) ? 0 : 1)
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
				is_awake=true,
				can_sleep=true,
				player=player,
				color=players[player].color,
				current_number=0,
				current_score=0,
				upgrades=upgrades
			}
		}
	 // 	else if dice.player != current_player_id {
		// 	dice = dice
		// }

		body_set_block_inertia_tensor(&dice, dice.shape.(ShapeBox).half_size, 1./dice.inverse_mass)
		body_calculate_derived_data(&dice)
	}
}

rolling :: proc(duration: real) {
	for &dice, d in dices{
		if dice.state != .ALIVE do continue

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
		if dice.state != .ALIVE || len(contacts) > 1000 do break

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
		resolver := ContactResolver{
			position_iterations=i32(len(contacts))*8, velocity_iterations=i32(len(contacts))*8
		}
		contact_resolve_contacts(&resolver, contacts[:], duration)
	}

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
}

add_particles :: proc(position: Vector3, color: rl.Color){
	for &particle in particles{
		if particle.visible do continue

		for i in 0 ..< len(particle.positions) {
			particle.positions[i] = position
			delta := Vector3{}
			if i / 3 == 0 do delta -= {-0.25, 0, 0}
			if i / 3 == 2 do delta += {0.25, 0, 0}
			if i % 3 == 0 do delta -= {0, 0, -0.25}
			if i % 3 == 2 do delta += {0, 0, 0.25}
			particle.positions[i] += delta
			particle.velocities[i] = random_vector(5., 20.) * 4. * delta
			particle.velocities[i].y = rand.float32_range(5, 20)
		}
		particle.color = color
		particle.visible = true
		particle.lifetime = 1.0

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
				dice.state = .DEAD
				other_dice.state = .DEAD

				// add some explosions
				add_particles(dice.position, dice.color/2.)
				add_particles(other_dice.position, other_dice.color/2.)

				players[dice.player].roll_kills += 1
				players[other_dice.player].roll_kills += 1

				sound := sounds[5]
				rl.SetSoundVolume(sound, rand.float32_range(0.8, 1.)) // Set volume based on bounce speed
				rl.SetSoundPitch(sound, 0.1+f32(players[dice.player].roll_kills)/f32(N_DICES/2.)) // Add some random pitch variation
				rl.PlaySound(sound)

				// we make a small dramatic pause...
				state_countdown = 0.0
				return
			}
		}
	}

	// We move to the next state
	state = .SCORING
	state_countdown = 0.4
}

scoring :: proc(dt: real) {
	n_dices_alive := 0
	for dice in dices {
		if dice.state == .ALIVE	do n_dices_alive += 1
	}

	if state_countdown < 2.0/f32(n_dices_alive) do return	// some pauses for counting
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
					// dice.current_score = 0
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

			add_particles(dice.position, dice.color)

			return
		}
		player.is_scoring = false
	}

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
}

// add_text :: proc(message: string, start, end: Vector3, color: rl.Color){
// 	for &text in scoring_texts{
// 		if text.visible do continue

// 		text = {

// 		}
// 	}
// }

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
		position: [2]i32 = (i == 0) ? {100, screen_height - 200,} : {screen_width-100, screen_height - 200,}

		if i == 1{
			// Shift the right player's score so it is always 100 pixels from the right side
			position[0] -= rl.MeasureText(strings.clone_to_cstring(text), font_size)
		}

		rl.DrawText(
			// strings.clone_to_cstring(text, context.temp_allocator),
			strings.clone_to_cstring(text),
			position.x, position.y,
			font_size, player.color,
		)

		player_roll_score := (player.roll_score+player.roll_antennas)*player.roll_multiplier
		if state == .SCORING && player.is_scoring && player_roll_score != 0.{
			text = fmt.tprintf("+ (%v+%v) x %v", player.roll_score, player.roll_antennas, player.roll_multiplier)
			// font_size /= 4

			font_size += i32(math.max((0.3-state_countdown), 0.1) * 100)

			if i == 1{
				// Shift the right player's score so it is always 100 pixels from the right side
				position[0] = screen_width-100-rl.MeasureText(strings.clone_to_cstring(text), font_size)
			}

			rl.DrawText(
				// strings.clone_to_cstring(text, context.temp_allocator),
				strings.clone_to_cstring(text),
				position.x, position.y-100.,
				font_size, player.color,
			)
		}
	}

	// text = fmt.tprintf("%v", players[1].total_score)
	// rl.DrawText(
	// 	strings.clone_to_cstring(text, context.temp_allocator),
	// 	screen_width - 200, screen_height - 200,
	// 	font_size,
	// 	players[1].color,
	// )

	// rl.DrawFPS(10, 10)

	// if state == .SCORING {
	// 	ratio := state_countdown / 0.5

	// 	if ratio >= 1.0 {
	// 		// After the SCORING animation is done, add the current score of each dice to the player's total score and reset the current score of each dice
	// 		for dice, i in dices {
	// 			players[dice.player].score += dice.current_score
	// 			dices[i].current_score = 0
	// 		}
	// 		state_countdown = 0.0
	// 		// state = .WAIT_FOR_ROLL
	// 	} else {
	// 		for dice in dices {
	// 			if dice.current_score != 0 {
	// 				text := fmt.tprintf("+%v", dice.current_score)
	// 				screen_position := rl.GetWorldToScreen(
	// 					rl.Vector3{dice.position.x, dice.position.y + 0.5, dice.position.z},
	// 					camera,
	// 				)

	// 				// Move the text towards the player's score display
	// 				target_x: f32 = dice.player == 0 ? 100. : f32(screen_width) - 200.
	// 				target_y: f32 = f32(screen_height) - 200.
	// 				screen_position.x += f32(target_x - screen_position.x) * ratio
	// 				screen_position.y += f32(target_y - screen_position.y) * ratio

	// 				rl.DrawText(
	// 					strings.clone_to_cstring(text, context.temp_allocator),
	// 					i32(screen_position.x + 1),
	// 					i32(screen_position.y + 1),
	// 					font_size / 2,
	// 					rl.BLACK,
	// 				)
	// 				rl.DrawText(
	// 					strings.clone_to_cstring(text, context.temp_allocator),
	// 					i32(screen_position.x),
	// 					i32(screen_position.y),
	// 					font_size / 2,
	// 					players[dice.player].color,
	// 				)
	// 			}
	// 		}
	// 	}
	// }

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
