package game

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

AREA_SIZE :: 30.0

EntityState :: enum {
	NOT_USED,
	DEAD,
	ALIVE,
}

Card :: struct {

}
cards := [1000]Card{}

Dice :: struct {
	state: EntityState,
	using box: Box,
	player: u8,
}
dices := [1000]Dice{}

// We use this to limit the throwing area
Plane :: struct {
	direction: Vector3,
	offset: real,
}

// All contact are stored here:
contacts := [dynamic]Contact{}

update :: proc(duration: real){
	for &dice, d in dices{
		if dice.state != .ALIVE {
			continue
		}

		body_integrate(&dice, duration)
		// this only applies the transform matrix to the offset,
		// we don't an offset for dices
		// primitive_calculate_internals(&dice)
	}

	// ground plane
	ground := Plane{direction={0.0, 1.0, 0.0}}

	clear(&contacts)
	for &dice, d in dices{
		if dice.state != .ALIVE || len(contacts) > 1000 do break

		collision_detect_box_plane(&dice, ground, &contacts)

		for other_dice, od in dices{
			if dice == other_dice || other_dice.state != .ALIVE {
				continue
			}

			collision_detect_box_box(dice, other_dice, &contacts)
		}
	}

	resolver := ContactResolver{
		position_iterations=u32(len(contacts)*8), velocity_iterations=u32(len(contacts)*8)
	}
	contact_resolver_resolve_contacts(&resolver, contacts[:], duration)
}

draw :: proc(camera: rl.Camera3D) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)

	rl.BeginMode3D(camera)
	// for p, i in particles {
	// 	rl.DrawCube(p.position, 1.0, 1.0, 1.0, rl.GREEN) // Draw the particle as a cube
	// }
	rl.EndMode3D()

	rl.DrawFPS(10, 10)
}

main :: proc() {
	// Make some dices:
	// for i in 0..<10 {
	// 	dices[i] = Dice{
	// 		state: .ALIVE,
	// 		body: RigidBody{
	// 			position: random_vector(-AREA_SIZE / 2, AREA_SIZE / 2),
	// 			velocity: random_vector(-5.0, 5.0),
	// 			rotation: random_vector(-1.0, 1.0),
	// 			angular_velocity: random_vector(-5.0, 5.0),
	// 			mass: 1.0,
	// 		},
	// 		player: u8(i % 2), // Just for testing, assign the dices to two players
	// 	}
	// }



	// Initialize window
	screen_width :: 1600
	screen_height :: 900
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

		rl.DrawCube(rl.Vector3{0.0, -0.5, 0.0}, AREA_SIZE, 1.0, AREA_SIZE, rl.Color{255, 255, 255, 255}) // Draw a big cube to represent the area where the dices can move
	}

	rl.SetTargetFPS(60)

	// Main game loop
	for !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()

		// update physics:
		update(dt)

		// draw everything:
		draw(camera)
	}
}
