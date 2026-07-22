package game

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:math/rand"
import "core:slice"

import rl "vendor:raylib"


dice_init :: proc(die: ^Die, position := Vector3{0, 1000, 0}) {
	half_size: f32 = DICE_HALF_SIZE
	mass := math.pow(half_size, 3) * 8.

	die^ = {
		state = .DEAD,
		shape = ShapeBox{half_size = half_size},
		position = position,
		orientation = random_orientation(),
		rotation = random_vector(-20.0, 20.0),
		acceleration = Vector3{0.0, -50.0, 0.0},
		linear_damping = 0.99,
		angular_damping = 0.9,
		inverse_mass = 1. / mass,
		can_sleep = true,

		current_number = 0,
		current_score = 0,
		attack = 1,
		health = 1,
		faces = {1, 2, 3, 4, 5, 6},
		killed_by = -1,

		// things we keep over the rolls:
		player = die.player,
		color = die.color,
		velocity = die.velocity,
		upgrades = die.upgrades,
		total_score = die.total_score,
		total_kills = die.total_kills,
		total_deaths = die.total_deaths,
	}
}

dice_reset :: proc(power: f32 = 1., reset_all:bool=false) {
	for &die, d in game.dice {
		if die.player == game.current_player || reset_all {
			position := random_vector(-AREA_SIZE / 8.0, AREA_SIZE / 8.0)
			position.z += -AREA_SIZE / 2.0
			position.y += AREA_SIZE / 4.0 + 10.
			velocity :=
				game.power *
				Vector3 {
						rand.float32_range(-20, 20),
						rand.float32_range(-20, -10),
						rand.float32_range(-1, 100),
					}

			dice_init(&die, position)
			die.state = .ALIVE
			die.velocity = velocity
		}
		body_set_awake(&die)

		// body_clear_accumulators(&dice)
		body_set_block_inertia_tensor(&die, die.shape.(ShapeBox).half_size, 1. / die.inverse_mass)
		body_calculate_derived_data(&die)

		die.health = 1
		die.attack = 1
	}
}

apply_dice_upgrades :: proc(dt: real) {
	for &dice, d in game.dice {
		for &upgrade, u in dice.upgrades {
			#partial switch upgrade.type {
			case .CardDice_Optimist:
				dice.faces = {4, 4, 5, 5, 6, 6}
			case .CardDice_Pessimist:
				dice.faces = {1, 1, 2, 2, 3, 3}
			}
		}
	}
}

dice_upgrades :: proc(dt: real) {
	max_delay: f32
	duration: f32 = 0.8
	for &die, d in game.dice {
		if die.state != .ALIVE do continue

		delay: f32
		for &upgrade, u in die.upgrades {
			text: string
			on_top := die.current_face == u

			#partial switch upgrade.type {
			case .CardDice_Assassin:
				die.attack += 2
				text = fmt.aprint("+2 ATTACK")
			case .CardDice_Tank:
				die.health += 2.
				text = fmt.aprint("+2 HEALTH")
			case .CardDice_Veteran:
				if on_top {
					die.health += 1.
					text = fmt.aprint("+1 HEALTH")
				}
			case:
				continue
			}
			if len(text) > 0 {
				add_text(
					die.position,
					text,
					die.color,
					delay = delay,
					lifetime = duration,
					icon_id = icon_index_from_card(upgrade.type),
				)

				delay += duration
			}
		}
		max_delay = max(max_delay, delay)
	}

	state_change(.CARDS_BATTLE, wait = max_delay)
}

dice_battle :: proc(dt: real) {
	if game.battle.state != .Over {
		battle := &game.battle
		battle.timer += dt * game.speed
		target_time: f32 = 0.5

		clash_position := (battle.previous_positions[0] + battle.previous_positions[1]) / 2.
		clash_position.y += 6.

		#partial switch battle.state {
		case .Fighting:
			for &die, d in game.battle.dice {
				die.position = linalg.lerp(
					battle.previous_positions[d],
					clash_position,
					battle.timer / target_time,
				)
				body_calculate_derived_data(die) // to update the transformation matrix, etc...
			}
			if battle.timer > target_time {
				die1 := game.battle.dice[0]
				die2 := game.battle.dice[1]
				die1_alive_before := die1.health > 0
				die2_alive_before := die2.health > 0
				attack_left1 := math.max(die1.attack - die2.health, 0)
				attack_left2 := math.max(die2.attack - die1.health, 0)
				die1.health = math.max(die1.health - die2.attack, 0)
				die2.health = math.max(die2.health - die1.attack, 0)
				die1.attack = attack_left1
				die2.attack = attack_left2

				if die1_alive_before && die1.health == 0 {
					dice_kills(die2, die1)
				}
				if die2_alive_before && die2.health == 0 {
					dice_kills(die1, die2)
				}
				// if die1.health == 0 do game.players[die2.player].roll.kills += 1
				// if die2.health == 0 do game.players[die1.player].roll.kills += 1

				add_particles(die1.position, die1.color)
				add_particles(die2.position, die2.color)
				// add_text(die1.position, fmt.aprint("FIGHT!"), rl.RAYWHITE, 1.5)

				sound := app.sounds[5]
				rl.SetSoundVolume(sound, rand.float32_range(0.8, 1.)) // Set volume based on bounce speed
				rl.SetSoundPitch(
					sound,
					0.1 + f32(game.players[die1.player].roll.kills) / f32(len(game.dice) / 2.),
				) // Add some random pitch variation
				rl.PlaySound(sound)

				battle.state = .Retreating
				battle.timer = 0.
			}
		case .Retreating:
			for &die, d in game.battle.dice {
				die.position = linalg.lerp(
					die.position,
					battle.previous_positions[d],
					battle.timer / target_time,
				)
				body_calculate_derived_data(die) // to update the transformation matrix, etc...
			}
			if battle.timer > target_time {
				battle.state = .Over
				battle.timer = 0.
			}
		}
		return
	}

	// We eliminate all game.dice from each player that show the same numbers.
	// E.g. if player 1 has two game.dice showing a 3 and player 2 has one dice showing a 3,
	// one dice each is eliminated and won't give points to either player.
	for &die, d in game.dice {
		if die.state != .ALIVE do continue
		has_drunk_upgrade := die_has_upgrade(die, .CardDice_Drunk)
		for &die2, d2 in game.dice {
			bid := battle_id(d, d2)
			if bid in game.battle.seen || d == d2 || die2.state != .ALIVE || die.player == die2.player do continue

			can_attack := die.current_number == die2.current_number
			can_attack |= has_drunk_upgrade
			if can_attack && ((die.attack > 0 && die2.health > 0)|| (die2.attack > 0 && die.health > 0)) {
				dice_fight(&die, &die2)
				game.battle.seen[bid] = true
				return
			}
		}
	}

	game.battle.seen = {}

	// Show me the immortal ones
	for &player, p in game.players {
		if .CardRoll_Immortality not_in player.roll.effects do continue

		for d in player.dice_sorted {
			die := &game.dice[d]

			if die.health > 0 || die.state != .ALIVE do continue

			add_text(die.position, fmt.aprint("IMMORTAL!"), die.color, 2.0)
		}
	}

	state_change(.DICE_DEATHS, 0.1)
}

dice_deaths :: proc(dt: real) {
	for &die, d in game.dice {
		if die.health > 0 || die.state != .ALIVE do continue

		// Immortal ones cannot die
		if .CardRoll_Immortality in game.players[die.player].roll.effects do continue

		die_death(&die)
		wait(1.)
		return
	}

	state_change(.DICE_SCORING, 0.4)
}

dice_scoring :: proc(dt: real) {
	for &player, p in game.players {
		other_player := &game.players[(p + 1) % N_PLAYERS]

		player.is_scoring = true
		n_alive := 0
		for die in game.dice {
			if die.state == .ALIVE && u8(p) == die.player do n_alive += 1
		}

		for d in player.dice_sorted {
			die := &game.dice[d]
			if die.state != .ALIVE || die.already_scored do continue

			die.current_score = sco(die.current_number)

			// Apply dice card effects
			n_events := 0
			delay: f32
			duration: f32 : 0.8
			for &upgrade, u in die.upgrades {
				on_top := die.current_face == u
				text: string

				#partial switch upgrade.type {
				case .CardDice_Antenna:
					factor := 0.
					for d2 in player.dice_sorted {
						die2 := &game.dice[d2]
						if d == d2 || die2.state != .ALIVE do continue

						if die_has_upgrade(die2^, .CardDice_Antenna) {
							// add_text(die2.position, fmt.aprint("ANTENNA BOOST!"), COLOR_UPGRADES[.CardDice_Antenna], lifetime=0.6)
							factor += sco(die2.current_number)
						}
					}
					if factor > 0. {
						text = fmt.aprintf("x%.f!", factor)
						die.current_score *= factor
					}

				case .CardDice_Journalist:
					if .CardRoll_FakeNews in player.roll.effects ||
					   .CardRoll_FakeNews in other_player.roll.effects {
						player.roll.factor /= 2.
						text = fmt.aprint("x0.5 ROLL FACTOR")
					} else {
						player.roll.factor += 1
						text = fmt.aprint("+1 ROLL FACTOR")
					}
				case .CardDice_Influencer:
					if on_top {
						append(&player.cards, Card{})
						cards_generate(player.cards[len(player.cards) - 1:], .RollCards)
						text = fmt.aprint("+1 ROLL CARD")
					}
				case .CardDice_Engineer:
					if on_top {
						append(&player.cards, Card{})
						cards_generate(player.cards[len(player.cards) - 1:], .DiceCards)
						text = fmt.aprint("+1 DICE CARD")
					}
				case .CardDice_Investor:
					if on_top {
						text = fmt.aprintf("PAYOUT +%.f", upgrade.var1)
						die.current_score += math.floor(upgrade.var1)
						upgrade.var1 = 0.
					} else {
						upgrade.var1 += die.current_score
						upgrade.var1 *= 1.1
						die.current_score = 0
						text = fmt.aprintf("SAVING %.1f", upgrade.var1)
					}
				case .CardDice_General:
					if n_alive > 1 {
						text = fmt.aprintf("x%v", n_alive)
						die.current_score *= sco(n_alive)
					}
				case .CardDice_Historian:
					if upgrade.var1 != 0. {
						text = fmt.aprintf("+%.f", upgrade.var1)
						die.current_score += upgrade.var1
					}
				case .CardDice_Researcher:
					if upgrade.var1 != 0. {
						text = fmt.aprintf("X%.f", upgrade.var1)
						player.roll.factor += upgrade.var1
					}
				case .CardDice_Medium:
					text = fmt.aprintf("+%v", len(player.ghosts))
					die.current_score += sco(len(player.ghosts))
				case .CardDice_Optimist:
					if on_top {
						bonus := 0.
						for o in player.dice_sorted {
							die2 := &game.dice[o]
							if d == o || die2.state != .ALIVE || die2.current_number < 4 do continue
							bonus += sco(die2.current_number)
							add_text(
								die2.position,
								fmt.aprintf("+%v", die2.current_number),
								die2.color,
								delay = delay,
								lifetime = duration,
								icon_id = icon_index_from_id("CardDice_Optimist"),
								icon_size = 50,
							)
							delay += duration / 3.
						}
						text = fmt.aprintf("+%.f", bonus)
						die.current_score += bonus
					}
				case .CardDice_Pirate:
					highest_score: sco
					highest_die: i32
					for d2 in other_player.dice_sorted {
						die2 := &game.dice[d2]
						if die2.state != .ALIVE || sco(die2.current_number) <= highest_score do continue
						highest_score = sco(die2.current_number)
						highest_die = d2
					}
					text = fmt.aprintf("+%.f", highest_score)
					die.current_score += highest_score
					die2 := &game.dice[highest_die]
					add_text(
						die2.position,
						fmt.aprintf("+%v", die2.current_number),
						die2.color,
						delay = delay,
						lifetime = duration,
						icon_id = icon_index_from_id("CardDice_Pirate"),
						icon_size = 50,
					)
					delay += duration / 3.
				case .CardDice_PlusOne:
					plus_score := 1
					if on_top do plus_score += n_alive - 1
					text = fmt.aprintf("+%v", plus_score)
					die.current_score += sco(plus_score)
				case .CardDice_Pessimist:
					if on_top {
						factor := 0.
						for o in player.dice_sorted {
							die2 := &game.dice[o]
							if d == o || die2.state != .ALIVE || die2.current_number > 3 do continue
							factor += sco(die2.current_number)
							add_text(
								die2.position,
								fmt.aprintf("+%v", die2.current_number),
								die2.color,
								delay = delay,
								lifetime = duration,
								icon_id = icon_index_from_id("CardDice_Pessimist"),
								icon_size = 50,
							)
							delay += duration / 3.
						}
						if factor > 0. {
							text = fmt.aprintf("x%.f", factor)
							die.current_score *= factor
						}
					}
				case .CardDice_Randomizer:
					random_bonus := rand.int32_range(1, 7)
					text = fmt.aprintf("+%v", random_bonus)
					die.current_score += sco(random_bonus)
				case .CardDice_Train:
					bonus := 0.
					n_dice := 0
					for d2 in player.dice_sorted {
						die2 := &game.dice[d2]
						if d == d2 || die2.state != .ALIVE || die2.current_number <= die.current_number do continue
						bonus += sco(die2.current_number)
						add_text(
							die2.position,
							fmt.aprintf("+%v", die2.current_number),
							die2.color,
							delay = delay,
							lifetime = duration,
							icon_id = icon_index_from_id("CardDice_Train"),
							icon_size = 50,
						)
						delay += duration / 3.
					}
					if bonus > 0. {
						text = fmt.aprintf("+%.f", bonus)
						die.current_score += bonus
					}
				case .CardDice_Librarian:
					if upgrade.var1 != 0. {
						text = fmt.aprintf("+%.f", upgrade.var1)
						die.current_score += upgrade.var1
					}
				case .CardDice_PowerUp:
					if on_top {
						upgrade.var1 += 1.
					}
					text = fmt.aprintf("X%.f", upgrade.var1)
					die.current_score *= upgrade.var1
				case .CardDice_Veteran:
					upgrade.var1 += 2
					text = fmt.aprintf("+%.f", upgrade.var1)
					die.current_score += sco(upgrade.var1)
				case .CardDice_WarHero:
					text = fmt.aprintf("+%.f", upgrade.var1)
					die.current_score += sco(upgrade.var1)
				case:
					continue
				}
				if len(text) > 0 {
					add_text(
						die.position,
						text,
						die.color,
						delay = delay,
						lifetime = duration,
						icon_id = icon_index_from_card(upgrade.type),
					)
					delay += duration
				}
			}

			if die.current_score != 0 || delay > 0 {
				die.already_scored = true
				player.roll.score += die.current_score
				player.roll.score_timer = 1.
				player.roll.score_counter += 1

				pitch: f32 = 1.0 + ((p == 0) ? 0.1 : -0.1) * f32(player.roll.score_counter)
				play_sound(6, pitch = pitch)

				add_text(
				    die.position,
				    fmt.aprintf("+%.f", die.current_score),
					die.color,
					delay = delay,
					lifetime = 0.9*duration,
				)
				wait(delay + 0.9*duration)
			}

			return
		}
		player.is_scoring = false
	}

	state_change(.CARDS_SCORING, 0.2)
}


dice_kills :: proc(killer: ^Die, victim: ^Die) {
	for &upgrade in killer.upgrades{
		if upgrade.type == .CardDice_WarHero do upgrade.var1 += 1
	}
	victim.killed_by = killer.id
}

die_death :: proc(victim: ^Die, killer: ^Die=nil){
	player := &game.players[victim.player]
	player2 := &game.players[(victim.player+1) % 2]

	if .CardRoll_Immortality in player.roll.effects{
		add_text(victim.position, fmt.aprint("IMMORTAL!"), victim.color, 2.0)
		return
	}

	add_particles(victim.position, victim.color)
	add_text(victim.position, L.ghost_positions[victim.player],
			"", rl.ColorAlpha(victim.color, .5), 1.0, icon_id=Vector2{0, 7+f32(victim.current_number)},
		    icon_size=L.font_size1)

	victim.state = .DEAD
	victim.total_deaths += 1
	victim.position.y = 1000.
	body_calculate_derived_data(victim)

	player2.roll.kills += 1

	for &upgrade, u in victim.upgrades{
		if upgrade.type == .CardDice_Veteran do upgrade.var1 = 0.
	}

	killer := killer
	if killer == nil && (victim.killed_by >= 0 && int(victim.killed_by) < len(game.dice)){
		killer = &game.dice[victim.killed_by]
	}
	if killer != nil{
		for &upgrade in killer.upgrades{
			if upgrade.type == .CardDice_WarHero do upgrade.var1 += 1
		}
	}

	if .CardRoll_Exorcism in player.roll.effects{
		add_text(victim.position, fmt.aprint("EXORCISED!"), victim.color, 2.0)
		return
	}

	if i32(len(player.ghosts)) >= player.ghosts_max do clear(&player.ghosts)
	append(&player.ghosts, victim.current_number)
	slice.sort(player.ghosts[:])
}

dice_fight :: proc(die1: ^Die, die2: ^Die) {
    game.battle.dice = {die1, die2}
    game.battle.previous_positions = {die1.position, die2.position}
    game.battle.state = .Fighting
    game.battle.timer = 0.
}

die_has_upgrade :: proc(die: Die, card_type: CardType) -> bool{
	for upgrade in die.upgrades{
		if upgrade.type == card_type do return true
	}
	return false
}
