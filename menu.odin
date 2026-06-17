package game

import "core:fmt"
import rl "vendor:raylib"

menu_loop :: proc(dt:f32=0., loading:bool=false){
	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) || rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
		app.state = .Game
	} else if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
		app.state = .Exit

		return
	}

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(COLOR_TABLE)
	logo_size := Vector2{1000., 1000.}*S
	texture := app.textures[1]
	draw_texture(texture, {(L.width-logo_size.x)/2., (L.height-logo_size.y)/2.}, logo_size, rl.WHITE)
	// rl.DrawTextureV(texture,
	// 	{(L.width-f32(texture.width))/2., (L.height-f32(texture.height))/2.}, rl.WHITE)

	text := fmt.tprint("Press SPACE to continue")
	if loading do text = fmt.tprint("Loading...")
	draw_text(text, {L.width/2, L.height-100*S}, font_size=L.font_size1, color=rl.WHITE, anchor=.CENTER)
}
