package game

import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:unicode/utf8"
import "core:fmt"
import "core:slice"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

TextureFaceSize :: [2]f32{128., 128.}

TextAnchor :: enum {
	LEFT,
	RIGHT,
	CENTER,
}

Particles :: struct{
	positions: [9]Vector3,
	velocities: [9]Vector3,
	color: rl.Color,
	visible: bool,
	lifetime: f32
}

TextAnimation :: struct{
	start: Vector2,
	end: Vector2,
	text: string,
	color: rl.Color,
	visible: bool,
	font_size: f32,
	lifetime: f32,
	start_lifetime: f32,
	anchor: TextAnchor,
}

button :: proc(text: string, position: rl.Vector2, size:rl.Vector2={1, 1}, color:rl.Color=rl.BLACK, active_color:rl.Color=rl.BLANK,
		font_size:f32=30, clickable:bool=true, padding:f32=10., text_color:=rl.WHITE, anchor:TextAnchor=.LEFT, hover_motion:bool=true) -> bool{
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
	draw_text(text, text_position, font_size, text_color)

	clicked := hovered && rl.IsMouseButtonPressed(.LEFT)
	if clicked {
		sound := app.sounds[12]
		rl.SetSoundVolume(sound, 1.)
		rl.PlaySound(sound)
	}

	return clicked
}

dice_button :: proc(number: i32, position: rl.Vector2, size: f32,
					 color:rl.Color=rl.GRAY/2, active_color:rl.Color=rl.BLANK, active:bool=false, clickable:bool=true) -> bool{

	if number < 1 || number > 6 do return false

	// highlight it if the mouse is hovering over it
	dest_rect := rl.Rectangle{x=position.x, y=position.y, width=size, height=size}
	hovered := clickable && rl.CheckCollisionPointRec(rl.GetMousePosition(), dest_rect)
	if hovered do dest_rect.y += math.sin(f32(rl.GetTime())*10)*5	// make the dice float up and down a bit

	active_color := active_color == rl.BLANK ? rl.ColorBrightness(color, 1.2) : active_color
	tint := active || hovered ? active_color : color
	texture := app.textures[0]
	ts := TextureFaceSize// / {f32(texture.width), f32(texture.height)}
	rl.DrawTexturePro(texture, {x=6.*ts.x, width=ts.x, height=ts.y}, dest_rect, {}, 0., tint)
	rl.DrawTexturePro(texture, {x=f32(number-1)*ts.x, width=ts.x, height=ts.y}, dest_rect, {}, 0., rl.BLACK)

	return hovered && rl.IsMouseButtonPressed(.LEFT)
}

draw_die_face :: proc(face: int, size: f32, texture: rl.Texture, tc: Vector2, ts: Vector2, color: rl.Color, scale:f32=1.){
    size := size + (0.2*(1.-scale))
    size2 := size*scale
    rlgl.Color4ub(color.r, color.g, color.b, color.a)

	// Front face (1)
	switch face{
	case 0:
    	rlgl.Normal3f(0.0, 0.0, 1.0) // Normal pointing left
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size2, -size2, size) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size2, -size2, size) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size2,  size2, size) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size2,  size2, size) // Top-left

	// Left face (2)
	case 1:
    	rlgl.Normal3f(-1.0, 0.0, 0.0) // Normal pointing left
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size, -size2, -size2) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f(-size, -size2,  size2) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f(-size,  size2,  size2) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size,  size2, -size2) // Top-left

	// // Top face (3)
	case 2:
    	rlgl.Normal3f(0.0, 1.0, 0.0) // Normal pointing up
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size2,  size,  size2) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size2,  size,  size2) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size2,  size, -size2) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size2,  size, -size2) // Top-lefts

	// // Bottom face (4)
	case 3:
    	rlgl.Normal3f(0.0, -1.0, 0.0) // Normal pointing down
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size2, -size, -size2) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size2, -size, -size2) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size2, -size,  size2) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size2, -size,  size2) // Top-left

	// // Right face (5)
	case 4:
    	rlgl.Normal3f(1.0, 0.0, 0.0) // Normal pointing right
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f( size, -size2,  size2) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size, -size2, -size2) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size,  size2, -size2) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f( size,  size2,  size2) // Top-left

	// // Back face (6)
	case 5:
    	rlgl.Normal3f(0.0, 0.0, -1.0) // Normal pointing away from viewer
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f( size2, -size2, -size) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f(-size2, -size2, -size) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f(-size2,  size2, -size) // Top-left
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f( size2,  size2, -size) // Top-right
    }
}

draw_die :: proc(dice: Dice, hoverable:bool=false) -> bool {
	size := dice.shape.(ShapeBox).half_size
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), app.camera3d)

    // Check collision between ray and b
    collision := rl.GetRayCollisionBox(ray, {min=dice.position-size, max=dice.position+size})

    color := dice.color1
	if dice.state != .ALIVE do color /= 2
	if hoverable && collision.hit do color = rl.ColorBrightness(color, -0.3)


	// transform: [16]f32, size: f32, texture: rl.Texture, faces: [6][2]f32, color: rl.Color
	transform := body_get_gl_transform(dice)

	texture := app.textures[0]
	fs := TextureFaceSize / {f32(texture.width), f32(texture.height)}

	// start to draw...
	rlgl.SetTexture(texture.id)
	rlgl.PushMatrix()
	rlgl.MultMatrixf(raw_data(&transform))
	rlgl.Begin(rlgl.QUADS)
	defer rlgl.End()
	defer rlgl.PopMatrix()

	// Draw background and borders
	for n, i in dice.faces {
	    draw_die_face(i, size, texture, {f32(6)*fs.x, 0}, fs, color)
	}

	// Draw numbers or upgrades
	for n, f in dice.faces {
	    if dice.upgrades[f].type == .CardNone{
			draw_die_face(f, size, texture, {f32(n-1)*fs.x, 0.}, fs, rl.BLACK)
			continue
		}

		card_type := reflect.enum_string(dice.upgrades[f].type)
		if card_type in app.sub_textures {
		    texture_id := app.sub_textures[card_type]
			draw_die_face(f, size, texture, fs.yx*app.sub_textures[card_type].yx, fs, color)
		} else {
            draw_die_face(f, size, texture, {0., fs.y}, fs, color)
		}

		// draw small numbers on the borders
		// draw_die_face(f, size, texture, {f32(7+f)*fs.x, 0.}, fs, color/2)
		draw_die_face(f, size, texture, {f32(13)*fs.x, 0}, fs, rl.ColorAlpha(color, 0.8), scale=0.6)
		draw_die_face(f, size, texture, {f32(n-1)*fs.x, 0.}, fs, rl.BLACK, scale=0.5)
	}

	return hoverable && collision.hit
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

add_text :: proc{add_text_vec3, add_text_vec3_vec2, add_text_vec2, add_text_vec2_vec2}
add_text_vec3_vec2 :: proc (
		start: Vector3, end: rl.Vector2, text: string, color: rl.Color,
		lifetime:f32=2.0, font_size:f32=-1, anchor:TextAnchor=.CENTER) {
	start_2d := rl.GetWorldToScreen(start, app.camera3d)
	add_text_vec2_vec2(start_2d, {f32(end.x), f32(end.y)}, text, color, lifetime, font_size, anchor)
}
add_text_vec3 :: proc (
		start: Vector3, text: string, color: rl.Color, lifetime:f32=2.0,
		font_size:f32=-1, anchor:TextAnchor=.CENTER) {
	start_2d := rl.GetWorldToScreen(start, app.camera3d)
	add_text_vec2_vec2(start_2d, start_2d + Vector2{0, -100}, text, color, lifetime, font_size, anchor)
}
add_text_vec2 :: proc (
		start: Vector2, text: string, color: rl.Color, lifetime:f32=2.0,
		font_size: f32=-1, anchor:TextAnchor=.CENTER) {
	add_text_vec2_vec2(start, start + Vector2{0, -100}, text, color, lifetime, font_size, anchor)
}
add_text_vec2_vec2 :: proc (
		start, end: Vector2, text: string, color: rl.Color, lifetime:f32=2.0,
		font_size: f32=-1, anchor:TextAnchor=.CENTER) {
	for &t in app.text_animations{
		if t.visible do continue

		t = {
			start = start,
			end = end,
			text = text,
			color = color,
			start_lifetime = lifetime,
			lifetime = lifetime,
			visible = true,
			font_size=font_size < 0 ? app.gui.font_size2 : font_size,
			anchor=anchor,
		}
		return
	}
}

measure_text :: proc(text: string, font_size: f32, spacing:f32=1.0, max_width:f32=9999) -> rl.Vector2 {
	return draw_text(text, {0, 0}, font_size, spacing=spacing, max_width=max_width, draw=false)
}

draw_text :: proc(text: string, position: rl.Vector2, font_size: f32,
		color: rl.Color=rl.RAYWHITE, spacing:f32=1.0, line_spacing:f32=1.2, max_width:f32=9999,
		strikethrough:bool=false, overline:bool=false, boxed:rl.Color=rl.BLANK, box_width:f32=-1, padding:f32=10,
		anchor:TextAnchor=.LEFT, draw:bool=true, highlight_color:rl.Color=rl.RAYWHITE) -> rl.Vector2{

	position := position
	if anchor == .RIGHT do position.x -= measure_text(text, font_size, spacing, max_width).x
	if anchor == .CENTER do position.x -= measure_text(text, font_size, spacing, max_width).x / 2.
	if boxed != rl.BLANK {
	    box_size := measure_text(text, font_size, spacing, max_width)+2*padding
		if box_width > 0 do box_size.x = box_width
	    draw_box(position - padding, box_size, boxed)
        // position += {padding, padding}
	}

	font := app.font
	text_size := rl.Vector2{0, 0}
	text_offset_y := f32(0)
	text_offset_x := f32(0)

	scale_factor := font_size / f32(font.baseSize)
	in_tag: bool
	highlighted: bool

	for r, i in text{
	    if r == '[' {
			in_tag = true
			continue
		}
	    if in_tag {
			if r == ']' {
    			in_tag = false
    			continue
			} else if r == 'h' {
			    highlighted = !highlighted
				continue
			}
		}

		if r == '\n' || (in_tag && r == 'n') {
			text_offset_y += line_spacing * f32(font.baseSize) * scale_factor
			text_offset_x = 0.
			continue
		}

		glyph_width :f32= 0.
		next_word_length :f32= 0.
		for nr, j in text[i:] {
		    if nr == '[' {
                break
            }

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
					text_offset_y += line_spacing * f32(font.baseSize) * scale_factor
					text_offset_x = 0.
				}
				break
			}
			// if we fit so far and the next rune is white space, we can stop here...
			if strings.is_space(nr) do break
		}

		if draw {
		    if highlighted{
          		// rl.DrawTextCodepoint(
         			// font, r,
         			// position + rl.Vector2{text_offset_x, text_offset_y} - 2.,
         			// font_size+4, color/2)
                rl.DrawRectangleV(
                    position + rl.Vector2{text_offset_x, text_offset_y},
                    {glyph_width, font_size}, rl.BLACK)
			}
			if !strings.is_space(r) {
			    rl.DrawTextCodepoint(
				font, r,
				position + rl.Vector2{text_offset_x, text_offset_y},
				font_size, highlighted ? rl.RAYWHITE : color)
			}
		}

		if text_offset_x != 0. || !strings.is_space(r) {
			text_offset_x += glyph_width
		}
		text_size = {
			math.max(text_size.x, text_offset_x),
			math.max(text_size.y, text_offset_y + f32(font.baseSize) * scale_factor)
		}
	}

	if draw{
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
	}

	return text_size
}

draw_box :: proc(position, size: rl.Vector2, fill:rl.Color=rl.BLANK, outline:rl.Color=rl.BLACK, thickness:f32=4.) {
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

draw_box_outline :: proc(position, size: Vector2, color:rl.Color=rl.BLACK, thickness:f32=4.){
    rl.DrawRectangleLinesEx({position.x-thickness, position.y-thickness, size.x+2*thickness, size.y+2*thickness}, thickness, color)
}

draw_card :: proc(card: Card, position: rl.Vector2, color:rl.Color=rl.BLANK, actions:[]string={}, static:bool=false) -> (bool, i32){
    size := CARD_SIZE
	hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), {x=position.x, y=position.y, width=f32(size.x), height=f32(size.y)})

	color := color
	if color == rl.BLANK do color = COLOR_CARDS[card.category]

	position := position
	if position.y+CARD_SIZE.y+300 > app.gui.height do position.y -= CARD_SIZE.y + 20

	if hovered && !static{
		color = rl.ColorBrightness(color, 0.1)
		position.y += -10. //math.sin(f32(rl.GetTime())*10)*5	// make the button float up and down a bit
	}

	if card.active {
		color = rl.ColorBrightness(color, 0.15)
	} else if !hovered && card.triggered == 0.{
		color = rl.ColorBrightness(color, -0.3)
	}

	if card.triggered > 0. && !static{
		position.y += math.sin(f32(rl.GetTime())*20)*10
	}

	font_size :f32= 25 // app.gui.font_size2
	padding :f32= 10
	header_height := font_size+2*padding
	lt :f32= 4. // line_thickness
	lc := rl.BLACK // color / 2 // line color
	lc.a = color.a

	rl.DrawRectangleV(position, size, color)
	rl.DrawRectangleV(position, {size.x, header_height}, rl.BLACK)

	rl.DrawRectangleLinesEx({position.x-4, position.y-4, size.x+2*lt, size.y+2*lt}, lt, lc)
	// rl.DrawLineEx({position.x+padding, position.y+line_pos}, {position.x+size.x-padding, position.y+line_pos}, lt, lc)

	texture := app.textures[0]
	ts := TextureFaceSize
	tp := ts * {16.+f32(card.category), 0.}
	icon_size := header_height - 2*padding
	rl.DrawTexturePro(
	    texture,
	    {x=tp.x, y=tp.y, width=ts.x, height=ts.y},
		{x=position.x+size.x-icon_size-padding, y=position.y+padding, height=icon_size, width=icon_size},
		{}, 0., color)
	if card.category == .ROLL && card.lifetime > 0 {
		draw_text(fmt.tprintf("%v", card.lifetime), position+{size.x-padding-icon_size-2, padding}, font_size, rl.RAYWHITE, anchor=.RIGHT)
	}

	tp = ts.yx * {0., 1.}
	card_type_string := reflect.enum_string(card.type)
	if card_type_string in app.sub_textures do tp = ts.yx * app.sub_textures[card_type_string].yx
	icon_size = min(size.x, size.y)-2*padding
	dest := rl.Rectangle{x=position.x+padding, y=position.y+header_height+padding, width=icon_size, height=icon_size}
	tint := rl.ColorBrightness(color, -0.2)
	if hovered do tint.a /= 2
	// rl.DrawCircleV({dest.x+dest.width/2, dest.y+dest.height/2}, dest.width/2-20., tint)
	inner_padding :f32=40
	rl.DrawRectangleV({dest.x, dest.y}+inner_padding, {}+dest.width-2*inner_padding, tint)
	tint = color
	if hovered do tint.a /= 2
	rl.DrawTexturePro(texture, {x=tp.x, y=tp.y, width=ts.x, height=ts.y}, dest, {}, 0., tint)

	// Title
	draw_text(get_text(card.type, "title"), position + padding, font_size, rl.RAYWHITE, max_width=size.x-2*padding)

	if hovered {
		button_pos := position + size + {-10, -45}

		for action, i in actions {
			if button(action, button_pos, font_size=font_size, anchor=.RIGHT) do return hovered, i32(i)
			button_pos += {-20-measure_text(action, font_size).x, 0}
		}
	}

	// Description
	text_pos := position + {0., CARD_SIZE.y+padding}+padding
	if hovered && has_text(card.type, "description") {
        text_size := draw_text(get_text(card.type, "description"), text_pos, font_size, rl.BLACK,
            max_width=size.x-(text_pos.x-position.x), highlight_color=color, boxed=color, box_width=CARD_SIZE.x)
        text_pos.y += text_size.y + 3*padding
	}
	if hovered && has_text(card.type, "description2") {
        text_size := draw_text(get_text(card.type, "description2"), text_pos, font_size, rl.BLACK,
            max_width=size.x-(text_pos.x-position.x), highlight_color=color, boxed=color, box_width=CARD_SIZE.x)
        text_pos.y += text_size.y + 3*padding
	}

	return hovered, -1
}
