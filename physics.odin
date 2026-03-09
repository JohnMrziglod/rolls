package game

import "core:math"
import "core:math/rand"

real :: f32
Vector3 :: [3]real

Particle :: struct {
	position: Vector3,
	velocity: Vector3,
	acceleration: Vector3,
	damping: real,
	inverse_mass: real,
	force_accum: Vector3,
}

Firework :: struct {
	using particle: Particle,
	type: u32,
	age: f32,
}

FireworkRule :: struct {
	type: u32,
	min_age: f32,
	max_age: f32,
	min_velocity: Vector3,
	max_velocity: Vector3,
	damping: real,
	payload: []FireworkPayload,
}

FireworkPayload :: struct{
	type: u32,
	count: u32,
}

random_vector :: proc(min, max: f32) -> Vector3 {
	return Vector3{
		rand.float32_range(min, max),
		rand.float32_range(min, max),
		rand.float32_range(min, max),
	}
}

make_particle :: proc(position: Vector3={0,0,0}) -> Particle {
	return Particle{
		position=position,
		velocity={0.0, 0.0, 0.0},
		acceleration={0.0, 0.0, 0.0},
		damping=0.99,
		inverse_mass=1.0,
		force_accum={0.0, 0.0, 0.0},
	}
}

update_physics :: proc(dt: f32) {
	for &p, i in particles {
		// INTEGRATE MOVEMENT:
		if p.inverse_mass == 0.0 {
			continue // Infinite mass objects do not move
		}

		p.force_accum = Vector3{0.0, -9.81, 0.0} // Clear the accumulated force

		p.position += p.velocity * dt

		resulting_acceleration := p.acceleration
		resulting_acceleration += p.force_accum * p.inverse_mass
		p.velocity += resulting_acceleration * dt
		p.velocity *= math.pow(p.damping, dt)

		// Age fireworks and apply rules:
		p.age -= dt

	}
}
