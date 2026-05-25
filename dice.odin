package game

import "core:fmt"
import "core:slice"

dice_killed :: proc(victim: ^Die, killer: ^Die=nil){
	player := &app.players[victim.player]
	player2 := &app.players[(victim.player+1) % 2]

	if .CardRoll_Immortality in player.roll.effects{
		add_text(victim.position, fmt.aprint("IMMORTAL!"), victim.color1, 1.5)
		return
	}

	add_particles(victim.position, victim.color1)
	add_text(victim.position, app.gui.ghost_positions[victim.player], fmt.aprint("GHOST!"), victim.color1, 1.5)

	victim.state = .DEAD
	victim.position.y = 1000.
	body_calculate_derived_data(victim)

	player2.roll.kills += 1

	if .CardRoll_Exorcism in player.roll.effects{
		add_text(victim.position, fmt.aprint("EXORCISED!"), victim.color1, 1.5)
		return
	}

	if .CardRoll_WhiteElephant in player.roll.effects{
		if i32(len(player2.ghosts)) >= player2.ghosts_max do clear(&player2.ghosts)
		append(&player2.ghosts, victim.current_number)
		slice.sort(player2.ghosts[:])
	} else {
		if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
		append(&player.ghosts, victim.current_number)
		slice.sort(player.ghosts[:])
	}
}

dice_fight :: proc(die1: ^Die, die2: ^Die) {
    app.battle.dice = {die1, die2}
    app.battle.previous_positions = {die1.position, die2.position}
    app.battle.state = .Fighting
    app.battle.timer = 0.
}

die_has_upgrade :: proc(die: Die, card_type: CardType) -> bool{
	for upgrade in die.upgrades{
		if upgrade.type == card_type do return true
	}
	return false
}
