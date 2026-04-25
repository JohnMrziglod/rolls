package game

import "core:fmt"
import "core:slice"

dice_kills :: proc(killer, victim: ^Dice){
	add_particles(victim.position, victim.color)
	add_text(victim.position, fmt.aprint("GHOST!"), victim.color, 1.5, font_size=app.gui.font_size2)

	victim.state = .DEAD
	victim.position.y = 1000.

	player := &app.players[victim.player]
	if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
	append(&player.ghosts, victim.current_number)
	// Sort the ghost dices (makes other things easier later on also for the human player)
	slice.sort(player.ghosts[:])

	app.players[killer.player].roll.kills += 1
}
