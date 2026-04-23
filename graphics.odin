package game

import "core:math"
import "core:math/rand"
import "core:unicode/utf8"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

TextAnchor :: enum {
	LEFT,
	RIGHT,
	CENTER,
}

button :: proc(text: string, position: rl.Vector2, size:rl.Vector2={1, 1}, color:rl.Color=rl.BLACK, active_color:rl.Color=rl.BLANK,
		font_size:f32=30, clickable:bool=true, padding:f32=10., anchor:TextAnchor=.LEFT, hover_motion:bool=true) -> bool{
	text_size := measure_text(text, font_size) + padding

	// highlight it if the mouse is hovering over it
	box := rl.Rectangle{
		x = position.x,
		y = position.y,
		width = math.max(size.x, text_size.x), // make sure the button is wide enough to fit the text
		height = math.max(size.y, text_size.y),
	}

	if anchor == .RIGHT do box.x -= box.width
	if anchor == .CENTER do box.x -= box.width / 2.

	hovered := clickable && rl.CheckCollisionPointRec(rl.GetMousePosition(), box)
	if hovered && hover_motion do box.y += math.sin(f32(rl.GetTime())*10)*5	// make the button float up and down a bit

	active_color := active_color == rl.BLANK ? rl.ColorBrightness(color, 1.2) : active_color

	position := rl.Vector2{box.x, box.y}
	draw_box(position-{0, box.height-text_size.y}/2., {box.width, box.height}, color, thickness=0.)
	text_position := position + {box.width-text_size.x, 0} / 2. + padding/2.
	// Debug box for text position
	// rl.DrawRectangleV(text_position, text_size, rl.RED)
	draw_text(text, text_position, font_size, rl.WHITE)


	return hovered && rl.IsMouseButtonPressed(.LEFT)
}

dice_button :: proc(number: i32, position: rl.Vector2, size: f32,
					 color:rl.Color=rl.WHITE, active_color:rl.Color=rl.BLANK, active:bool=false, clickable:bool=true) -> bool{

	if number < 1 || number > 6 do return false

	texture_rect := rl.Rectangle{
		x = f32((number-1)*app.textures[0].width/6),
		y = 0,
		width = f32(app.textures[0].width/6),
		height = f32(app.textures[0].height),
	}
	dest_rect := rl.Rectangle{
		x = position.x,
		y = position.y,
		width = size,
		height = size,
	}

	active_color := active_color == rl.BLANK ? rl.ColorBrightness(color, 1.2) : active_color

	// highlight it if the mouse is hovering over it
	hovered := clickable && rl.CheckCollisionPointRec(rl.GetMousePosition(), dest_rect)
	if hovered do dest_rect.y += math.sin(f32(rl.GetTime())*10)*5	// make the dice float up and down a bit

	tint := active || hovered ? active_color : color
	rl.DrawTexturePro(app.textures[0], texture_rect, dest_rect, {}, 0., tint)

	return hovered && rl.IsMouseButtonPressed(.LEFT)
}

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
	for &particle in app.particles{
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

measure_text :: proc(text: string, font_size: f32, spacing:f32=1.0) -> rl.Vector2 {
	font := app.font
	scale_factor := font_size / f32(font.baseSize)

	width :f32= 0.
	height :f32= 0.

	for r in text{
		if r == '\n' {
			height += 1.5 * f32(font_size)
			width = 0.
			continue
		}

		glyph_index := rl.GetGlyphIndex(font, r)
		glyph := font.glyphs[glyph_index]
		rec := font.recs[glyph_index]
		if glyph.advanceX == 0 {
			width += f32(rec.width) * scale_factor
		} else {
			width += f32(glyph.advanceX) * scale_factor
		}
		width += spacing
		height = math.max(height, f32(glyph.offsetY) + rec.height*scale_factor)
	}

	return rl.Vector2{width, height}
}

draw_text :: proc(text: string, position: rl.Vector2, font_size: f32,
		color: rl.Color=rl.RAYWHITE, spacing:f32=1.0, max_width:f32=-1.,
		strikethrough:bool=false, overline:bool=false,
		anchor:TextAnchor=.LEFT){

	position := position
	if anchor == .RIGHT do position.x -= measure_text(text, font_size).x
	if anchor == .CENTER do position.x -= measure_text(text, font_size).x / 2.

	if max_width < 0. {
		rl.DrawTextEx(app.font,
			strings.clone_to_cstring(text, context.temp_allocator),
			position, font_size, spacing, color)

		text_size := measure_text(text, font_size)

		if strikethrough {
			rl.DrawLineEx(
				position + rl.Vector2{0,  text_size.y / 2.},
				position + rl.Vector2{text_size.x,  text_size.y / 2.},
				font_size / 10., color)
		}

		if overline {
			rl.DrawLineEx(
				position + rl.Vector2{0,  -font_size / 5.},
				position + rl.Vector2{text_size.x,  -font_size / 5.},
				font_size / 10., color)
		}

		return
	}

	font := app.font

	// We need to wrap the text... below is the c function, we have to refactor it into odin...
	text_offset_y := f32(0)
	text_offset_x := f32(0)

	scale_factor := font_size / f32(font.baseSize)

	for r, i in text{
		if r == '\n' {
			text_offset_y += 1.5 * f32(font.baseSize) * scale_factor
			text_offset_x = 0.
			continue
		}

		glyph_width :f32= 0.
		next_word_length :f32= 0.
		for nr, j in text[i:] {
			if j != 0 do next_word_length += spacing

			glyph_index := rl.GetGlyphIndex(font, nr)
			if font.glyphs[glyph_index].advanceX == 0 {
				next_word_length += f32(font.recs[glyph_index].width) * scale_factor
			} else {
				next_word_length += f32(font.glyphs[glyph_index].advanceX) * scale_factor
			}
			if j == 0 do glyph_width = next_word_length

			if text_offset_x + next_word_length > max_width || nr == '\n' {
				if text_offset_x != 0. {
					// we draw it onto the next line
					text_offset_y += 1.5 * f32(font.baseSize) * scale_factor
					text_offset_x = 0.
				}
				break
			}
			// if we fit so far and the next rune is white space, we can stop here...
			if strings.is_space(nr) do break
		}

		if !strings.is_space(r) {
			rl.DrawTextCodepoint(
				font, r,
				position + rl.Vector2{text_offset_x, text_offset_y},
				font_size, color)
		}

		if text_offset_x != 0. || !strings.is_space(r) {
			text_offset_x += glyph_width
		}
	}
}

draw_box :: proc(position: rl.Vector2, size: rl.Vector2,
					fill:rl.Color=rl.BLANK, outline:rl.Color=rl.BLACK, thickness:f32=4.) {
	if fill != rl.BLANK {
		rl.DrawRectangleV(position, size, fill)
	}
	rl.DrawRectangleLinesEx(
		{position.x-thickness, position.y-thickness, size.x+2*thickness, size.y+2*thickness}, thickness, outline)
}

color_brighten :: proc(color: rl.Color, factor: f32) -> rl.Color {
	return rl.Color{
		u8(math.min(f32(color.r) * factor, 255)),
		u8(math.min(f32(color.g) * factor, 255)),
		u8(math.min(f32(color.b) * factor, 255)),
		color.a,
	}
}

draw_card :: proc(id: CardType, position: rl.Vector2, color:rl.Color=rl.BLANK, actions:[]string={}) -> i32{
	size := app.gui.card_size
	hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), {x=position.x, y=position.y, width=f32(size.x), height=f32(size.y)})

	color := color
	category := card_category(id)
	if color == rl.BLANK do color = COLOR_CARDS[category]

	position := position
	if hovered {
		color = rl.ColorBrightness(color, math.sin(f32(rl.GetTime())*2)/5.+0.3)
		position.y += -10. //math.sin(f32(rl.GetTime())*10)*5	// make the button float up and down a bit
	}

	font_size :f32= app.gui.font_size2
	padding :f32= 10
	line_pos := font_size+2*padding
	lt :f32= 4. // line_thickness
	lc := rl.BLACK // color / 2 // line color
	lc.a = color.a

	rl.DrawRectangleV(position, size, color)
	rl.DrawRectangleV(position, {size.x, line_pos}, rl.BLACK)

	rl.DrawRectangleLinesEx({position.x-4, position.y-4, size.x+2*lt, size.y+2*lt}, lt, lc)
	// rl.DrawLineEx({position.x+padding, position.y+line_pos}, {position.x+size.x-padding, position.y+line_pos}, lt, lc)

	// Title
	text_pos := position + {padding, padding}
	text_id := fmt.tprintf("title/%v", id)
	draw_text(app.texts[text_id], text_pos, font_size, rl.RAYWHITE, max_width=size.x-2*padding)

	// Description
	text_pos += {0, line_pos+padding}
	text_id = fmt.tprintf("description/%v", id)
	draw_text(app.texts[text_id], text_pos, font_size, rl.BLACK, max_width=size.x-2*padding)

	if hovered {
		button_pos := position + size + {-10, -35}
		for action, i in actions {
			if button(action, button_pos, font_size=20, anchor=.RIGHT) do return i32(i)
			button_pos += {-130, 0}
		}
		// if button("ASSIGN", button_pos+{-10, 0}, font_size=20, anchor=.RIGHT) do return 1
	}

	return -1
}
