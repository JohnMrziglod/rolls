package game

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
	rlgl.Color4ub(dice.color.r, dice.color.g, dice.color.b, dice.color.a)

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
