package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

AxisAngle :: struct {
	axis:  rl.Vector3,
	angle: f32,
}

Dice :: struct {
	position:      rl.Vector3,
	velocity:      rl.Vector3,
	rotation:      rl.Quaternion,
	rot_vel:       rl.Vector3, // rad/sec around each axis
	player:        u32,
	on_ground:     bool,
	number_on_top: u8,
	current_score: i32,
}

random_unit_vector3 :: proc() -> rl.Vector3 {
	// Random point on unit sphere
	z: f32 = rand.float32_range(-1, 1)
	t: f32 = rand.float32_range(0, 2 * math.PI) // 0..2π

	r := math.sqrt(1.0 - z * z)

	return rl.Vector3{r * math.cos(t), r * math.sin(t), z}
}

COLOR_TABLE := rl.Color{102, 51, 153, 255}

collides :: proc(dice1, dice2: Dice) -> bool {
	// Check if the two cubes are colliding by checking if their bounding boxes overlap
	half_size: f32 = 0.5
	for axis in 0 ..< 3 {
		if math.abs(dice1.position[axis] - dice2.position[axis]) > half_size * 2 {
			return false
		}
	}
	return true
}
collides_with_ground :: proc(dice: Dice) -> bool {
	// Check if any of the corners of the rotated cube are below the ground level (y=0)
	half_size: f32 = 0.5
	corners := [8]rl.Vector3 {
		{-half_size, -half_size, -half_size},
		{half_size, -half_size, -half_size},
		{-half_size, -half_size, half_size},
		{half_size, -half_size, half_size},
		{-half_size, half_size, -half_size},
		{half_size, half_size, -half_size},
		{-half_size, half_size, half_size},
		{half_size, half_size, half_size},
	}

	for corner in corners {
		// Rotate the corner by the dice's rotation
		// This is a simple rotation around the y-axis, which is not entirely accurate but good enough for our purposes
		angle_x := math.to_radians(dice.rotation.x)
		angle_y := math.to_radians(dice.rotation.y)
		angle_z := math.to_radians(dice.rotation.z)
		cos_x := math.cos(angle_x)
		sin_x := math.sin(angle_x)
		cos_y := math.cos(angle_y)
		sin_y := math.sin(angle_y)
		cos_z := math.cos(angle_z)
		sin_z := math.sin(angle_z)

		rotated_x :=
			corner.x * cos_y * cos_z +
			corner.y * (cos_x * sin_z + sin_x * sin_y * cos_z) +
			corner.z * (sin_x * sin_z - cos_x * sin_y * cos_z)
		rotated_y :=
			corner.x * (-cos_y * sin_z) +
			corner.y * (cos_x * cos_z - sin_x * sin_y * sin_z) +
			corner.z * (sin_x * cos_z + cos_x * sin_y * sin_z)
		rotated_z := corner.x * sin_y + corner.y * (-sin_x * cos_y) + corner.z * (cos_x * cos_y)

		if dice.position.y + rotated_y < 0.0 {
			return true
		}
	}

	return false
}

any_true :: proc(arr: [3]bool) -> bool {
	for b in arr {
		if b {
			return true
		}
	}
	return false
}

angle_between :: proc(q1, q2: rl.Quaternion) -> f32 {
    // Normalize to ensure unit quaternions
    q1 := rl.QuaternionNormalize(q1)
    q2 := rl.QuaternionNormalize(q2)

    relativeRotation := q2 * rl.QuaternionInvert(q1);
    axis, angle := rl.QuaternionToAxisAngle(relativeRotation);
    return angle
}


N_DICES :: 6
N_PLAYERS :: 2
Player :: struct {
	score: i32,
	color: rl.Color,
}
players: [N_PLAYERS]Player
current_player_id: u32 = 0

State :: enum {
	WAIT_FOR_ROLL,
	ROLLING,
	COUNTING,
}
state := State.WAIT_FOR_ROLL
counting_countdown: f32 = 0.0

side_view := false
AREA_SIZE: f32 = 20.0
DICE_SIZE: f32 = 1.0
HALF_SIZE := DICE_SIZE / 2

DIRECTION := 0

main :: proc() {
	// Initialize window
	screen_width :: 1600*2
	screen_height :: 900*2
	fmt.println(
		"Screen size:",
		screen_width,
		"x",
		screen_height,
		"Real size:",
		rl.GetScreenWidth(),
		"x",
		rl.GetScreenHeight(),
	)

	players[0].color = rl.Color{203, 161, 53, 255}
	players[1].color = rl.Color{255, 41, 156, 255}

	rl.InitWindow(screen_width, screen_height, "Rolls")
	defer rl.CloseWindow()

	CAMERA_HEIGHT: f32 = 30.0
	camera := rl.Camera3D{}
	camera.position = rl.Vector3{2., CAMERA_HEIGHT, 0.}
	camera.target = rl.Vector3{0.0, 0.0, 0.0}
	camera.up = rl.Vector3{0.0, 1.0, 0.0}
	camera.fovy = f32(40) // Camera field-of-view Y
	camera.projection = .PERSPECTIVE // Camera mode type

	{ // Clear everything so we don't get welcomed by a white screen
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		rl.BeginMode3D(camera)
		defer rl.EndMode3D()

		rl.DrawCube(rl.Vector3{0.0, -0.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE) // Draw a big cube to represent the area where the dices can move
	}

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	sounds := [?]rl.Sound {
		rl.LoadSound("assets/sounds/dice_1.wav"),
		rl.LoadSound("assets/sounds/dice_2.wav"),
		rl.LoadSound("assets/sounds/dice_3.wav"),
		rl.LoadSound("assets/sounds/dice_4.wav"),
		rl.LoadSound("assets/sounds/dice_5.wav"),
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

	dices: [dynamic]Dice

	charging := false
	charge_start_time: f64 = 0.0

	rl.SetTargetFPS(60)

	ROT := rl.Vector3{0, 0, 0}

	// Main game loop
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// Rotate the camera by using the mouse:
		if rl.IsMouseButtonDown(rl.MouseButton.RIGHT) {
			delta_x := f32(rl.GetMouseDelta().x)
			delta_y := f32(rl.GetMouseDelta().y)

			if side_view {
				camera.position.x += delta_x * 0.1
			} else {
				camera.position.y += delta_y * 0.1
				camera.position.y = math.max(1.0, camera.position.y) // Don't allow the camera to go below the ground
			}
		}

		if rl.IsKeyPressed(rl.KeyboardKey.R) && len(dices) > 1 {
			// Remove all dices except the first one:
			length := len(dices)
			for i in 0 ..< length - 1 {
				pop(&dices)
			}
		}

		if rl.IsKeyPressed(rl.KeyboardKey.W) {
			side_view = !side_view
			if side_view {
				camera.position = rl.Vector3{CAMERA_HEIGHT, 0., 0.}
			} else {
				camera.position = rl.Vector3{2., CAMERA_HEIGHT, 0.}
			}
		}

		if state == .WAIT_FOR_ROLL && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			charging = true
			charge_start_time = rl.GetTime()
		}

		// Max power is reached after 3 seconds of charging)
		power := f32(math.min(1.0, (rl.GetTime() - charge_start_time) / 0.25))

		// if charging &&
		// 	((current_player_id == 0 && rl.IsKeyReleased(rl.KeyboardKey.SPACE)) ||
		// 		(current_player_id == 1 && power >= 1.0)) {
		first_round := len(dices) == 0

		if first_round{
			charging = false

			if first_round {
				// If there are no dices, add some dices before resetting them
				for i in 0 ..< N_DICES * 2 {
					append(&dices, Dice{player = i < N_DICES ? 0 : 1})
				}
			}

			// Throw the dices
			for dice, i in dices {
				dices[i].current_score = 0 // Reset score for all dices before counting
				if !first_round && dice.player != current_player_id {
					continue // Only throw the dices of the current player
				}
				dices[i].on_ground = false
				dices[i].position = rl.Vector3{
					f32(i%N_DICES)*2.-5., 0.5,//rand.float32_range(4, 10)
					dice.player == 0 ? -5.0 : 5.0, // Start on the left or right side depending on the player
				}
				dices[i].velocity = 0.0 * power * rl.Vector3{
					rand.float32_range(-50, 20), 0.0, rand.float32_range(30, 100)
				}
				dices[i].rot_vel = power * rl.Vector3{0, 0, 0} * 0.0
				dices[i].rotation = rl.QuaternionFromEuler(
					0, 0, 0
					//rand.float32_range(0, math.TAU), rand.float32_range(0, math.TAU), rand.float32_range(0, math.TAU),
				)
			}

			// Switch state
			current_player_id = (current_player_id + 1) % N_PLAYERS
			state = .ROLLING
		}

		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		rl.BeginMode3D(camera)

		rl.DrawCube(rl.Vector3{0.0, -0.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE) // Draw a big cube to represent the area where the dices can move

		restitution :: 0.2

		ready_to_count := true
		for &dice, i in dices {
			// on_ground := collides_with_ground(dice)

			dice.velocity.y += -9.81 * dt
			dice.position += dice.velocity * dt

			// Keep the dices inside the area:
			impact := [3]bool{false, false, false}
			for axis in 0 ..< 3 {
				area_limit := rl.Vector2 {-AREA_SIZE / 2 + HALF_SIZE, AREA_SIZE / 2 - HALF_SIZE}
				if axis == 1 {
					// Allow the dice to go up infinitely, but not below the ground
					area_limit = rl.Vector2{0.5, 100.0}
				}
				if dice.position[axis] <= area_limit[0] {
					dice.position[axis] = area_limit[0]
					dice.velocity[axis] *= -1.
					impact[axis] = true
				} else if dice.position[axis] >= area_limit[1] {
					dice.position[axis] = area_limit[1]
					dice.velocity[axis] *= -1.
					impact[axis] = true
				}
			}

			if any_true(impact) {
				dice.velocity *= restitution
			}

			// Add some random rotation on bounce

			// Handle collision with the ground
			// if on_ground {
			// 	dices[i].on_ground = true
			// 	//dices[i].position.y = 0.5 // Stop at ground level
			// 	dices[i].velocity.y *= -0.3 // Bounce with damping
			// 	// Add some random horizontal velocity on bounce)
			// 	speed = math.abs(dices[i].velocity.y)
			// 	dices[i].velocity.x *= 0.3
			// 	dices[i].velocity.z *= 0.3
			// 	if rand.float32() < 0.5 {
			// 		dices[i].velocity.x *= -1.
			// 		dices[i].velocity.z *= -1.
			// 	}

			// 	// We treat y rot velocity differently because it doesn't affect the outcome
			// 	dices[i].rot_vel.y *= 0.8

			// 	// dices[i].rotation *= 0.9 // Add some damping to the rotation so that it will eventually stop

			// 	impact = true
			// } else {
			// 	dices[i].on_ground = false

			// 	// Handle collision with other dices
			// 	for other_dice, j in dices {
			// 		if i == j || !collides(dice, other_dice) {
			// 			continue
			// 		}

			// 		// Simple elastic collision response
			// 		dices[i].velocity, dices[j].velocity = dices[j].velocity, dices[i].velocity
			// 		// dices[i].rot_vel *= 0.9 // Add some damping to the rotation on collision
			// 		// dices[j].rot_vel *= 0.9

			// 		// Move the dices apart to prevent them from sticking together
			// 		direction := dices[i].position - dices[j].position
			// 		direction =
			// 			direction /
			// 			math.sqrt(
			// 				direction.x * direction.x +
			// 				direction.y * direction.y +
			// 				direction.z * direction.z,
			// 			) // Normalize
			// 		dices[i].position += direction * 0.1
			// 		dices[j].position -= direction * 0.1

			// 		// We treat y rot velocity differently because it doesn't affect the outcome
			// 		dices[i].rot_vel.y *= 0.85
			// 		dices[j].rot_vel.y *= 0.85

			// 		if dices[j].on_ground {
			// 			dices[j].position.y = 0.5
			// 		}
			// 	}
			// }

			// if impact && speed > 0.1 {
			// 	// Play a random dice sound on bounce
			// 	sound := rand.choice(sounds[:])
			// 	rl.SetSoundVolume(sound, math.min(1.0, speed / 10.0)) // Set volume based on bounce speed
			// 	rl.SetSoundPitch(sound, rand.float32_range(0.8, 1.2)) // Add some random pitch variation
			// 	rl.PlaySound(sound)
			// }

			// if !on_ground {
			// 	// We don't need to apply gravity if the dice is on the ground, otherwise it will jitter a lot because of the bounces
			// 	dices[i].velocity.y -= 9.81 * dt // Apply gravity
			// }


			// // Calculate the angle to the nearest flat position (0, 90, 180, 270)
			// rotation := math.DEG_PER_RAD * rl.QuaternionToEuler(dice.rotation).yzx
			// angle_to_flat := i32(rotation.x) / 90 * 90
			// dices[i].rot_vel.x = 0.5 * (f32(angle_to_flat) - rotation.x)
			// angle_to_flat = i32(rotation.z) / 90 * 90
			// dices[i].rot_vel.z = 0.5 * (f32(angle_to_flat) - rotation.z)

			// rot_speed := math.to_radians(rl.Vector3Length(dice.rot_vel))
			// if rot_speed > 0. {
			// 	rot_axis := rl.Vector3Normalize(dice.rot_vel)
			// 	delta := rl.QuaternionFromAxisAngle(rot_axis, rot_speed * dt)
			// 	dice.rotation = rl.QuaternionNormalize(delta * dice.rotation)
			// }

			speed := rl.Vector3Length(dice.velocity)

			if impact.y && speed < 0.1 {
				speed = 0.0
				dice.velocity = {}
				dice.rot_vel = {}
				dice.position.y = 0.5
			}

			if speed >= 0.001 {
				ready_to_count = false
			}

			// update_dice(&dices[i], dt)
			draw_dice(
				dices[i].position,
				dices[i].rotation,
				players[dice.player].color,
				1.0,
				textures[0],
			)
		}

		info := -1
		if rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			DIRECTION = (DIRECTION + 1) % 3
		}

		if len(dices) > 0 && rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
			mouse_ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), camera)
			for &dice, i in dices {
				collision := rl.GetRayCollisionBox(
					mouse_ray,
					rl.BoundingBox {
						min = dice.position - rl.Vector3{0.5, 0.5, 0.5},
						max = dice.position + rl.Vector3{0.5, 0.5, 0.5},
					},
				)
				if collision.hit {
					info = i
					turn := rl.Vector3{0, 0, 0}
					turn[DIRECTION] = 1.
					turn *= math.PI / 2
					dice.rotation *= rl.QuaternionFromEuler(turn.x, turn.y, turn.z)
					dice.rotation = rl.QuaternionNormalize(dice.rotation)
					closest_dice := dice
					fmt.println("\nPosition:", closest_dice.position)
					rotation := math.DEG_PER_RAD * rl.QuaternionToEuler(closest_dice.rotation)
					fmt.println("Rotation:", closest_dice.rotation)
					angle_to_flat_x := i32(rotation.x + 45) / 90 * 90
					angle_to_flat_z := i32(rotation.z + 45) / 90 * 90
					fmt.println("Closest to Flat:", angle_to_flat_x, angle_to_flat_z)
					fmt.println("Velocity:", closest_dice.velocity, "Speed:", rl.Vector3Length(closest_dice.velocity))
					break
				}
			}
		}

		if ready_to_count {
			// Count the score for the current player based on the number of dice that are lying flat on the ground with a certain face up
			for &dice, d in dices {
				// Determine which face is up
				// by checking an imaginary point on each face and seeing which is the highest in the y direction after rotation
				best_face := 0
				best_height :f32= -1.0
				for face in 1 ..= 6 {
					transform := rl.QuaternionToMatrix(dice.rotation)

					// x, y, z coordinates of a point in the center of each face of the cube before rotation
					point := rl.Vector3{0, 0, -1} // Front Face (1)
					if face == 2 {
						point = rl.Vector3{1, 0, 0} // Left (2)
					} else if face == 3 {
						point = rl.Vector3{0, 1, 0} // Top (3)
					} else if face == 4 {
						point = rl.Vector3{0, -1, 0} // Bottom (4)
					} else if face == 5 {
						point = rl.Vector3{-1, 0, 0} // Right (5)
					} else if face == 6 {
						point = rl.Vector3{0, 0, 1} // Back (6)
					}

					height := rl.Vector3Transform(point, transform).y
					if info == d do fmt.println("Face", face, "height:", height)
					if height > best_height {
						best_height = height
						best_face = face
					}
				}

				dice.number_on_top = u8(best_face)
				dice.current_score = i32(dice.number_on_top)
			}
			state = .COUNTING
		}

		rl.EndMode3D()

		font_size: i32 = 100
		text := fmt.tprintf("%v", players[0].score)
		rl.DrawText(
			strings.clone_to_cstring(text, context.temp_allocator),
			100,
			screen_height - 200,
			font_size,
			players[0].color,
		)
		text = fmt.tprintf("%v", players[1].score)
		rl.DrawText(
			strings.clone_to_cstring(text, context.temp_allocator),
			screen_width - 200,
			screen_height - 200,
			font_size,
			players[1].color,
		)

		rl.DrawFPS(10, 10)

		if state == .COUNTING {
			// counting_countdown += dt

			ratio :f32= 0.1//counting_countdown / 0.5

			if ratio >= 1.0 {
				// After the counting animation is done, add the current score of each dice to the player's total score and reset the current score of each dice
				for dice, i in dices {
					players[dice.player].score += dice.current_score
					dices[i].current_score = 0
				}
				counting_countdown = 0.0
				// state = .WAIT_FOR_ROLL
			} else {
				for dice in dices {
					if dice.current_score != 0 {
						text := fmt.tprintf("+%v", dice.current_score)
						screen_position := rl.GetWorldToScreen(
							rl.Vector3{dice.position.x, dice.position.y + 0.5, dice.position.z},
							camera,
						)

						// Move the text towards the player's score display
						target_x: f32 = dice.player == 0 ? 100. : f32(screen_width) - 200.
						target_y: f32 = f32(screen_height) - 200.
						screen_position.x += f32(target_x - screen_position.x) * ratio
						screen_position.y += f32(target_y - screen_position.y) * ratio

						rl.DrawText(
							strings.clone_to_cstring(text, context.temp_allocator),
							i32(screen_position.x - 4),
							i32(screen_position.y - 4),
							(font_size / 2)+10,
							rl.BLACK,
						)
						rl.DrawText(
							strings.clone_to_cstring(text, context.temp_allocator),
							i32(screen_position.x),
							i32(screen_position.y),
							font_size / 2,
							players[dice.player].color,
						)
					}
				}
			}
		}

		if charging && current_player_id == 0 {
			// Draw a power bar at the center of the screen
			width: i32 = 800
			height: i32 = 80
			x: i32 = (screen_width - width) / 2
			y: i32 = (screen_height - height) / 2
			rl.DrawRectangle(x, y, i32(power * f32(width)), height, rl.GREEN)
			rl.DrawRectangleLines(x, y, width, height, rl.BLACK)
		}

		// Free the temp arena at the end of the frame
		free_all(context.temp_allocator)
	}
}
