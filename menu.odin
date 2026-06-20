package game

import "core:fmt"
import rl "vendor:raylib"

menu_loop :: proc(dt:f32=0., loading:bool=false){
	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(COLOR_TABLE)
	logo_size := Vector2{1000., 1000.}*S
	texture := app.textures[1]
	draw_texture(texture, {(L.width-logo_size.x)/2., (L.height-logo_size.y)/2.}, logo_size, rl.WHITE)
	// rl.DrawTextureV(texture,
	// 	{(L.width-f32(texture.width))/2., (L.height-f32(texture.height))/2.}, rl.WHITE)

	if loading {
		draw_text("Loading...", {L.width/2, L.height-100*S}, L.font_size2, anchor=.CENTER)
		return
	}

	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) || continue_button() do app.state = .Game
	if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) do app.state = .Exit
}
