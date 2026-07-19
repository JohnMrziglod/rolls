package game

import "core:fmt"
import "core:os"
import "core:math/rand"
import "core:strings"
import rl "vendor:raylib"

AppState :: enum{Menu, Game, Exit}

Application :: struct {
	// resources
	font:        	rl.Font,
	textures:    	[]rl.Texture2D,
	sub_textures:	map[string]Vector2,
	sounds:      	[]rl.Sound,
	musics:      	[]rl.Music,
	texts:       	map[string]string,

	// state handling
	state: 			AppState,
	tutorials_off: 	bool,
}
app: Application

main :: proc() {
	rl.SetTraceLogLevel(.ERROR)

	// Initialize window
	init_window()
	defer rl.CloseWindow()

	// w := rl.GetMonitorWidth(rl.GetCurrentMonitor())
	// h := rl.GetMonitorHeight(rl.GetCurrentMonitor())
	// rl.ClearWindowState({ .WINDOW_RESIZABLE })
	// rl.ToggleFullscreen()
	// rl.SetWindowSize(w, h)


	// rl.SetWindowState({.WINDOW_UNDECORATED, .BORDERLESS_WINDOWED_MODE})
	// rl.SetWindowSize(L.width, L.height)
	// rl.SetTargetFPS(60)

	// toggle the state
	// rl.ToggleBorderlessWindowed()
	// rl.MaximizeWindow()
	// rl.SetWindowPosition(0, 30)
	rl.SetExitKey(.KEY_NULL) // we don't want the window to be closed by accident

	app = {
		font = rl.LoadFont("assets/fonts/Paperlogy-6SemiBold.ttf"),
		tutorials_off = true
	}
	defer rl.UnloadFont(app.font)
	rl.GenTextureMipmaps(&app.font.texture)
	rl.SetTextureFilter(app.font.texture, .TRILINEAR)

	app.textures = {
		rl.LoadTexture("assets/textures/die.png"),
		rl.LoadTexture("assets/textures/title.png"),
		rl.LoadTexture("assets/textures/antagonists.png"),
	}
	for &texture in app.textures {
		rl.GenTextureMipmaps(&texture)
		rl.SetTextureFilter(texture, .TRILINEAR)
	}
	defer {
		for texture in app.textures {
			rl.UnloadTexture(texture)
		}
	}

	menu_loop(loading = true)

	rl.InitAudioDevice()
	defer rl.CloseAudioDevice()

	app.sounds = {
		rl.LoadSound("assets/sounds/dice_1.wav"),
		rl.LoadSound("assets/sounds/dice_2.wav"),
		rl.LoadSound("assets/sounds/dice_3.wav"),
		rl.LoadSound("assets/sounds/dice_4.wav"),
		rl.LoadSound("assets/sounds/dice_5.wav"),
		rl.LoadSound("assets/sounds/dice_elimination.wav"),
		rl.LoadSound("assets/sounds/dice_scores_1.wav"),
		rl.LoadSound("assets/sounds/dice_scores_2.wav"),
		rl.LoadSound("assets/sounds/dice_scores_3.wav"),
		rl.LoadSound("assets/sounds/dice_scores_4.wav"),
		rl.LoadSound("assets/sounds/card_activate.wav"),
		rl.LoadSound("assets/sounds/card_discard.wav"),
		rl.LoadSound("assets/sounds/button.wav"),
	}
	defer {
		for sound in app.sounds {
			rl.UnloadSound(sound)
		}
	}
	music_files, music_files_ok := os.glob("assets/music/*.mp3", context.temp_allocator)
	if music_files_ok != nil {
		fmt.panicf("%v", music_files_ok)
		// os.exit(1)
	}
	current_music_file := strings.clone_to_cstring(rand.choice(music_files[:]))
	fmt.printfln("Playing music: %s", current_music_file)
	defer delete(current_music_file)
	app.musics = {
		rl.LoadMusicStream(current_music_file),
		// rl.LoadMusicStream("assets/sounds/music_2.ogg"),
	}
	rl.PlayMusicStream(app.musics[0])
	defer {
		for music in app.musics {
			rl.UnloadMusicStream(music)
		}
	}

	files: [2]string
	load_data(&files[0], "assets/cards.toml")
	load_data(&files[1], "assets/antagonists.toml")
	defer {
		for file in files do defer delete(file)
	}
	load_info()

	for !rl.WindowShouldClose() {
		if app.state == .Exit do break

		if rl.IsKeyPressed(rl.KeyboardKey.T) do app.tutorials_off = !app.tutorials_off

		dt := rl.GetFrameTime()
		if (!rl.IsWindowFocused()) {
			rl.MinimizeWindow()
			rl.BeginDrawing()
			rl.EndDrawing()
			continue
		}

		w := f32(rl.GetScreenWidth())
		h := f32(rl.GetScreenHeight())
		if L.width != w || L.height != h {
			update_layout()
		}

		#partial switch app.state {
		case .Menu:
			menu_loop(dt)
		case .Game:
			game_loop(dt)
		}

		// Free the temp arena at the end of the frame
		free_all(context.temp_allocator)
	}
}

init_window :: proc(){
	display := rl.GetCurrentMonitor()
	// if we are not full screen, set the window size to match the monitor we are on
	L.width = 1200//f32(rl.GetMonitorWidth(display))
	L.height = 800//f32(rl.GetMonitorHeight(display))

	rl.SetConfigFlags({.WINDOW_RESIZABLE})
	rl.InitWindow(i32(L.width), i32(L.height), "Rolls")
	rl.SetTargetFPS(60)

	update_layout()
}
