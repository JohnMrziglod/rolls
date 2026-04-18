package game

import "core:unicode/utf8"
import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

CardUpgrade_Antenna :: struct {}
CardUpgrade_Journalist :: struct {}

Cards :: union{
	CardUpgrade_Antenna,
	CardUpgrade_Journalist,
}

measure_text :: proc(text: string, font_size: f32, spacing:f32=1.0) -> rl.Vector2 {
	font := app.font
	scale_factor := font_size / f32(font.baseSize)

	width :f32= 0.
	height :f32= 0.

	for r in text{
		if r == '\n' {
			height += 1.5 * f32(font.baseSize) * scale_factor
			width = 0.
			continue
		}

		glyph_index := rl.GetGlyphIndex(font, r)
		if font.glyphs[glyph_index].advanceX == 0 {
			width += f32(font.recs[glyph_index].width) * scale_factor
		} else {
			width += f32(font.glyphs[glyph_index].advanceX) * scale_factor
		}
		width += spacing
	}

	return rl.Vector2{width, height + 1.5 * f32(font.baseSize) * scale_factor}
}

draw_text :: proc(text: string, position: rl.Vector2, font_size: f32, color: rl.Color=rl.RAYWHITE, spacing:f32=1.0, max_width:f32=-1.){
	if max_width < 0. {
		rl.DrawTextEx(app.font,
			strings.clone_to_cstring(text, context.temp_allocator),
			position, font_size, spacing, color)

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


draw_card :: proc(id: typeid, position: rl.Vector2, color:rl.Color={1, 1, 1, 0}) {
	text_id := fmt.tprintf("title/%v", id)
	color := color
	if color == {1, 1, 1, 0} {
		if strings.contains(text_id, "CardUpgrade") {
			color = COLOR_CARDS[.UPGRADE]
		} else if strings.contains(text_id, "CardRoll") {
			color = COLOR_CARDS[.ROLL]
		} else {
			color = COLOR_CARDS[.CYCLE]
		}
	}

	font_size :f32= app.gui.font_size2
	size := app.gui.card_size
	padding :f32= 10
	line_pos := font_size+2*padding
	lt :f32= 4. // line_thickness
	lc := rl.BLACK // color / 2 // line color
	lc.a = color.a
	rl.DrawRectangleV(position+{10, 10}, size, rl.BLACK)
	rl.DrawRectangleV(position, size, color)
	rl.DrawRectangleV(position, {size.x, line_pos}, rl.BLACK)

	rl.DrawRectangleLinesEx({position.x-4, position.y-4, size.x+2*lt, size.y+2*lt}, lt, lc)
	// rl.DrawLineEx({position.x+padding, position.y+line_pos}, {position.x+size.x-padding, position.y+line_pos}, lt, lc)

	// Title
	text_pos := position + {padding, padding}
	draw_text(app.texts[text_id], text_pos, font_size, rl.RAYWHITE, max_width=size.x-2*padding)

	// Description
	text_pos += {0, line_pos+padding}
	text_id = fmt.tprintf("description/%v", id)
	draw_text(app.texts[text_id], text_pos, font_size, rl.BLACK, max_width=size.x-2*padding)
}
