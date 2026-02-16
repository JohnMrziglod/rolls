package game

import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

AxisAngle :: struct {
	axis: rl.Vector3,
	angle: f32,
}

Dice :: struct {
	position: rl.Vector3,
	velocity: rl.Vector3,
	rotation: rl.Quaternion,
	rot_vel: rl.Vector3,	// deg/sec around each axis
	player: u32,
	on_ground: bool,
	number_on_top: u8,
	current_score: i32,
}

random_unit_vector3 :: proc() -> rl.Vector3 {
    // Random point on unit sphere
    z :f32= rand.float32_range(-1, 1)
    t :f32= rand.float32_range(0, 2 * math.PI) // 0..2π

    r := math.sqrt(1.0 - z*z);

    return rl.Vector3{
        r * math.cos(t),
        r * math.sin(t),
        z,
    };
}

COLOR_TABLE := rl.Color{102, 51, 153, 255}

collides :: proc(dice1, dice2: Dice) -> bool {
	// Check if the two cubes are colliding by checking if their bounding boxes overlap
	half_size :f32= 0.5
	for axis in 0..<3 {
		if math.abs(dice1.position[axis] - dice2.position[axis]) > half_size * 2 {
			return false
		}
	}
	return true
}
collides_with_ground :: proc(dice: Dice) -> bool {
	// Check if any of the corners of the rotated cube are below the ground level (y=0)
	half_size :f32= 0.5
	corners := [8]rl.Vector3{
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

		rotated_x := corner.x*cos_y*cos_z + corner.y*(cos_x*sin_z + sin_x*sin_y*cos_z) + corner.z*(sin_x*sin_z - cos_x*sin_y*cos_z)
		rotated_y := corner.x*(-cos_y*sin_z) + corner.y*(cos_x*cos_z - sin_x*sin_y*sin_z) + corner.z*(sin_x*cos_z + cos_x*sin_y*sin_z)
		rotated_z := corner.x*sin_y + corner.y*(-sin_x*cos_y) + corner.z*(cos_x*cos_y)

		if dice.position.y + rotated_y < 0.0 {
			return true
		}
	}

	return false
}

update_dice :: proc(d: ^Dice, dt: f32) {
    gravity           := f32(-9.81)
    restitution       := f32(0.3)
    friction          := f32(0.8)
    angular_damping   := f32(0.995)
    linear_damping    := f32(0.999)
    half_size         := f32(0.5)

    // --------------------------------------------------
    // 1. Apply gravity
    // --------------------------------------------------
    d.velocity.y += gravity * dt

    // --------------------------------------------------
    // 2. Integrate linear motion
    // --------------------------------------------------
    d.position += d.velocity.x * dt
    d.position.y += d.velocity.y * dt
    d.position.z += d.velocity.z * dt

    // --------------------------------------------------
    // 3. Integrate rotation (deg/sec → radians)
    // --------------------------------------------------
    omega := rl.Vector3{
        x = rl.DEG2RAD * d.rot_vel.x,
        y = rl.DEG2RAD * d.rot_vel.y,
        z = rl.DEG2RAD * d.rot_vel.z,
    }

    delta_angle := omega * dt
    angle := rl.Vector3Length(delta_angle)

    if angle > 0.00001 {
        axis := rl.Vector3Scale(delta_angle, 1.0 / angle)
        dq := rl.QuaternionFromAxisAngle(axis, angle)

        // world space angular velocity
        d.rotation = rl.QuaternionMultiply(dq, d.rotation)
        d.rotation = rl.QuaternionNormalize(d.rotation)
    }

    // --------------------------------------------------
    // 4. Ground collision (simple bottom test)
    // --------------------------------------------------
    bottom := d.position.y - half_size

    if bottom <= 0 {
        d.on_ground = true

        // Snap to ground
        d.position.y = half_size

        if d.velocity.y < 0 {
            d.velocity.y *= -restitution
        }

        // Friction (horizontal damping)
        d.velocity.x *= friction
        d.velocity.z *= friction

        d.rot_vel.x *= friction
        d.rot_vel.z *= friction
    } else {
        d.on_ground = false
    }

    // --------------------------------------------------
    // 5. Global damping
    // --------------------------------------------------
    d.velocity = rl.Vector3Scale(d.velocity, linear_damping)
    d.rot_vel  = rl.Vector3Scale(d.rot_vel, angular_damping)

    // --------------------------------------------------
    // 6. Sleep threshold (stop jitter)
    // --------------------------------------------------
    if d.on_ground &&
       rl.Vector3Length(d.velocity) < 0.05 &&
       rl.Vector3Length(d.rot_vel) < 5.0 {

        d.velocity = rl.Vector3{}
        d.rot_vel  = rl.Vector3{}
    }

    // --------------------------------------------------
    // 7. Determine number on top
    // --------------------------------------------------
    up := rl.Vector3{0, 1, 0}

    local_axes := [6]rl.Vector3{
        { 0, 1, 0},  // 1
        { 0,-1, 0},  // 6
        { 1, 0, 0},  // 3
        {-1, 0, 0},  // 4
        { 0, 0, 1},  // 2
        { 0, 0,-1},  // 5
    }

    best_dot := f32(-1000)
    best_face := 0

    for i in 0..<6 {
        world_dir := rl.Vector3RotateByQuaternion(local_axes[i], d.rotation)
        dot := rl.Vector3DotProduct(world_dir, up)

        if dot > best_dot {
            best_dot = dot
            best_face = i
        }
    }

    d.number_on_top = u8(best_face + 1)
}


draw_dice :: proc(position: rl.Vector3, rotation: rl.Quaternion, color: rl.Color, size: f32, texture: rl.Texture2D) {
	rlgl.SetTexture(texture.id)
	t_w :f32: 1.0 / 6.0 // Texture has 6 columns for the different orientations of the numbers
	t_h :f32: 1.0 // Texture has 1 row for the numbers 1-6

	rlgl.PushMatrix()
	rlgl.Translatef(position.x, position.y, position.z)

	rot_matrix := rl.QuaternionToMatrix(rotation)
	rlgl.MultMatrixf(&rot_matrix[0,0])

	// Draw the numbers on each face of the cube
	rlgl.Begin(rlgl.QUADS)
		rlgl.Color4ub(color.r, color.g, color.b, color.a)

		// Front face (1)
		rlgl.Normal3f(0.0, 0.0, 1.0) // Normal pointing towards viewer
		rlgl.TexCoord2f(0.0, 0.0); rlgl.Vertex3f(-size/2, -size/2, size/2) // Bottom-left
		rlgl.TexCoord2f(t_w, 0.0); rlgl.Vertex3f(size/2, -size/2, size/2) // Bottom-right
		rlgl.TexCoord2f(t_w, t_h); rlgl.Vertex3f(size/2, size/2, size/2) // Top-right
		rlgl.TexCoord2f(0.0, t_h); rlgl.Vertex3f(-size/2, size/2, size/2) // Top-left

		// Back face (6)
		rlgl.Normal3f(0.0, 0.0, -1.0) // Normal pointing away from viewer
		rlgl.TexCoord2f(5*t_w, 0.0); rlgl.Vertex3f(size/2, -size/2, -size/2) // Bottom-right
		rlgl.TexCoord2f(6*t_w, 0.0); rlgl.Vertex3f(-size/2, -size/2, -size/2) // Bottom-left
		rlgl.TexCoord2f(6*t_w, t_h); rlgl.Vertex3f(-size/2, size/2, -size/2) // Top-left
		rlgl.TexCoord2f(5*t_w, t_h); rlgl.Vertex3f(size/2, size/2, -size/2) // Top-right

		// Left face (2)
		rlgl.Normal3f(-1.0, 0.0, 0.0) // Normal pointing left
		rlgl.TexCoord2f(t_w, 0.0); rlgl.Vertex3f(-size/2, -size/2, -size/2) // Bottom-left
		rlgl.TexCoord2f(2*t_w, 0.0); rlgl.Vertex3f(-size/2, -size/2, size/2) // Bottom-right
		rlgl.TexCoord2f(2*t_w, t_h); rlgl.Vertex3f(-size/2, size/2, size/2) // Top-right
		rlgl.TexCoord2f(t_w, t_h); rlgl.Vertex3f(-size/2, size/2, -size/2) // Top-left

		// Right face (5)
		rlgl.Normal3f(1.0, 0.0, 0.0) // Normal pointing right
		rlgl.TexCoord2f(4*t_w, 0.0); rlgl.Vertex3f(size/2, -size/2, size/2) // Bottom-left
		rlgl.TexCoord2f(5*t_w, 0.0); rlgl.Vertex3f(size/2, -size/2, -size/2) // Bottom-right
		rlgl.TexCoord2f(5*t_w, t_h); rlgl.Vertex3f(size/2, size/2, -size/2) // Top-right
		rlgl.TexCoord2f(4*t_w, t_h); rlgl.Vertex3f(size/2, size/2, size/2) // Top-left

		// Top face (3)
		rlgl.Normal3f(0.0, 1.0, 0.0) // Normal pointing up
		rlgl.TexCoord2f(2*t_w, 0.0); rlgl.Vertex3f(-size/2, size/2, size/2) // Bottom-left
		rlgl.TexCoord2f(3*t_w, 0.0); rlgl.Vertex3f(size/2, size/2, size/2) // Bottom-right
		rlgl.TexCoord2f(3*t_w, t_h); rlgl.Vertex3f(size/2, size/2, -size/2) // Top-right
		rlgl.TexCoord2f(2*t_w, t_h); rlgl.Vertex3f(-size/2, size/2, -size/2) // Top-lefts

		// Bottom face (4)
		rlgl.Normal3f(0.0, -1.0, 0.0) // Normal pointing down
		rlgl.TexCoord2f(3*t_w, 0.0); rlgl.Vertex3f(-size/2, -size/2, -size/2) // Bottom-left
		rlgl.TexCoord2f(4*t_w, 0.0); rlgl.Vertex3f(size/2, -size/2, -size/2) // Bottom-right
		rlgl.TexCoord2f(4*t_w, t_h); rlgl.Vertex3f(size/2, -size/2, size/2) // Top-right
		rlgl.TexCoord2f(3*t_w, t_h); rlgl.Vertex3f(-size/2, -size/2, size/2) // Top-left

	rlgl.End()

	rlgl.PopMatrix()
}

N_DICES :: 6
N_PLAYERS :: 2
Player :: struct {
	score: i32,
	color: rl.Color,
}
players: [N_PLAYERS]Player
current_player_id :u32= 0

State :: enum {
	WAIT_FOR_ROLL,
	ROLLING,
	COUNTING,
}
state := State.WAIT_FOR_ROLL
counting_countdown :f32= 0.0

side_view := false
AREA_SIZE :f32= 20.0

main :: proc() {
	// Initialize window
	screen_width :: 1600*2
	screen_height :: 900*2

	players[0].color = rl.Color{203, 161, 53, 255}
	players[1].color = rl.Color{255, 41, 156, 255}

	rl.InitWindow(screen_width, screen_height, "Rolls")
	defer rl.CloseWindow()

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
	textures := [?]rl.Texture2D {
		rl.LoadTexture("assets/textures/dice.png"),
	}
	defer {
		for texture in textures {
			rl.UnloadTexture(texture)
		}
	}

	dices: [dynamic]Dice

	CAMERA_HEIGHT :f32= 30.0

	charging := false
	charge_start_time :f64= 0.0

	// Set up 3D camera
	camera := rl.Camera3D{}
	camera.position = rl.Vector3{2., CAMERA_HEIGHT, 0.}
	camera.target = rl.Vector3{0.0, 0.0, 0.0}
	camera.up = rl.Vector3{0.0, 1.0, 0.0}
	camera.fovy = f32(40) // Camera field-of-view Y
	camera.projection = .PERSPECTIVE // Camera mode type

	rl.SetTargetFPS(60)

	// Main game loop
	for !rl.WindowShouldClose() {

		// Rotate the camera by using the mouse:
		if rl.IsMouseButtonDown(rl.MouseButton.LEFT) {
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
			for i in 0..<length-1 {
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

		if rl.IsKeyPressed(rl.KeyboardKey.A) {
			for i in 0..<N_DICES {
				// Add a new dice at a random position above the ground
				x := rand.float32_range(-10, 10)
				y := rand.float32_range(10, 15)
				z := rand.float32_range(-10, 10)
				dice := Dice {
					position = rl.Vector3{x, y, z},
					velocity = rl.Vector3{x/10., 0.0, z/10.},
					// rotation: rl.Vector3{0.0, 0.0, 0.0},
					player = 0,
				}
				append(&dices, dice)
			}
		}

		if state == .WAIT_FOR_ROLL && rl.IsKeyPressed(rl.KeyboardKey.SPACE) {
			charging = true
			charge_start_time = rl.GetTime()
		}
		// Max power is reached after 3 seconds of charging)
		power := f32(math.min(1.0, (rl.GetTime() - charge_start_time) / 0.25))
		if charging && (
				(current_player_id == 0 && rl.IsKeyReleased(rl.KeyboardKey.SPACE)) || (current_player_id == 1 && power >= 1.0)) {
			charging = false
			first_round := len(dices) == 0

			if first_round {
				// If there are no dices, add some dices before resetting them
				for i in 0..<N_DICES*2 {
					append(&dices, Dice{player=i<N_DICES?0:1})
				}
			}

			// Throw the dices
			for dice, i in dices {
				dices[i].current_score = 0 // Reset score for all dices before counting

				if !first_round && dice.player != current_player_id {
					continue // Only throw the dices of the current player
				}
				x := rand.float32_range(-2, 2)
				z := -rand.float32_range(5, 8)
				y := rand.float32_range(4, 10)
				vx := rand.float32_range(-50, 20) * power
				vz := rand.float32_range(30, 100) * power
				dices[i].on_ground = false
				dices[i].position = rl.Vector3{x, y, z}
				dices[i].velocity = rl.Vector3{vx, 0.0, vz}
				dices[i].rot_vel = rl.Vector3{x, y, z} * 600.0 * power
				dices[i].rotation = rl.QuaternionFromEuler(rand.float32_range(0, 360), rand.float32_range(0, 360), rand.float32_range(0, 360))
			}

			// Switch state
			current_player_id = (current_player_id + 1) % N_PLAYERS
			state = .ROLLING
		}

		// Draw
		rl.BeginDrawing()
		defer rl.EndDrawing()

		rl.ClearBackground(rl.BLACK)

		rl.BeginMode3D(camera)

		// Draw a simple grid
		// rl.DrawGrid(10, 1.0)
		rl.DrawCube(rl.Vector3{0.0, -0.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, COLOR_TABLE) // Draw a big cube to represent the area where the dices can move

		time := rl.GetTime()
		dt := rl.GetFrameTime()

		ready_to_count := true
		for &dice, i in dices {
			on_ground := collides_with_ground(dice)

			// angle_to_flat = i32(math.abs(dices[i].rotation.z)) % 90
			// dices[i].rot_vel.z = 1. * (f32(angle_to_flat) - dices[i].rotation.z)
			// dices[i].rot_vel *= 0.99 // Apply some damping to rotation

			// Keep the dices inside the area:
			impact := false
			if dices[i].position.x < -AREA_SIZE/2 {
				dices[i].position.x = -AREA_SIZE/2
				dices[i].velocity.x *= -0.5
				impact = true
			} else if dices[i].position.x > AREA_SIZE/2 {
				dices[i].position.x = AREA_SIZE/2
				dices[i].velocity.x *= -0.5
				impact = true
			}
			if dices[i].position.z < -AREA_SIZE/2 {
				dices[i].position.z = -AREA_SIZE/2
				dices[i].velocity.z *= -0.5
				impact = true
			} else if dices[i].position.z > AREA_SIZE/2 {
				dices[i].position.z = AREA_SIZE/2
				dices[i].velocity.z *= -0.5
				impact = true
			}

			// Add some random rotation on bounce
			speed := math.abs(dices[i].velocity.y)

			// Handle collision with the ground
			if on_ground {
				dices[i].on_ground = true
				//dices[i].position.y = 0.5 // Stop at ground level
				dices[i].velocity.y *= -0.3 // Bounce with damping
				// Add some random horizontal velocity on bounce)
				speed = math.abs(dices[i].velocity.y)
				dices[i].velocity.x *= 0.3
				dices[i].velocity.z *= 0.3
				if rand.float32() < 0.5 {
					dices[i].velocity.x *= -1.
					dices[i].velocity.z *= -1.
				}

				// We treat y rot velocity differently because it doesn't affect the outcome
				dices[i].rot_vel.y *= 0.8

				// dices[i].rotation *= 0.9 // Add some damping to the rotation so that it will eventually stop

				impact = true
			} else {
				dices[i].on_ground = false

				// Handle collision with other dices
				for other_dice, j in dices {
					if i == j || !collides(dice, other_dice) {
						continue
					}

					// Simple elastic collision response
					dices[i].velocity, dices[j].velocity = dices[j].velocity, dices[i].velocity
					// dices[i].rot_vel *= 0.9 // Add some damping to the rotation on collision
					// dices[j].rot_vel *= 0.9

					// Move the dices apart to prevent them from sticking together
					direction := dices[i].position - dices[j].position
					direction = direction / math.sqrt(direction.x*direction.x + direction.y*direction.y + direction.z*direction.z) // Normalize
					dices[i].position += direction * 0.1
					dices[j].position -= direction * 0.1

					// We treat y rot velocity differently because it doesn't affect the outcome
					dices[i].rot_vel.y *= 0.85
					dices[j].rot_vel.y *= 0.85

					if dices[j].on_ground {
						dices[j].position.y = 0.5
					}
				}
			}

			if impact && speed > 0.1 {
				// Play a random dice sound on bounce
				sound := rand.choice(sounds[:])
				rl.SetSoundVolume(sound, math.min(1.0, speed/10.0)) // Set volume based on bounce speed
				rl.SetSoundPitch(sound, rand.float32_range(0.8, 1.2)) // Add some random pitch variation
				rl.PlaySound(sound)
			}

			if !on_ground {
				// We don't need to apply gravity if the dice is on the ground, otherwise it will jitter a lot because of the bounces
				dices[i].velocity.y -= 9.81 * dt // Apply gravity
			}

			dice.position += dice.velocity * dt // Update position

			// Calculate the angle to the nearest flat position (0, 90, 180, 270)
			rotation := math.DEG_PER_RAD * rl.QuaternionToEuler(dice.rotation)
			angle_to_flat := i32(rotation.x)/90 * 90
			dices[i].rot_vel.x = 0.5 * (f32(angle_to_flat) - rotation.x)
			angle_to_flat = i32(rotation.z)/90 * 90
			dices[i].rot_vel.z = 0.5 * (f32(angle_to_flat) - rotation.z)

			rot_speed := math.to_radians(rl.Vector3Length(dice.rot_vel))
			if rot_speed > 0.{
				rot_axis := rl.Vector3Normalize(dice.rot_vel)
				delta := rl.QuaternionFromAxisAngle(rot_axis, rot_speed * dt)
				dice.rotation = rl.QuaternionNormalize(delta * dice.rotation)
			}

			// dices[i].rotation += dices[i].rot_vel * dt
			// limit the rotation to 0-360 degrees
			// dices[i].rotation.x = math.mod(dices[i].rotation.x+360, 360)
			// dices[i].rotation.y = math.mod(dices[i].rotation.y+360, 360)
			// dices[i].rotation.z = math.mod(dices[i].rotation.z+360, 360)


			if !dices[i].on_ground || math.sum(dices[i].velocity[:]) >= 0.001 {// || math.sum(dices[i].rot_vel[:]) >= 0.001 {
				ready_to_count = false
			}

			draw_dice(dices[i].position, dices[i].rotation, players[dice.player].color, 1.0, textures[0])
		}

		if len(dices) > 0 && rl.IsMouseButtonPressed(rl.MouseButton.RIGHT) {
			mouse_ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), camera)
			for dice in dices {
				collision := rl.GetRayCollisionBox(
					mouse_ray, rl.BoundingBox{min=dice.position - rl.Vector3{0.5, 0.5, 0.5}, max=dice.position + rl.Vector3{0.5, 0.5, 0.5}})
				if collision.hit {
					closest_dice := dice
					fmt.println("\nPosition:", closest_dice.position)
					rotation := math.DEG_PER_RAD * rl.QuaternionToEuler(closest_dice.rotation)
					fmt.println("Rotation:", rotation)
					angle_to_flat_x := i32(rotation.x+45)/90 * 90
					angle_to_flat_z := i32(rotation.z+45)/90 * 90
					fmt.println("Angle to flat:", angle_to_flat_x, angle_to_flat_z)
					fmt.println(rotation.x-f32(angle_to_flat_x), rotation.z-f32(angle_to_flat_z), closest_dice.rot_vel)
					break
				}
			}
		}

		if ready_to_count && state == .ROLLING {
			// Count the score for the current player based on the number of dice that are lying flat on the ground with a certain face up
			for dice, i in dices {
				// Determine which face is up based on the rotation of the dice
				// This is a simplified version and may not be entirely accurate, but it should work well enough for our purposes
				rotation_x := i32(math.abs(dice.rotation.x)) % 360
				rotation_z := i32(math.abs(dice.rotation.z)) % 360

				number_on_top :u8= 3
				if (rotation_x < 45 || rotation_x >= 315) && (rotation_z < 45 || rotation_z >= 315) {
					number_on_top = 1
				} else if (rotation_x >= 45 && rotation_x < 135) && (rotation_z < 45 || rotation_z >= 315) {
					number_on_top = 2
				} else if (rotation_x >= 135 && rotation_x < 225) && (rotation_z < 45 || rotation_z >= 315) {
					number_on_top = 6
				} else if (rotation_x >= 225 && rotation_x < 315) && (rotation_z < 45 || rotation_z >= 315) {
					number_on_top = 5
				} else if (rotation_z >= 45 && rotation_z < 135) {
					number_on_top = 4
				}

				dices[i].number_on_top = number_on_top
				dices[i].current_score += i32(number_on_top)
			}
			state = .COUNTING
		}

		rl.EndMode3D()

		font_size :i32= 100
		text := fmt.tprintf("%v", players[0].score)
		rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), 100, screen_height-200 , font_size, players[0].color)
		text = fmt.tprintf("%v", players[1].score)
		rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), screen_width-200, screen_height-200, font_size, players[1].color)

		rl.DrawFPS(10, 10)

		if state == .COUNTING {
			counting_countdown += dt

			ratio := counting_countdown / 0.5

			if ratio >= 1.0 {
				// After the counting animation is done, add the current score of each dice to the player's total score and reset the current score of each dice
				for dice, i in dices {
					players[dice.player].score += dice.current_score
					dices[i].current_score = 0
				}
				counting_countdown = 0.0
				state = .WAIT_FOR_ROLL
			} else {
				for dice in dices {
					if dice.current_score != 0 {
						text := fmt.tprintf("+%v", dice.current_score)
						screen_position := rl.GetWorldToScreen(rl.Vector3{dice.position.x, dice.position.y + 0.5, dice.position.z}, camera)

						// Move the text towards the player's score display
						target_x :f32= dice.player == 0 ? 100 : screen_width - 200
						target_y :f32= screen_height - 200
						screen_position.x += f32(target_x - screen_position.x) * ratio
						screen_position.y += f32(target_y - screen_position.y) * ratio

						rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), i32(screen_position.x+1), i32(screen_position.y+1), font_size/2, rl.BLACK)
						rl.DrawText(strings.clone_to_cstring(text, context.temp_allocator), i32(screen_position.x), i32(screen_position.y), font_size/2, players[dice.player].color)
					}
				}
			}
		}

		if charging && current_player_id == 0 {
			// Draw a power bar at the center of the screen
			width :i32= 800
			height :i32= 80
			x :i32= (screen_width-width) / 2
			y :i32= (screen_height-height) / 2
			rl.DrawRectangle(x, y, i32(power * f32(width)), height, rl.GREEN)
			rl.DrawRectangleLines(x, y, width, height, rl.BLACK)
		}

		// Free the temp arena at the end of the frame
		free_all(context.temp_allocator)
	}
}
