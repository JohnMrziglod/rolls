package game

// import "core:math"
// import rl "vendor:raylib"
// import rlgl "vendor:raylib/rlgl"

// main :: proc() {

// 	rl.InitWindow(1600, 900, "Test rotation with quaternions")
// 	defer rl.CloseWindow()

// 	rl.SetTargetFPS(60)

// 	// Set up 3D camera
// 	camera := rl.Camera3D{}
// 	camera.position = rl.Vector3{10., 30.0, 0.}
// 	camera.target = rl.Vector3{0.0, 0.0, 0.0}
// 	camera.up = rl.Vector3{0.0, 1.0, 0.0}
// 	camera.fovy = f32(40)
// 	camera.projection = .PERSPECTIVE

// 	cube_position := rl.Vector3{4.5, 4.5, 0.5}
// 	cube_orientation := rl.Quaternion(1)

// 	for !rl.WindowShouldClose() {

// 		// HERE -> Rotate 45 degrees around the cube's Y-axis
// 		rotate_cube_by_this := rl.QuaternionFromEuler(0., math.to_radians_f32(45.), 0.)
// 		// except when space is held down, then reset the rotation to 0
// 		if rl.IsKeyDown(rl.KeyboardKey.SPACE){
// 			rotate_cube_by_this = rl.QuaternionFromEuler(0., 0., 0.)
// 		}

// 		rl.BeginDrawing()
// 		defer rl.EndDrawing()

// 		rl.ClearBackground(rl.RAYWHITE)

// 		rl.BeginMode3D(camera)
// 		defer rl.EndMode3D()

// 		rl.DrawGrid(10, 1.0)

// 		// Draw a simple cube with a rotation
// 		rlgl.PushMatrix()
// 			rlgl.Translatef(cube_position.x, cube_position.y, cube_position.z)

// 			// HERE -> might be the problem?
// 			new_rotation := rl.QuaternionNormalize(rotate_cube_by_this * cube_orientation)
// 			rot_matrix := rl.QuaternionToMatrix(new_rotation)
// 			rlgl.MultMatrixf(&rot_matrix[0,0])

// 			// Draw each side of the cube with different colors
// 			size :f32= 1.0
// 			rlgl.Begin(rlgl.QUADS)
// 				// Front face (1) - RED
// 				rlgl.Color4ub(255, 0, 0, 255)
// 				rlgl.Normal3f(0.0, 0.0, 1.0) // Normal pointing towards viewer
// 				rlgl.Vertex3f(-size/2, -size/2, size/2) // Bottom-left
// 				rlgl.Vertex3f(size/2, -size/2, size/2) // Bottom-right
// 				rlgl.Vertex3f(size/2, size/2, size/2) // Top-right
// 				rlgl.Vertex3f(-size/2, size/2, size/2) // Top-left

// 				// Back face (6) - GREEN
// 				rlgl.Color4ub(0, 255, 0, 255)
// 				rlgl.Normal3f(0.0, 0.0, -1.0) // Normal pointing away from viewer
// 				rlgl.Vertex3f(size/2, -size/2, -size/2) // Bottom-right
// 				rlgl.Vertex3f(-size/2, -size/2, -size/2) // Bottom-left
// 				rlgl.Vertex3f(-size/2, size/2, -size/2) // Top-left
// 				rlgl.Vertex3f(size/2, size/2, -size/2) // Top-right

// 				// Left face (2) - BLUE
// 				rlgl.Color4ub(0, 0, 255, 255)
// 				rlgl.Normal3f(-1.0, 0.0, 0.0) // Normal pointing left
// 				rlgl.Vertex3f(-size/2, -size/2, -size/2) // Bottom-left
// 				rlgl.Vertex3f(-size/2, -size/2, size/2) // Bottom-right
// 				rlgl.Vertex3f(-size/2, size/2, size/2) // Top-right
// 				rlgl.Vertex3f(-size/2, size/2, -size/2) // Top-left

// 				// Right face (5) - MAGENTA
// 				rlgl.Color4ub(255, 0, 255, 255)
// 				rlgl.Normal3f(1.0, 0.0, 0.0) // Normal pointing right
// 				rlgl.Vertex3f(size/2, -size/2, size/2) // Bottom-left
// 				rlgl.Vertex3f(size/2, -size/2, -size/2) // Bottom-right
// 				rlgl.Vertex3f(size/2, size/2, -size/2) // Top-right
// 				rlgl.Vertex3f(size/2, size/2, size/2) // Top-left

// 				// Top face (3) - GOLD
// 				rlgl.Color4ub(150, 150, 0, 255)
// 				rlgl.Normal3f(0.0, 1.0, 0.0) // Normal pointing up
// 				rlgl.Vertex3f(-size/2, size/2, size/2) // Bottom-left
// 				rlgl.Vertex3f(size/2, size/2, size/2) // Bottom-right
// 				rlgl.Vertex3f(size/2, size/2, -size/2) // Top-right
// 				rlgl.Vertex3f(-size/2, size/2, -size/2) // Top-lefts

// 				// Bottom face (4) - YELLOW
// 				rlgl.Color4ub(255, 255, 0, 255)
// 				rlgl.Normal3f(0.0, -1.0, 0.0) // Normal pointing down
// 				rlgl.Vertex3f(-size/2, -size/2, -size/2) // Bottom-left
// 				rlgl.Vertex3f(size/2, -size/2, -size/2) // Bottom-right
// 				rlgl.Vertex3f(size/2, -size/2, size/2) // Top-right
// 				rlgl.Vertex3f(-size/2, -size/2, size/2) // Top-left

// 			rlgl.End()

// 		rlgl.PopMatrix()
// 	}
// }
