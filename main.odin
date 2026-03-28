package game

import "core:fmt"
import "core:math/rand"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

AREA_SIZE :: 30.0

Card :: struct {

}

Dice :: struct {
	using body: RigidBody,

}
dices := [1000]Dice{}

main :: proc() {
	// Make some particles:
	for i in 0..<1000 {
		particles[i] = make_particle(random_vector(-AREA_SIZE / 2.0, AREA_SIZE / 2.0))
	}



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
		update_physics(dt)

		// draw everything:
		draw(camera)
	}
}

draw :: proc(camera: rl.Camera3D) {
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(rl.BLACK)

	rl.BeginMode3D(camera)
	for p, i in particles {
		rl.DrawCube(p.position, 1.0, 1.0, 1.0, rl.GREEN) // Draw the particle as a cube
	}
	rl.EndMode3D()

	rl.DrawFPS(10, 10)
}
