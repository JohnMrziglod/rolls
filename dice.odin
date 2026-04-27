package game

import "core:fmt"
import "core:slice"

dice_killed :: proc(victim: ^Dice, killer: ^Dice=nil){
	player := &app.players[victim.player]

	if .CardRoll_Immortality in player.roll.effects{
		add_text(victim.position, fmt.aprint("IMMORTAL!"), victim.color, 1.5, font_size=app.gui.font_size2)
		return
	}

	add_particles(victim.position, victim.color)
	add_text(victim.position, fmt.aprint("GHOST!"), victim.color, 1.5, font_size=app.gui.font_size2)

	victim.state = .DEAD
	victim.position.y = 1000.

	if killer != nil do app.players[killer.player].roll.kills += 1

	if .CardRoll_Exorcism in player.roll.effects{
		add_text(victim.position, fmt.aprint("EXORCISED!"), victim.color, 1.5, font_size=app.gui.font_size2)
		return
	}

	if killer != nil && .CardRoll_WhiteElephant in player.roll.effects{
		other_player := &app.players[killer.player]
		if i32(len(other_player.ghosts)) >= other_player.ghosts_max do clear(&other_player.ghosts)
		append(&other_player.ghosts, victim.current_number)
		slice.sort(other_player.ghosts[:])
	} else {
		if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
		append(&player.ghosts, victim.current_number)
		slice.sort(player.ghosts[:])
	}
}
