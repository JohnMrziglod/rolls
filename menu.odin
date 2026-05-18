package game

import "core:fmt"
import rl "vendor:raylib"

menu :: proc(dt:real=0., loading:bool=false){
	if rl.IsKeyPressed(rl.KeyboardKey.SPACE) || rl.IsMouseButtonPressed(rl.MouseButton.LEFT) {
		app.state = app.state_before
	}
	if rl.IsKeyPressed(rl.KeyboardKey.ESCAPE) {
		app.state = .EXIT
	}

	rl.BeginDrawing()
	defer rl.EndDrawing()

	rl.ClearBackground(COLOR_TABLE)
	logo_size := Vector2{200., 200.}
	texture := app.textures[1]
	rl.DrawTextureV(texture,
		{(app.gui.width-f32(texture.width))/2., (app.gui.height-f32(texture.height))/2.}, rl.WHITE)

	text := fmt.tprint("Press SPACE to continue")
	if loading do text = fmt.tprint("Loading...")
	draw_text(text, {app.gui.width/2, app.gui.height-100}, font_size=app.gui.font_size1, color=rl.WHITE, anchor=.CENTER)
}
