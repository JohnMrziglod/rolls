package game

import "core:math"
import "core:math/rand"
import "core:fmt"
import "core:reflect"
import "core:strings"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

BOX_PADDING :f32: 6.
TextureFaceSize :: [2]f32{128., 128.}

TextAnchor :: enum {
	LEFT,
	RIGHT,
	CENTER,
}

Particles :: struct{
	positions: [12]Vector3,
	velocities: [12]Vector3,
	color: rl.Color,
	visible: bool,
	lifetime: f32
}

IconParticle :: struct{
	position: Vector2,
	velocity: Vector2,
	texture_id: Vector2,
	color: rl.Color,
	lifetime: f32,
}

Vector :: union{Vector2, Vector3}
Animation :: struct{
	start: Vector,
	end: Vector,
	text: string,
	icon_id: Maybe(Vector2),
	icon_size: f32,
	color: rl.Color,
	visible: bool,
	font_size: f32,
	lifetime: f32,
	start_lifetime: f32,
	delay: f32,
	anchor: TextAnchor,
}

splash :: proc(t: f32, min_:f32=0., max_:f32=4.) -> f32 {
	t := max(1.-t, 0.)
    A :f32= 30.0   // intensity
    B :f32= 5.0  // decay speed

    decay_term := 2.*math.exp(-B * t)

    return max(A * t * decay_term, min_)
}
splash_shrink :: proc(t: f32, min_:f32=0) -> f32{
	t := max(1.-2*t, 0.)
	A :f32= 40.0   // intensity

    return 1.+A*t*t
}

continue_button :: proc() -> bool{
	return button(
		"Press <SPACE> to continue", {L.width / 2., L.height - 100*S},
		size = V2{300, 50}*S,
		font_size = L.font_size2+sine_wave(5, 2),
		color = rl.BLANK, anchor = .CENTER,
		hover_motion=false,
	)
	// return draw_text(text, {L.width/2, L.height-100*S}, L.font_size2+sine_wave(5, 2), anchor=.CENTER)
}

button :: proc(text: string, position: rl.Vector2, size:rl.Vector2={1, 1}, color:rl.Color=rl.BLACK, active_color:rl.Color=rl.BLANK,
		font_size:f32=-1., clickable:bool=true, padding:f32=10., text_color:=rl.WHITE, anchor:TextAnchor=.LEFT, hover_motion:bool=true) -> bool{
	font_size := font_size > 0. ? font_size : L.font_size2
	padding := SCALE(padding)
	text_size := measure_text(text, font_size) + 2*padding

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
	if hovered && hover_motion do box.y += SCALE(math.sin(f32(rl.GetTime())*10)*5)	// make the button float up and down a bit

	active_color := active_color == rl.BLANK ? rl.ColorBrightness(color, 1.2) : active_color

	position := rl.Vector2{box.x, box.y}
	draw_box(position-{0, box.height-text_size.y}/2., {box.width, box.height}, color, thickness=0.)
	text_position := position + {box.width-text_size.x, 0} / 2. + padding
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

draw_die_face :: proc(face: int, die_size: f32, texture: rl.Texture, tc, ts: Vector2, color: rl.Color, scale:f32=1.){
    size := die_size + (0.1*(1.-scale))
    size2 := size*scale
    offset :f32= 0.//scale == 1. ? 0. : die_size/2
    rlgl.Color4ub(color.r, color.g, color.b, color.a)

	// Front face (1)
	switch face{
	case 0:
    	rlgl.Normal3f(0.0, 0.0, 1.0) // Normal pointing left
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size2+offset, -size2+offset, size) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size2+offset, -size2+offset, size) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size2+offset,  size2+offset, size) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size2+offset,  size2+offset, size) // Top-left

	// Left face (2)
	case 1:
    	rlgl.Normal3f(-1.0, 0.0, 0.0) // Normal pointing left
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size, -size2+offset, -size2+offset) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f(-size, -size2+offset,  size2+offset) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f(-size,  size2+offset,  size2+offset) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size,  size2+offset, -size2+offset) // Top-left

	// // Top face (3)
	case 2:
    	rlgl.Normal3f(0.0, 1.0, 0.0) // Normal pointing up
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size2+offset,  size,  size2+offset) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size2+offset,  size,  size2+offset) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size2+offset,  size, -size2+offset) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size2+offset,  size, -size2+offset) // Top-lefts

	// // Bottom face (4)
	case 3:
    	rlgl.Normal3f(0.0, -1.0, 0.0) // Normal pointing down
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f(-size2+offset, -size, -size2+offset) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size2+offset, -size, -size2+offset) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size2+offset, -size,  size2+offset) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f(-size2+offset, -size,  size2+offset) // Top-left

	// // Right face (5)
	case 4:
    	rlgl.Normal3f(1.0, 0.0, 0.0) // Normal pointing right
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f( size, -size2+offset,  size2+offset) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f( size, -size2+offset, -size2+offset) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f( size,  size2+offset, -size2+offset) // Top-right
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f( size,  size2+offset,  size2+offset) // Top-left

	// // Back face (6)
	case 5:
    	rlgl.Normal3f(0.0, 0.0, -1.0) // Normal pointing away from viewer
    	rlgl.TexCoord2f(tc.x,      tc.y+ts.y); rlgl.Vertex3f( size2+offset, -size2+offset, -size) // Bottom-right
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y+ts.y); rlgl.Vertex3f(-size2+offset, -size2+offset, -size) // Bottom-left
    	rlgl.TexCoord2f(tc.x+ts.x, tc.y     ); rlgl.Vertex3f(-size2+offset,  size2+offset, -size) // Top-left
    	rlgl.TexCoord2f(tc.x,      tc.y     ); rlgl.Vertex3f( size2+offset,  size2+offset, -size) // Top-right
    }
}

draw_die :: proc(dice: Die, hoverable:bool=false) -> bool {
	size := dice.shape.(ShapeBox).half_size
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), game.camera3d)

    // Check collision between ray and b
    collision := rl.GetRayCollisionBox(ray, {min=dice.position-size, max=dice.position+size})

    color := dice.color
	hovered := hoverable && collision.hit
	if hovered do color = rl.ColorBrightness(color, -0.3)

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
		icon_col :f32= dice.health > 0 ? 6 : 7
	    draw_die_face(i, size, texture, {icon_col*fs.x, 0}, fs, color)
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

		// we only draw the face on this side if we hover it, so icons are more recognisable
		if hovered {
			draw_die_face(f, size, texture, {f32(15)*fs.x, 0}, fs, dice.color, scale=0.95)
			draw_die_face(f, size, texture, {f32(n-1)*fs.x, 0.}, fs, rl.BLACK, scale=0.45)
		}
	}

	return hovered
}

add_particles :: proc(position: Vector3, color: rl.Color){
	for &particles in game.particles{
		if particles.visible do continue

		for i in 0 ..< len(particles.positions) {
			particles.positions[i] = position
			particles.velocities[i] = random_vector(-20., 20.)
			particles.velocities[i].y = rand.float32_range(5, 20)
		}
		particles.color = color
		particles.visible = true
		particles.lifetime = 1.0

		return
	}
}

add_icon_particles :: proc(position, area: Vector2, texture_ids: []Vector2, color: rl.Color, lifetime:f32=2.){
	for &particle in game.icon_particles[:200]{
		particle.position = position+{rand.float32_range(0, area.x), rand.float32_range(0, area.y)}
		// particle.velocity = random_vector2(-200., 200.)
		particle.velocity.y = rand.float32_range(50, 1000)
		particle.texture_id = rand.choice(texture_ids[:])
		particle.color = color
		particle.lifetime = lifetime
	}
}

draw_icon_particles :: proc(dt: real){
	for &particle, i in game.icon_particles{
		if particle.lifetime <= 0. do return

		draw_texture_by_index(particle.texture_id, particle.position, 30.,
			rl.ColorAlpha(particle.color, min(particle.lifetime, 1.)),
			rotation=math.sin((f32(rl.GetTime())+f32(i))*10)*20
		)
		particle.position += particle.velocity * dt
		particle.lifetime -= dt * game.speed
	}
}

add_text_fixed :: proc (
		start: Vector2, text: string, color: rl.Color, lifetime:f32=-1.,
		font_size: f32=-1, anchor:TextAnchor=.CENTER, delay:f32=0.,
		icon_id:Maybe(Vector2)=nil, icon_size:f32=0.) {
	add_text_vec_vec(start, start, text, color, lifetime, font_size, anchor, delay, icon_id, icon_size)
}
add_text :: proc{add_text_vec3, add_text_vec2, add_text_vec_vec}
add_text_vec3 :: proc (
		start: Vector3, text: string, color: rl.Color, lifetime:f32=-1.,
		font_size:f32=-1, anchor:TextAnchor=.CENTER, delay:f32=0.,
		icon_id:Maybe(Vector2)=nil, icon_size:f32=0.) {
	add_text_vec_vec(start, start, text, color, lifetime, font_size, anchor, delay, icon_id, icon_size)
}
add_text_vec2 :: proc (
		start: Vector2, text: string, color: rl.Color, lifetime:f32=-1.,
		font_size: f32=-1, anchor:TextAnchor=.CENTER, delay:f32=0.,
		icon_id:Maybe(Vector2)=nil, icon_size:f32=0.) {
	add_text_vec_vec(start, start+{0, -100}, text, color, lifetime, font_size, anchor, delay, icon_id, icon_size)
}
add_text_vec_vec :: proc (
		start, end: Vector, text: string, color: rl.Color, lifetime:f32=-1.,
		font_size: f32=-1, anchor:TextAnchor=.CENTER, delay:f32=0.,
		icon_id:Maybe(Vector2)=nil, icon_size:f32=0.) {

	for &a in game.animations{
		if a.visible do continue

		a = {
			start = start,
			end = end,
			text = text,
			icon_id=icon_id,
			icon_size=icon_size,
			color = color,
			start_lifetime = lifetime < 0. ? 2. : lifetime,
			lifetime = lifetime < 0. ? 2. : lifetime,
			visible = true,
			font_size=font_size < 0 ? L.font_size2 : font_size,
			anchor=anchor,
			delay=delay
		}
		return
	}
}

measure_text :: proc(text: string, font_size: f32, spacing:f32=1.0, max_width:f32=9999, boxed:bool=false) -> rl.Vector2 {
	return draw_text(text, {0, 0}, font_size, spacing=spacing, max_width=max_width, draw=false, boxed=boxed? rl.RAYWHITE : rl.BLANK)
}

draw_text :: proc(text: string, position: rl.Vector2, font_size: f32=-1.,
		color: rl.Color=rl.WHITE, spacing:f32=1.0, line_spacing:f32=1.2, max_width:f32=9999,
		strikethrough:bool=false, overline:bool=false, underline:bool=false, boxed:rl.Color=rl.BLANK, box_width:f32=-1,
		padding:f32=10, anchor:TextAnchor=.LEFT, draw:bool=true, highlight_color:rl.Color=rl.RAYWHITE,
		outline:rl.Color=rl.BLANK, icon_bg_color:rl.Color=rl.BLANK) -> rl.Vector2{

	font_size := font_size > 0. ? font_size : L.font_size2
	padding := SCALE(padding)

	position := position
	max_width := max_width
	if boxed != rl.BLANK && max_width != 9999. do max_width -= 2*padding
	if anchor == .RIGHT do position.x -= measure_text(text, font_size, spacing, max_width).x
	if anchor == .CENTER do position.x -= measure_text(text, font_size, spacing, max_width).x / 2.
	if boxed != rl.BLANK{
		if draw {
			box_size := measure_text(text, font_size, spacing, max_width)+2*padding
			if box_width > 0 do box_size.x = box_width
			draw_rounded_box(position, box_size, boxed)
		}
		position += padding
	}

	outline := outline
	if outline != rl.BLANK do outline.a = color.a

	font := app.font
	text_size := rl.Vector2{0, 0}
	text_offset_y := f32(0)
	text_offset_x := f32(0)

	scale_factor := font_size / f32(font.baseSize)
	in_tag: bool
	// TokenType :: union{Text, Highlighted, Icon}
	highlighted: bool
	in_icon: bool
	icon_id := strings.builder_make(context.temp_allocator)
	draw_icon: bool

	for r, i in text{
	    if r == '[' {
			in_tag = true
			continue
		}
	    if in_tag {
			if r == ']' {
    			in_tag = false
       			if in_icon{
          			// Somehow this doesn't work yet
          			if text_offset_x+2.+font_size > max_width{
	       				// we draw it onto the next line
						text_offset_y += line_spacing * f32(font.baseSize) * scale_factor
						text_offset_x = 0.
             		}
          			if draw{
             			if icon_bg_color != rl.BLANK{
             				draw_box(position + rl.Vector2{text_offset_x, text_offset_y-2*S}, {4., 4.}*S+font_size, fill=icon_bg_color, thickness=0)
              			}
						draw_texture_by_string(strings.to_string(icon_id),
							position + rl.Vector2{text_offset_x+2.*S, text_offset_y}, font_size, highlight_color)
             		}
					text_offset_x += font_size+4.
					text_size = {
						math.max(text_size.x, text_offset_x),
						math.max(text_size.y, text_offset_y + f32(font.baseSize) * scale_factor)
					}
				}
       			in_icon = false
    			continue
			} else if !in_icon && r == 'i' {
				in_icon = true
    			strings.builder_reset(&icon_id)
				continue
			} else if !in_icon && r == 'h' {
			    highlighted = !highlighted
				continue
			} else if in_icon {
			    strings.write_rune(&icon_id, r)
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
		next_in_tag := false
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
			if !strings.is_space(r) {
				if outline != rl.BLANK || highlighted{
					rl.DrawTextCodepoint(
						font, r,
						position + rl.Vector2{text_offset_x, text_offset_y}-2.,
						font_size+6, outline)
				}
			    rl.DrawTextCodepoint(
					font, r,
					position + rl.Vector2{text_offset_x, text_offset_y},
					font_size, highlighted ? rl.Color{120, 120, 120, 255} : color)
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
		if underline {
			rl.DrawLineEx(
				position + rl.Vector2{0,  font_size},
				position + rl.Vector2{text_size.x,  font_size},
				min(font_size / 10., 1.), color)
		}
	}

	if boxed != rl.BLANK {
		text_size += padding
		text_size.x = math.max(text_size.x, box_width)
	}

	return text_size
}

draw_rounded_box :: proc(position, size: rl.Vector2, fill:rl.Color=rl.BLANK, radius:f32=6.) {
	w := size.x;
	h := size.y;
	roundness := 2.*radius*S / min(w, h)
	if (roundness < 0) do roundness = 0
	if (roundness > 1) do roundness = 1

	draw_box(position, size, fill, outline={0, 0, 0, fill.a}, roundness=roundness)
}
draw_box :: proc(position, size: rl.Vector2, fill:rl.Color=rl.BLANK, outline:rl.Color=rl.BLACK, thickness:f32=6., roundness:f32=0.) {
	box := rl.Rectangle{x=position.x, y=position.y, width=size.x, height=size.y}
	if roundness > 0.{
		segments :i32= 0
		if fill != rl.BLANK {
			rl.DrawRectangleRounded(box, roundness, segments, fill)
		}
		box = {position.x, position.y, size.x, size.y}
		rl.DrawRectangleRoundedLinesEx(box, roundness, segments, thickness*S, outline)
	} else {
		if fill != rl.BLANK {
			rl.DrawRectangleV(position, size, fill)
		}
		if thickness > 0. {
			box = {position.x, position.y, size.x, size.y}
			rl.DrawRectangleLinesEx(box, thickness*S, outline)
		}
	}
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

icon_index_from_id :: proc(texture_id: string) -> Vector2 {
	return app.sub_textures[texture_id] or_else {1, 0}
}

icon_index_from_card :: proc(card_type: CardType) -> Vector2 {
	return app.sub_textures[reflect.enum_string(card_type)] or_else {1, 0}
}

draw_antagonist :: proc(id: AntagonistID, position: Vector2, size: f32, tint:rl.Color=rl.BLANK, rotation:f32=0.){
	texture := app.textures[2]
	sub_texture_index := icon_index_from_id(reflect.enum_string(id))
	ts := Vector2{256, 256}

	// Draw the background texture first:
	tp := (ts * (sub_texture_index+{0,1})).yx
	bg_size := size * (1.+sine_wave(1, 0.05, 3.1))
	bg_rotation := rotation + sine_wave(1, 2)
	dest := rl.Rectangle{x=position.x, y=position.y, width=bg_size, height=bg_size}
	rl.DrawTexturePro(texture, {x=tp.x, y=tp.y, width=ts.x, height=ts.y}, dest, {}+bg_size/2., bg_rotation, tint)

	tp = (ts * sub_texture_index).yx
	position := position
	position.y += sine_wave(1, 3)
	// position.x += (rl.GetMousePosition().x-position.x)/L.width * 50.
	// position.y += (rl.GetMousePosition().y-position.y)/L.height * 50.
	rotation := rotation + sine_wave(1, 3)
	size := size * (1.0+sine_wave(1, 0.1))
	dest = rl.Rectangle{x=position.x, y=position.y, width=size, height=size}
	rl.DrawTexturePro(texture, {x=tp.x, y=tp.y, width=ts.x, height=ts.y}, dest, {}+size/2., rotation, tint)
}

draw_texture :: proc{draw_texture_by_index, draw_texture_by_string, draw_full_texture}
draw_texture_by_index :: proc(texture_id:Vector2={0,1}, position: Vector2, size: f32, tint:rl.Color=rl.BLACK, rotation:f32=0.){
	texture := app.textures[0]
	ts := TextureFaceSize
	tp := ts.yx * texture_id.yx
	dest := rl.Rectangle{x=position.x+size/2., y=position.y+size/2., width=size, height=size}
	origin := position
	rl.DrawTexturePro(texture, {x=tp.x, y=tp.y, width=ts.x, height=ts.y}, dest, {}+size/2., rotation, tint)
}
draw_texture_by_string :: proc(texture_id: string, position: Vector2, size: f32, tint:rl.Color=rl.BLACK, rotation:f32=0.){
	texture := app.textures[0]
	ts := TextureFaceSize
	tp := (ts * icon_index_from_id(texture_id) ).yx

	dest := rl.Rectangle{x=position.x+size/2., y=position.y+size/2., width=size, height=size}
	rl.DrawTexturePro(texture, {x=tp.x, y=tp.y, width=ts.x, height=ts.y}, dest, {}+size/2., rotation, tint)
}
draw_full_texture :: proc(texture: rl.Texture, position, size: Vector2, tint: rl.Color=rl.BLACK){
	dest := rl.Rectangle{x=position.x+size.x/2., y=position.y+size.y/2., width=size.x, height=size.y}
	origin := position
	rl.DrawTexturePro(texture, {x=0., y=0., width=f32(texture.width), height=f32(texture.height)}, dest, {}+size/2., 0., tint)
}

fade_out :: proc(ratio:f32=0.3){
	draw_box({-200, -200}, {L.width+400, L.height+400}, fill=rl.ColorAlpha(rl.BLACK, ratio), thickness=0)
}

draw_card :: proc(
		card: Card, position: rl.Vector2, color:rl.Color=rl.BLANK, actions:[]string={},
		with_title:bool=true, with_icon:bool=true, with_info:bool=true, hoverable:bool=true,
		upside_down:bool=false,
) -> (bool, i32){
    size := L.card_size
   	font_size :f32= L.font_size2-3
	padding :f32= SCALE(12)
	margin: f32 = SCALE(12)
	header_height := font_size+2*padding

	// if upside_down we draw the towards upside (useful when drawing towards the bottom of the screen)
	direction :f32= upside_down ? -1. : 1.

	color := color
	if color == rl.BLANK do color = COLOR_CARDS[card.category]

	if !hoverable do color = rl.ColorBrightness(color, -0.3)
    if !with_icon do size.y = header_height
	hovered := hoverable && with_icon && card_is_hovered(position)

	position := position
	if hovered{
		color = rl.ColorBrightness(color, 0.1)
		position.y += SCALE(-10)
	}

	if card.active {
		color = rl.ColorBrightness(color, 0.15)
	} else if !hovered && card.triggered == 0.{
		color = rl.ColorBrightness(color, -0.1)
	}

	if card.triggered > 0.{
		position.y += math.sin(f32(rl.GetTime())*20)*10*S
	}

	if with_icon{
		draw_rounded_box(position, size, fill=color)
	}

	// Title
	if with_title{
		if !with_icon {
			draw_rounded_box(position, {size.x, header_height}, fill=rl.ColorContrast(color, 0.1))
		} else {
			rl.DrawLineEx(position+{0., header_height}, position+{size.x, header_height}, SCALE(4.), rl.BLACK)
		}
		draw_text(get_text(card.type, "title"), position + padding, font_size, rl.BLACK, max_width=size.x-2*padding)
		icon_size := header_height - 2*padding
		icon_position := position+{size.x-icon_size-padding, padding}
		draw_texture(Vector2{0., 15.+f32(card.category)}, icon_position, icon_size, color)
		if card.category == .ROLL && card.lifetime > 0 {
			draw_text(fmt.tprintf("%v", card.lifetime),
				position+{size.x-padding-icon_size-2, padding}, font_size, rl.BLACK, anchor=.RIGHT)
		}
	}

	// main card icon
	if with_icon{
		icon_position := position+padding + {0., header_height+6.*S}
		icon_size := min(size.x, size.y)-2*padding
		icon_color := hovered ? rl.ColorAlpha(color, 0.5) : color
		rl.DrawRectangleV(icon_position+40*S, {}+icon_size-2*40*S, rl.ColorBrightness(icon_color, -0.2))
		draw_texture(reflect.enum_string(card.type), icon_position, icon_size+math.sin(f32(rl.GetTime())+30*f32(card.type))*3*S, icon_color,
			rotation=math.sin(f32(rl.GetTime())+10*f32(card.type))*3*S)
	} else {
		// margin = 0.
	}

	if hovered {
		button_pos := position + size + {-15, -60}*S

		for action, i in actions {
			if button(action, button_pos, font_size=font_size, anchor=.RIGHT) do return hovered, i32(i)
			button_pos += {-30*S-measure_text(action, font_size).x, 0}
		}
	}

	// Info
	if !with_info do return hovered, -1

	show_description := hovered || !with_icon
	text_pos := position
	if with_title || with_icon do text_pos += {0, size.y+SCALE(10)}
	if show_description {
	    ids := []string{"description", "description2"}
		previous_info_height: f32
		for id in ids{
		    if !has_text(card.type, id) do continue

			text := card_fill_vars(card, get_text(card.type, id))
            text_size := draw_text(
                    text, text_pos, font_size, rl.BLACK,
                    max_width=size.x, highlight_color=color,
                    icon_bg_color=rl.BLACK,
                    boxed=color, box_width=size.x, padding=10)
            previous_info_height = draw_term_info(text, text_pos, color, padding, margin)
            text_pos.y += max(text_size.y, previous_info_height)+SCALE(2*10.)
		}
	}

	reset_info()

	return hovered, -1
}
fade :: proc(color: rl.Color, ratio:f32=0.5) -> rl.Color {
	return rl.ColorAlpha(color, ratio)
}
draw_term_info :: proc(text: string, position: Vector2, color: rl.Color, padding, margin:f32) -> f32{
	// Draw an additional info box for all highlighted terms that have an info entry in app.texts
	font_size := L.font_size2-2
	direction :f32= position.x < L.width/2. ? 1. : -1.
	delta := Vector2{L.card_size.x+SCALE(10), 0}
	info_size: Vector2
	max_info_height: f32

	color := rl.GRAY
	color.a = 180

	mentioned: map[string]bool
	defer delete(mentioned)

	for term, &info in INFO{
		if info.shown || !strings.contains(text, term) do continue

		info.shown = true

		info_size = draw_text(fmt.tprintf("%v:[n]%v", term, info.text), position+direction*delta, font_size, color=rl.BLACK,
			max_width=L.card_size.x, boxed=color, box_width=L.card_size.x)
		max_info_height = max(max_info_height, info_size.y)
		delta.x += L.card_size.x + SCALE(10)

		for another_term in INFO{
			if strings.contains(info.text, another_term) do mentioned[another_term] = true
		}
	}

	// Do it again for mentioned terms
	for term in mentioned{
		info := &INFO[term]
		if info.shown do continue

		info.shown = true
		info_size = draw_text(fmt.tprintf("%v:[n]%v", term, info.text), position+direction*delta, font_size, color=rl.BLACK,
			max_width=L.card_size.x, boxed=color, box_width=L.card_size.x)
		max_info_height = max(max_info_height, info_size.y)
		delta.x += L.card_size.x + SCALE(10)
	}

	return max_info_height
}

draw_die_info :: proc(die: Die, extended:bool=false) -> i32{
	position := rl.GetWorldToScreen(die.position, game.camera3d)
	icon_size := SCALE(50.)
	margin := SCALE(10.)
    padding := SCALE(4.)

    // box_size := Vector2{6*icon_size+10*padding, icon_size+3*padding+L.font_size2}+2.*margin
    // draw_box(position-margin, box_size, fill=rl.ColorAlpha(die.color, 0.8), thickness=0.)

    card: Card
    card_position: Vector2

    hovered_upgrade_index :i32= -1
    hovered_color: rl.Color
	#reverse for upgrade, u in die.upgrades{
		upgrade_pos := position + f32(u)*Vector2{icon_size+2*padding, 0.}
		upgraded := upgrade.type != .CardNone

        tp := Vector2{0, f32(die.faces[u]-1)} // Standard face number
        color:= die.color
       	if upgraded {
       		tp = icon_index_from_card(upgrade.type)
        }

        dest := rl.Rectangle{x=upgrade_pos.x, y=upgrade_pos.y, width=icon_size, height=icon_size}
        hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), dest)
        if hovered {
			if upgraded {
			  	card_position = upgrade_pos + {-L.card_size.x/2.+icon_size/2., icon_size+10}
				card = upgrade
			} else if game.card_selected.category == .DICE{
				tp = icon_index_from_card(game.card_selected.type)
   				// color = COLOR_CARDS[.DICE]
			}
			hovered_upgrade_index = i32(u)
			hovered_color = color
        }
        draw_box({dest.x, dest.y}-padding, {}+icon_size+2*padding, fill=upgraded ? color : rl.ColorAlpha(color, 0.9), thickness=1)
        draw_texture(tp, upgrade_pos, icon_size, tint=upgraded ? rl.BLACK : rl.RAYWHITE/2)
    }
    if card.type != .CardNone {
    	draw_card(card, position+{0, icon_size+2*margin}, with_icon=false, color=hovered_color)
    }

    if extended {
	    text := fmt.tprintf("Attack: %v, Health: %v", die.attack, die.health)
	    text_position := position + padding
	    text_position.y += icon_size + padding + SCALE(10.)
	    draw_text(text, text_position, color=rl.BLACK)
    }

    return hovered_upgrade_index
}
