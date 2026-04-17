package game

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

DiceUpgrade_Antenna :: struct {}
DiceUpgrade_Journalist :: struct {}

DiceUpgrade :: union{
	DiceUpgrade_Antenna,
	DiceUpgrade_Journalist,
}

Card :: struct{

}

draw_text :: proc(text: string, position: rl.Vector2, font_size: f32, color: rl.Color=rl.RAYWHITE, spacing:f32=1.0, max_width:f32=-1.){
	if max_width < 0. {
		rl.DrawTextEx(app.font,
			strings.clone_to_cstring(text, context.temp_allocator),
			position, font_size, spacing, color)

		return
	}

	// We need to wrap the text... below is the c function, we have to refactor it into odin...
	length := strings.rune_count(text)

	text_offset_y := f32(0)
	text_offset_x := f32(0)

	scale_factor := font_size / f32(app.font.baseSize)

	// Word/character wrapping mechanism variables
	measuring: true

	start_line := -1
	end_line := -1
	last_k := -1

	for codepoint, i in text {
		glyph_index := rl.GetGlyphIndex(app.font, codepoint)

		glyph_width := f32(0)
		if codepoint != '\n' {
			if app.font.glyphs[glyph_index].advanceX == 0 {
				glyph_width = f32(app.font.recs[glyph_index].width) * scale_factor
			} else {
				glyph_width = f32(app.font.glyphs[glyph_index].advanceX) * scale_factor
			}

			if i + 1 < length {
				glyph_width += spacing
			}
		}

		if measuring {
			if codepoint == ' ' || codepoint == '\t' || codepoint == '\n' {
				end_line = i
			}

			if text_offset_x + glyph_width > max_width {
				if end_line < 1 {
					end_line = i
				}
				if i == end_line {
					end_line -= 1
				}
				if start_line + 1 == end_line {
					end_line = i - 1
				}

				measuring = false
			} else if i + 1 == length {
				end_line = i
				measuring = false
			} else if codepoint == '\n' {
				measuring = false
			}

			if !measuring {
				text_offset_x = 0
				i = start_line

				last_k, k = k, last_k // swap

			}
		} else {
			if codepoint == '\n' {
				text_offset_y += (f32(app.font.baseSize) + f32(app.font.baseSize)/2) * scale_factor
				text_offset_x = 0
			} else {
				if text_offset_x + glyph_width > max_width {
					text_offset_y += (f32(app.font.baseSize) + f32(app.font.baseSize)/2) * scale_factor
					text_offset_x = 0
				}

				if text_offset_y + f32(app.font.baseSize) * scale_factor > max_width {
					break
				}

				if codepoint != ' ' && codepoint != '\t' {
					draw_text(string{codepoint}, position + rl.Vector2{text_offset_x, text_offset
}

// Draw text using font inside rectangle limits
// static void DrawTextBoxed(Font font, const char *text, Rectangle rec, float fontSize, float spacing, bool wordWrap, Color tint)
// {
//     DrawTextBoxedSelectable(font, text, rec, fontSize, spacing, wordWrap, tint, 0, 0, WHITE, WHITE);
// }

// // Draw text using font inside rectangle limits with support for text selection
// static void DrawTextBoxedSelectable(Font font, const char *text, Rectangle rec, float fontSize, float spacing, bool wordWrap, Color tint, int selectStart, int selectLength, Color selectTint, Color selectBackTint)
// {
//     int length = TextLength(text);  // Total length in bytes of the text, scanned by codepoints in loop

//     float textOffsetY = 0;          // Offset between lines (on line break '\n')
//     float textOffsetX = 0.0f;       // Offset X to next character to draw

//     float scaleFactor = fontSize/(float)font.baseSize;     // Character rectangle scaling factor

//     // Word/character wrapping mechanism variables
//     enum { MEASURE_STATE = 0, DRAW_STATE = 1 };
//     int state = wordWrap? MEASURE_STATE : DRAW_STATE;

//     int startLine = -1;         // Index where to begin drawing (where a line begins)
//     int endLine = -1;           // Index where to stop drawing (where a line ends)
//     int lastk = -1;             // Holds last value of the character position

//     for (int i = 0, k = 0; i < length; i++, k++)
//     {
//         // Get next codepoint from byte string and glyph index in font
//         int codepointByteCount = 0;
//         int codepoint = GetCodepoint(&text[i], &codepointByteCount);
//         int index = GetGlyphIndex(font, codepoint);

//         // NOTE: Normally we exit the decoding sequence as soon as a bad byte is found (and return 0x3f)
//         // but we need to draw all of the bad bytes using the '?' symbol moving one byte
//         if (codepoint == 0x3f) codepointByteCount = 1;
//         i += (codepointByteCount - 1);

//         float glyphWidth = 0;
//         if (codepoint != '\n')
//         {
//             glyphWidth = (font.glyphs[index].advanceX == 0) ? font.recs[index].width*scaleFactor : font.glyphs[index].advanceX*scaleFactor;

//             if (i + 1 < length) glyphWidth = glyphWidth + spacing;
//         }

//         // NOTE: When wordWrap is ON we first measure how much of the text we can draw before going outside of the rec container
//         // We store this info in startLine and endLine, then we change states, draw the text between those two variables
//         // and change states again and again recursively until the end of the text (or until we get outside of the container)
//         // When wordWrap is OFF we don't need the measure state so we go to the drawing state immediately
//         // and begin drawing on the next line before we can get outside the container
//         if (state == MEASURE_STATE)
//         {
//             // TODO: There are multiple types of spaces in UNICODE, maybe it's a good idea to add support for more
//             // Ref: http://jkorpela.fi/chars/spaces.html
//             if ((codepoint == ' ') || (codepoint == '\t') || (codepoint == '\n')) endLine = i;

//             if ((textOffsetX + glyphWidth) > rec.width)
//             {
//                 endLine = (endLine < 1)? i : endLine;
//                 if (i == endLine) endLine -= codepointByteCount;
//                 if ((startLine + codepointByteCount) == endLine) endLine = (i - codepointByteCount);

//                 state = !state;
//             }
//             else if ((i + 1) == length)
//             {
//                 endLine = i;
//                 state = !state;
//             }
//             else if (codepoint == '\n') state = !state;

//             if (state == DRAW_STATE)
//             {
//                 textOffsetX = 0;
//                 i = startLine;
//                 glyphWidth = 0;

//                 // Save character position when we switch states
//                 int tmp = lastk;
//                 lastk = k - 1;
//                 k = tmp;
//             }
//         }
//         else
//         {
//             if (codepoint == '\n')
//             {
//                 if (!wordWrap)
//                 {
//                     textOffsetY += (font.baseSize + (float)font.baseSize/2)*scaleFactor;
//                     textOffsetX = 0;
//                 }
//             }
//             else
//             {
//                 if (!wordWrap && ((textOffsetX + glyphWidth) > rec.width))
//                 {
//                     textOffsetY += (font.baseSize + (float)font.baseSize/2)*scaleFactor;
//                     textOffsetX = 0;
//                 }

//                 // When text overflows rectangle height limit, just stop drawing
//                 if ((textOffsetY + font.baseSize*scaleFactor) > rec.height) break;

//                 // Draw selection background
//                 bool isGlyphSelected = false;
//                 if ((selectStart >= 0) && (k >= selectStart) && (k < (selectStart + selectLength)))
//                 {
//                     DrawRectangleRec((Rectangle){ rec.x + textOffsetX - 1, rec.y + textOffsetY, glyphWidth, (float)font.baseSize*scaleFactor }, selectBackTint);
//                     isGlyphSelected = true;
//                 }

//                 // Draw current character glyph
//                 if ((codepoint != ' ') && (codepoint != '\t'))
//                 {
//                     DrawTextCodepoint(font, codepoint, (Vector2){ rec.x + textOffsetX, rec.y + textOffsetY }, fontSize, isGlyphSelected? selectTint : tint);
//                 }
//             }

//             if (wordWrap && (i == endLine))
//             {
//                 textOffsetY += (font.baseSize + (float)font.baseSize/2)*scaleFactor;
//                 textOffsetX = 0;
//                 startLine = endLine;
//                 endLine = -1;
//                 glyphWidth = 0;
//                 selectStart += lastk - k;
//                 k = lastk;

//                 state = !state;
//             }
//         }

//         if ((textOffsetX != 0) || (codepoint != ' ')) textOffsetX += glyphWidth;  // avoid leading spaces
//     }
// }

draw_card :: proc(id: typeid, position: rl.Vector2, color: rl.Color) {
	font_size :f32= 30
	size := [2]f32{450, 200}
	padding :f32= 10
	line_pos := font_size+2*padding
	lt :f32= 4. // line_thickness
	rl.DrawRectangleV(position, size, color)
	lc := color / 2 // line color
	lc.a = color.a
	rl.DrawRectangleLinesEx({position.x-4, position.y-4, size.x+2*lt, size.y+2*lt}, lt, lc)
	rl.DrawLineEx({position.x+padding, position.y+line_pos}, {position.x+size.x-padding, position.y+line_pos}, lt, lc)

	// Title
	text_pos := position + {padding, padding}
	text_id := fmt.tprintf("title/%v", id)
	draw_text(app.texts[text_id], text_pos, font_size, rl.BLACK)

	// Description
	text_pos += {0, line_pos+padding}
	text_id = fmt.tprintf("description/%v", id)
	draw_text(app.texts[text_id], text_pos, font_size, rl.BLACK)
}
