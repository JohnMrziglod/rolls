package game

import "core:math"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

Particle :: struct {
	position: rl.Vector3,
	velocity: rl.Vector3,
	acceleration: rl.Vector3,
	damping: f32,
	inverse_mass: f32,
	force_accum: rl.Vector3,
}

update_physics :: proc(particles: []Particle, dt: f32) {
	for &p, i in particles {
		if p.inverse_mass == 0.0 {
			return // Infinite mass objects do not move
		}

		p.position += p.velocity * dt

		resulting_acceleration := p.acceleration
		resulting_acceleration += p.force_accum * p.inverse_mass
		p.velocity += resulting_acceleration * dt
		p.velocity *= math.pow(p.damping, dt)
	}
}
