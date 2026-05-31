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

splash :: proc(t: f32) -> f32 {
	t := 1.-t
    A :f32= 30.0   // intensity
    B :f32= 5.0  // decay speed

    decay_term := 2.*math.exp(-B * t)

    return A * t * decay_term
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
	ray := rl.GetScreenToWorldRay(rl.GetMousePosition(), app.camera3d)

    // Check collision between ray and b
    collision := rl.GetRayCollisionBox(ray, {min=dice.position-size, max=dice.position+size})

    color := dice.color1
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
			draw_die_face(f, size, texture, {f32(15)*fs.x, 0}, fs, dice.color1, scale=0.95)
			draw_die_face(f, size, texture, {f32(n-1)*fs.x, 0.}, fs, rl.BLACK, scale=0.45)
		}
	}

	return hovered
}

add_particles :: proc(position: Vector3, color: rl.Color){
	for &particles in app.particles{
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
	for &particle in app.icon_particles[:200]{
		particle.position = position+{rand.float32_range(0, area.x), rand.float32_range(0, area.y)}
		// particle.velocity = random_vector2(-200., 200.)
		particle.velocity.y = rand.float32_range(50, 1000)
		particle.texture_id = rand.choice(texture_ids[:])
		particle.color = color
		particle.lifetime = lifetime
	}
}

draw_icon_particles :: proc(dt: real){
	for &particle, i in app.icon_particles{
		if particle.lifetime <= 0. do return

		draw_texture_by_index(particle.texture_id, particle.position, 30.,
			rl.ColorAlpha(particle.color, min(particle.lifetime, 1.)),
			rotation=math.sin((f32(rl.GetTime())+f32(i))*10)*20
		)
		particle.position += particle.velocity * dt
		particle.lifetime -= dt * config.game_speed
	}
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

	for &a in app.animations{
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
			font_size=font_size < 0 ? app.gui.font_size2 : font_size,
			anchor=anchor,
			delay=delay
		}
		return
	}
}

measure_text :: proc(text: string, font_size: f32, spacing:f32=1.0, max_width:f32=9999) -> rl.Vector2 {
	return draw_text(text, {0, 0}, font_size, spacing=spacing, max_width=max_width, draw=false)
}

draw_text :: proc(text: string, position: rl.Vector2, font_size: f32=-1.,
		color: rl.Color=rl.RAYWHITE, spacing:f32=1.0, line_spacing:f32=1.2, max_width:f32=9999,
		strikethrough:bool=false, overline:bool=false, boxed:rl.Color=rl.BLANK, box_width:f32=-1, padding:f32=10,
		anchor:TextAnchor=.LEFT, draw:bool=true, highlight_color:rl.Color=rl.RAYWHITE,
		outline:rl.Color=rl.BLANK) -> rl.Vector2{

	font_size := font_size > 0. ? font_size : app.gui.font_size2

	position := position
	if anchor == .RIGHT do position.x -= measure_text(text, font_size, spacing, max_width).x
	if anchor == .CENTER do position.x -= measure_text(text, font_size, spacing, max_width).x / 2.
	if boxed != rl.BLANK {
	    box_size := measure_text(text, font_size, spacing, max_width)+2*padding
		if box_width > 0 do box_size.x = box_width
	    draw_box(position - padding, box_size, boxed)
        // position += {padding, padding}
	}

	outline := outline
	if outline != rl.BLANK do outline.a = color.a

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
				if outline != rl.BLANK{
					rl.DrawTextCodepoint(
						font, r,
						position + rl.Vector2{text_offset_x, text_offset_y}-2.,
						font_size+6, outline)
				}
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

icon_index_from_id :: proc(texture_id: string) -> Vector2 {
	return app.sub_textures[texture_id] or_else {1, 0}
}

icon_index_from_card :: proc(card_type: CardType) -> Vector2 {
	return app.sub_textures[reflect.enum_string(card_type)] or_else {1, 0}
}

draw_texture :: proc{draw_texture_by_index, draw_texture_by_string}
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

	// if texture_id in app.sub_textures do tp = ts.yx * .yx

	dest := rl.Rectangle{x=position.x+size/2., y=position.y+size/2., width=size, height=size}
	rl.DrawTexturePro(texture, {x=tp.x, y=tp.y, width=ts.x, height=ts.y}, dest, {}+size/2., rotation, tint)
}

fade_out :: proc(){
	draw_box({-10, -10}, {app.gui.width+100, app.gui.height+100}, fill=rl.ColorAlpha(rl.BLACK, 0.8), thickness=0)
}

draw_card :: proc(card: Card, position: rl.Vector2, color:rl.Color=rl.BLANK, actions:[]string={}, static:bool=false, with_icon:bool=true) -> (bool, i32){
    size := CARD_SIZE
   	font_size :f32= app.gui.font_size2
	padding :f32= 10
	margin: f32 = 10
	header_height := font_size+2*padding

    if !with_icon do size.y = header_height
	hovered := with_icon && rl.CheckCollisionPointRec(rl.GetMousePosition(), {x=position.x, y=position.y, width=f32(size.x), height=f32(size.y)})

	color := color
	if color == rl.BLANK do color = COLOR_CARDS[card.category]

	position := position

	if hovered && !static{
		color = rl.ColorBrightness(color, 0.1)
		position.y += -10. //math.sin(f32(rl.GetTime())*10)*5
	}

	if card.active {
		color = rl.ColorBrightness(color, 0.15)
	} else if !hovered && card.triggered == 0.{
		color = rl.ColorBrightness(color, -0.3)
	}

	if card.triggered > 0. && !static{
		position.y += math.sin(f32(rl.GetTime())*20)*10
	}

	lt :f32= 4. // line_thickness

	if with_icon{
		rl.DrawRectangleV(position, size, color)
		lc := rl.Color{0, 0, 0, color.a} // color
		rl.DrawRectangleLinesEx({position.x-lt, position.y-lt, size.x+2*lt, size.y+2*lt}, lt, lc)
	}

	// Title
	rl.DrawRectangleV(position-lt, {size.x, header_height}+2*lt, rl.BLACK)
	draw_text(get_text(card.type, "title"), position + padding, font_size, rl.RAYWHITE, max_width=size.x-2*padding)
	icon_size := header_height - 2*padding
	icon_position := position+{size.x-icon_size-padding, padding}
	draw_texture(Vector2{0., 16.+f32(card.category)}, icon_position, icon_size, color)
	if card.category == .ROLL && card.lifetime > 0 {
		draw_text(fmt.tprintf("%v", card.lifetime),
			position+{size.x-padding-icon_size-2, padding}, font_size, rl.RAYWHITE, anchor=.RIGHT)
	}

	// main card icon
	if with_icon{
		icon_position = position+padding + {0., header_height}
		icon_size = min(size.x, size.y)-2*padding
		icon_color := hovered ? rl.ColorAlpha(color, 0.5) : color
		rl.DrawRectangleV(icon_position+40, {}+icon_size-2*40, rl.ColorBrightness(icon_color, -0.2))
		draw_texture(reflect.enum_string(card.type), icon_position, icon_size+math.sin(f32(rl.GetTime())+30*f32(card.type))*3, icon_color, rotation=math.sin(f32(rl.GetTime())+10*f32(card.type))*3)
	} else {
		margin = 0.
	}

	if hovered {
		button_pos := position + size + {-10, -45}

		for action, i in actions {
			if button(action, button_pos, font_size=font_size, anchor=.RIGHT) do return hovered, i32(i)
			button_pos += {-20-measure_text(action, font_size).x, 0}
		}
	}

	// Description
	show_description := hovered || !with_icon
	text_pos := position + {0., size.y+margin}+padding
	if show_description {
	    ids := []string{"description", "description2"}
		for id in ids{
		    if !has_text(card.type, id) do continue

			text := card_fill_vars(card, get_text(card.type, id))
            text_size := draw_text(
                    text, text_pos, font_size, rl.BLACK,
                    max_width=size.x-(text_pos.x-position.x), highlight_color=color, boxed=color, box_width=size.x)
            text_pos.y += text_size.y + 2*padding + margin
		}
	}

	return hovered, -1
}

draw_die_info :: proc(die: Die) -> i32{
	hovered_upgrade_index :i32= -1
	position := rl.GetWorldToScreen(die.position, app.camera3d)
	icon_size := f32(50.)
	margin := f32(10.)
    padding := f32(4.)

    box_size := Vector2{6*icon_size+10*padding, icon_size+3*padding+app.gui.font_size2}+2.*margin
    draw_box(position-margin, box_size, fill=rl.ColorAlpha(die.color1, 0.8), thickness=0.)

    card: Card
    card_position: Vector2
	#reverse for upgrade, u in die.upgrades{
		upgrade_pos := position + f32(u)*Vector2{icon_size+2*padding, 0.}
		upgraded := upgrade.type != .CardNone

        tp := Vector2{0, f32(die.faces[u]-1)} // Standard face number
        color: rl.Color
       	if !upgraded {
            color = die.color1
        } else {
        	color = COLOR_CARDS[.DICE]
       		tp = icon_index_from_card(upgrade.type)
        }

        dest := rl.Rectangle{x=upgrade_pos.x, y=upgrade_pos.y, width=icon_size, height=icon_size}
        hovered := rl.CheckCollisionPointRec(rl.GetMousePosition(), dest)
        if hovered {
			if upgraded {
			  	card_position = upgrade_pos + {-CARD_SIZE.x/2.+icon_size/2., icon_size+10}
				card = upgrade
			} else if app.card_selected.category == .DICE{
				tp = icon_index_from_card(app.card_selected.type)
   				color = COLOR_CARDS[.DICE]
			}
			hovered_upgrade_index = i32(u)
        }
        draw_box({dest.x, dest.y}-padding, {}+icon_size+2*padding, fill=upgraded ? color : rl.ColorAlpha(color, 0.8), thickness=1)
        draw_texture(tp, upgrade_pos, icon_size, tint=upgraded ? rl.BLACK : rl.RAYWHITE/2)
    }
    if card.type != .CardNone {
    	draw_card(card, position+{-margin+4., box_size.y+margin}, with_icon=false)
    }

    text := fmt.tprintf("Attack: %v, Health: %v", die.attack, die.health)
    text_position := position + padding
    text_position.y += icon_size + padding
    draw_text(text, text_position, color=rl.BLACK)

    return hovered_upgrade_index
}
