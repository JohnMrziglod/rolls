package game

import "core:math/rand"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

draw_dice :: proc(
	dice: Dice,
	texture: rl.Texture2D,
) {
	size := dice.shape.(ShapeBox).half_size * 2.

	rlgl.SetTexture(texture.id)
	t_w: f32 : 1.0 / 6.0 // Texture has 6 columns for the different orientations of the numbers
	t_h: f32 : 1.0 // Texture has 1 row for the numbers 1-6

	rlgl.PushMatrix()

	rot_matrix := body_get_gl_transform(dice)
	rlgl.MultMatrixf(raw_data(&rot_matrix))

	// Draw the numbers on each face of the cube
	rlgl.Begin(rlgl.QUADS)
	color := dice.color
	if dice.state != .ALIVE {
		color /= 2
	}
	rlgl.Color4ub(color.r, color.g, color.b, color.a)

	// Front face (1)
	rlgl.Normal3f(0.0, 0.0, 1.0) // Normal pointing towards viewer
	rlgl.TexCoord2f(0.0, 0.0); rlgl.Vertex3f(-size / 2, -size / 2, size / 2) // Bottom-left
	rlgl.TexCoord2f(t_w, 0.0); rlgl.Vertex3f(size / 2, -size / 2, size / 2) // Bottom-right
	rlgl.TexCoord2f(t_w, t_h); rlgl.Vertex3f(size / 2, size / 2, size / 2) // Top-right
	rlgl.TexCoord2f(0.0, t_h); rlgl.Vertex3f(-size / 2, size / 2, size / 2) // Top-left

	// Left face (2)
	rlgl.Normal3f(-1.0, 0.0, 0.0) // Normal pointing left
	rlgl.TexCoord2f(t_w, 0.0); rlgl.Vertex3f(-size / 2, -size / 2, -size / 2) // Bottom-left
	rlgl.TexCoord2f(2 * t_w, 0.0); rlgl.Vertex3f(-size / 2, -size / 2, size / 2) // Bottom-right
	rlgl.TexCoord2f(2 * t_w, t_h); rlgl.Vertex3f(-size / 2, size / 2, size / 2) // Top-right
	rlgl.TexCoord2f(t_w, t_h); rlgl.Vertex3f(-size / 2, size / 2, -size / 2) // Top-left

	// Top face (3)
	rlgl.Normal3f(0.0, 1.0, 0.0) // Normal pointing up
	rlgl.TexCoord2f(2 * t_w, 0.0); rlgl.Vertex3f(-size / 2, size / 2, size / 2) // Bottom-left
	rlgl.TexCoord2f(3 * t_w, 0.0); rlgl.Vertex3f(size / 2, size / 2, size / 2) // Bottom-right
	rlgl.TexCoord2f(3 * t_w, t_h); rlgl.Vertex3f(size / 2, size / 2, -size / 2) // Top-right
	rlgl.TexCoord2f(2 * t_w, t_h); rlgl.Vertex3f(-size / 2, size / 2, -size / 2) // Top-lefts

	// Bottom face (4)
	rlgl.Normal3f(0.0, -1.0, 0.0) // Normal pointing down
	rlgl.TexCoord2f(3 * t_w, 0.0); rlgl.Vertex3f(-size / 2, -size / 2, -size / 2) // Bottom-left
	rlgl.TexCoord2f(4 * t_w, 0.0); rlgl.Vertex3f(size / 2, -size / 2, -size / 2) // Bottom-right
	rlgl.TexCoord2f(4 * t_w, t_h); rlgl.Vertex3f(size / 2, -size / 2, size / 2) // Top-right
	rlgl.TexCoord2f(3 * t_w, t_h); rlgl.Vertex3f(-size / 2, -size / 2, size / 2) // Top-left

	// Right face (5)
	rlgl.Normal3f(1.0, 0.0, 0.0) // Normal pointing right
	rlgl.TexCoord2f(4 * t_w, 0.0); rlgl.Vertex3f(size / 2, -size / 2, size / 2) // Bottom-left
	rlgl.TexCoord2f(5 * t_w, 0.0); rlgl.Vertex3f(size / 2, -size / 2, -size / 2) // Bottom-right
	rlgl.TexCoord2f(5 * t_w, t_h); rlgl.Vertex3f(size / 2, size / 2, -size / 2) // Top-right
	rlgl.TexCoord2f(4 * t_w, t_h); rlgl.Vertex3f(size / 2, size / 2, size / 2) // Top-left

	// Back face (6)
	rlgl.Normal3f(0.0, 0.0, -1.0) // Normal pointing away from viewer
	rlgl.TexCoord2f(5 * t_w, 0.0); rlgl.Vertex3f(size / 2, -size / 2, -size / 2) // Bottom-right
	rlgl.TexCoord2f(6 * t_w, 0.0); rlgl.Vertex3f(-size / 2, -size / 2, -size / 2) // Bottom-left
	rlgl.TexCoord2f(6 * t_w, t_h); rlgl.Vertex3f(-size / 2, size / 2, -size / 2) // Top-left
	rlgl.TexCoord2f(5 * t_w, t_h); rlgl.Vertex3f(size / 2, size / 2, -size / 2) // Top-right

	rlgl.End()

	rlgl.PopMatrix()
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
