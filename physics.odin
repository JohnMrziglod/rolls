package game

import "core:math"
import "core:math/linalg"

SLEEP_EPSILON :: 0.1

RigidBody :: struct {
	inverse_mass: real,
	inverse_inertia_tensor: Matrix3,
	linear_damping: real,
	angular_damping: real,
	position: Vector3,
	orientation: Quaternion,
	velocity: Vector3,
	rotation: Vector3,

	// derived data (we use it as a cache to avoid recalculating it every frame):
	inverse_inertia_tensor_world: Matrix3,
	motion: real,
	is_awake: bool,
	can_sleep: bool,
	transform_matrix: Matrix4,

	// accumulated forces and torques:
	force_accum: Vector3,
	torque_accum: Vector3,
	acceleration: Vector3,
	last_frame_acceleration: Vector3,
}

check_inverse_inertia_tensor :: proc(iit: Matrix3) {
	// assert(iit[0, 0] != 0.0)
	// assert(iit[1, 1] != 0.0)
	// assert(iit[2, 2] != 0.0)
}

transform_inertia_tensor :: proc(
	iitWorld: ^Matrix3, q: Quaternion, iitBody: Matrix3, rotmat: Matrix4)
{
    t4 :real= rotmat[0,0]*iitBody[0,0]+
        rotmat[0,1]*iitBody[1,0]+
        rotmat[0,2]*iitBody[2,0];
    t9 :real= rotmat[0,0]*iitBody[0,1]+
        rotmat[0,1]*iitBody[1,1]+
        rotmat[0,2]*iitBody[2,1];
    t14 :real= rotmat[0,0]*iitBody[0,2]+
        rotmat[0,1]*iitBody[1,2]+
        rotmat[0,2]*iitBody[2,2];
    t28 :real= rotmat[1,0]*iitBody[0,0]+
        rotmat[1,1]*iitBody[1,0]+
        rotmat[1,2]*iitBody[2,0];
    t33 :real= rotmat[1,0]*iitBody[0,1]+
        rotmat[1,1]*iitBody[1,1]+
        rotmat[1,2]*iitBody[2,1];
    t38 :real= rotmat[1,0]*iitBody[0,2]+
        rotmat[1,1]*iitBody[1,2]+
        rotmat[1,2]*iitBody[2,2];
    t52 :real= rotmat[2,0]*iitBody[0,0]+
        rotmat[2,1]*iitBody[1,0]+
        rotmat[2,2]*iitBody[2,0];
    t57 :real= rotmat[2,0]*iitBody[0,1]+
        rotmat[2,1]*iitBody[1,1]+
        rotmat[2,2]*iitBody[2,1];
    t62 :real= rotmat[2,0]*iitBody[0,2]+
        rotmat[2,1]*iitBody[1,2]+
        rotmat[2,2]*iitBody[2,2];

    iitWorld ^= {
    	t4*rotmat[0,0]+ t9*rotmat[0,1]+ t14*rotmat[0,2],
		t4*rotmat[1,0]+ t9*rotmat[1,1]+ t14*rotmat[1,2],
		t4*rotmat[2,0]+ t9*rotmat[2,1]+ t14*rotmat[2,2],
		t28*rotmat[0,0]+ t33*rotmat[0,1]+ t38*rotmat[0,2],
		t28*rotmat[1,0]+ t33*rotmat[1,1]+ t38*rotmat[1,2],
		t28*rotmat[2,0]+ t33*rotmat[2,1]+ t38*rotmat[2,2],
		t52*rotmat[0,0]+ t57*rotmat[0,1]+ t62*rotmat[0,2],
		t52*rotmat[1,0]+ t57*rotmat[1,1]+ t62*rotmat[1,2],
		t52*rotmat[2,0]+ t57*rotmat[2,1]+ t62*rotmat[2,2],
	}
}

calculate_transform_matrix :: proc(position: Vector3, orientation: Quaternion) -> Matrix4 {
	// Convert the quaternion to a rotation matrix:
	rotmat := Matrix4{
		1 - 2*orientation.y*orientation.y - 2*orientation.z*orientation.z,
		2*orientation.x*orientation.y - 2*orientation.z*orientation.w,
		2*orientation.x*orientation.z + 2*orientation.y*orientation.w,
		position.x,

		2*orientation.x*orientation.y + 2*orientation.z*orientation.w,
		1 - 2*orientation.x*orientation.x - 2*orientation.z*orientation.z,
		2*orientation.y*orientation.z - 2*orientation.x*orientation.w,
		position.y,

		2*orientation.x*orientation.z - 2*orientation.y*orientation.w,
		2*orientation.y*orientation.z + 2*orientation.x*orientation.w,
		1 - 2*orientation.x*orientation.x - 2*orientation.y*orientation.y,
		position.z,
	}

	return rotmat
}

quaternion_add_vector :: proc(q: ^Quaternion, vector: Vector3) {
	nq :Quaternion= {0, vector.x, vector.y, vector.z}
	nq *= q^
	q.w += nq.w * 0.5
	q.x += nq.x * 0.5
	q.y += nq.y * 0.5
	q.z += nq.z * 0.5
}

body_calculate_derived_data :: proc(body: ^RigidBody) {
	body.orientation = linalg.quaternion_normalize(body.orientation)
	body.transform_matrix = calculate_transform_matrix(body.position, body.orientation)
	transform_inertia_tensor(&body.inverse_inertia_tensor_world, body.orientation, body.inverse_inertia_tensor, body.transform_matrix)
}

body_integrate :: proc(body: ^RigidBody, dt: f32) {
	if !body.is_awake do return

	// Calculate linear acceleration from force inputs.
	body.last_frame_acceleration = body.acceleration
	body.last_frame_acceleration += body.force_accum * body.inverse_mass

	// Calculate angular acceleration from torque inputs.
	angular_acceleration := body.inverse_inertia_tensor_world * body.torque_accum

	// Adjust velocities
	// Update linear velocity from both acceleration and impulse.
	body.velocity += body.last_frame_acceleration * dt

	// Update angular velocity from both acceleration and impulse.
	body.rotation += angular_acceleration * dt

	// Impose drag.
	body.velocity *= math.pow(body.linear_damping, dt)
	body.rotation *= math.pow(body.angular_damping, dt)

	// Adjust positions
	// Update linear position.
	body.position += body.velocity*dt

	// Update angular position.
	quaternion_add_vector(&body.orientation, body.rotation*dt)

	// Normalise the orientation, and update the matrices with the new
	// position and orientation
	body_calculate_derived_data(body)

	// Clear accumulators.
	body_clear_accumulators(body)

	// Update the kinetic energy store, and possibly put the body to
	// sleep.
	if body.can_sleep {
	    current_motion := linalg.dot(body.velocity, body.velocity) + linalg.dot(body.rotation, body.rotation)

	    bias := math.pow(0.5, dt);
	    body.motion = bias*body.motion + (1-bias)*current_motion;

	    if body.motion < SLEEP_EPSILON{
			body_set_awake(body, false)
		} else if body.motion > 10 * SLEEP_EPSILON {
			body.motion = 10 * SLEEP_EPSILON
		}
	}
}

body_set_mass :: proc(body: ^RigidBody, mass: real) {
	assert(mass != 0.0)
	body.inverse_mass = 1.0 / mass
}

body_get_mass :: proc(body: ^RigidBody) -> real {
	if body.inverse_mass == 0.0 {
		return REAL_MAX
	} else {
		return 1.0 / body.inverse_mass
	}
}

body_has_finite_mass :: proc(body: ^RigidBody) -> bool {
	return body.inverse_mass >= 0.0
}

body_set_inertia_tensor :: proc(body: ^RigidBody, inertia_tensor: Matrix3) {
	body.inverse_inertia_tensor = linalg.inverse(inertia_tensor)
	check_inverse_inertia_tensor(body.inverse_inertia_tensor)
}

body_get_inertia_tensor :: proc(body: ^RigidBody) -> Matrix3 {
	return linalg.inverse(body.inverse_inertia_tensor)
}

body_get_inertia_tensor_world :: proc(body: ^RigidBody) -> Matrix3 {
	return linalg.inverse(body.inverse_inertia_tensor_world)
}

body_set_orientation :: proc(body: ^RigidBody, orientation: Quaternion) {
	body.orientation = linalg.quaternion_normalize(orientation)
}

body_get_rot_matrix :: proc(body: ^RigidBody) -> Matrix3 {
	return only_rot(body.transform_matrix)
}

body_get_gl_transform :: proc(body: ^RigidBody) -> [16]f32 {
	m := body.transform_matrix
	return [16]f32{
		m[0, 0], m[1, 0], m[2, 0], 0,
		m[0, 1], m[1, 1], m[2, 1], 0,
		m[0, 2], m[1, 2], m[2, 2], 0,
		m[0, 3], m[1, 3], m[2, 3], 1,
	}
}

body_get_point_in_local_space :: proc(body: ^RigidBody, world_point: Vector3) -> Vector3 {
	return linalg.transpose(only_rot(body.transform_matrix)) * (world_point - body.position)
}

body_get_point_in_world_space :: proc(body: ^RigidBody, local_point: Vector3) -> Vector3 {
	return body.transform_matrix * homogenous(local_point)
}
body_get_direction_in_local_space :: proc(body: ^RigidBody, world_direction: Vector3) -> Vector3 {
	return linalg.transpose(only_rot(body.transform_matrix)) * world_direction
}

body_get_direction_in_world_space :: proc(body: ^RigidBody, local_direction: Vector3) -> Vector3 {
	return only_rot(body.transform_matrix) * local_direction
}

body_set_awake :: proc(body: ^RigidBody, awake: bool = true){
	if awake {
		body.is_awake = true

		// add a bit of motion to avoid it falling asleep immediately
		body.motion = SLEEP_EPSILON * 2.
	} else {
		body.is_awake = false
		body.velocity = {}
		body.rotation = {}
	}
}

body_set_can_sleep :: proc (body: ^RigidBody, can_sleep: bool = true){
	body.can_sleep = can_sleep
	if !can_sleep && !body.is_awake do body_set_awake(body)
}

body_clear_accumulators :: proc(body: ^RigidBody) {
	body.force_accum = {}
	body.torque_accum = {}
}

body_add_force :: proc (body: ^RigidBody, force: Vector3){
	body.force_accum += force
	body.is_awake = true
}

body_add_force_at_body_point :: proc (body: ^RigidBody, force: Vector3, point: Vector3){
	// convert to world coordinates
	world_point := body_get_point_in_world_space(body, point)
	body_add_force_at_point(body, force, world_point)
}

body_add_force_at_point :: proc (body: ^RigidBody, force: Vector3, point: Vector3){
	body.force_accum += force
	relative_point := point - body.position
	body.torque_accum += linalg.cross(relative_point, force)
	body.is_awake = true
}

body_add_torque :: proc (body: ^RigidBody, torque: Vector3){
	body.torque_accum += torque
	body.is_awake = true
}

Contact :: struct {
	body: [2]^RigidBody,
	friction: real,
	restitution: real,
	contact_point: Vector3,
	contact_normal: Vector3,
	contact_velocity: Vector3,
	contact_to_world: Matrix3,
	penetration: real,
	desired_delta_velocity: real,
	relative_contact_position: [2]Vector3,
}

contact_set_body_data :: proc(contact: ^Contact, one, two: ^RigidBody, friction, restitution: real) {
	contact.body[0] = one
	contact.body[1] = two
	contact.friction = friction
	contact.restitution = restitution
}

contact_match_awake_state :: proc(contact: ^Contact) {
	// Collisions with the world never cause a body to wake up.
	if contact.body[1] == nil do return

	awake_0 := contact.body[0].is_awake
	awake_1 := contact.body[1].is_awake

	if awake_0 ~ awake_1 {
		if awake_0 do body_set_awake(contact.body[1])
		else do body_set_awake(contact.body[0])
	}
}

contact_swap_bodies :: proc(contact: ^Contact) {
	contact.contact_normal *= -1
	contact.body[0], contact.body[1] = contact.body[1], contact.body[0]
}

contact_calculate_contact_basis :: proc(contact: ^Contact) {
	contact.contact_to_world[0] = contact.contact_normal

	if math.abs(contact.contact_normal.x) > math.abs(contact.contact_normal.y) {
		s := 1.0 / math.sqrt(contact.contact_normal.z*contact.contact_normal.z + contact.contact_normal.x*contact.contact_normal.x)

		contact.contact_to_world[1] = Vector3{contact.contact_normal.z * s, 0, -contact.contact_normal.x * s}
	} else {
		s := 1.0 / math.sqrt(contact.contact_normal.z*contact.contact_normal.z + contact.contact_normal.y*contact.contact_normal.y)

		contact.contact_to_world[1] = Vector3{0, -contact.contact_normal.z * s, contact.contact_normal.y * s}
	}

	contact.contact_to_world[2] = linalg.cross(contact.contact_normal, contact.contact_to_world[1])
}

contact_calculate_local_velocity :: proc(contact: ^Contact, body_index: u32, duration: real) -> Vector3 {
	body := contact.body[body_index]

	// Velocity of the contact point
	velocity := body.velocity + linalg.cross(body.rotation, contact.relative_contact_position[body_index])

	// Into contact coordinates
	contact_velocity := linalg.transpose(contact.contact_to_world) * velocity

	// velocity due to forces without reactions
	acceleration_velocity := body.last_frame_acceleration * duration
	acceleration_velocity = linalg.transpose(contact.contact_to_world) * acceleration_velocity

	// we ignore any component of acceleration in the contact normal direction, we are only interested in planar acceleration
	acceleration_velocity.x = 0

	contact_velocity += acceleration_velocity

	return contact_velocity
}

contact_calculate_desired_delta_velocity :: proc(contact: ^Contact, duration: real) {
	velocity_from_acceleration := 0.0
	if contact.body[0].is_awake {
		velocity_from_acceleration += contact.body[0].last_frame_acceleration * duration * contact.contact_normal;
	}

	body2 := contact.body[1]
	if body2 != nil && body2.is_awake {
		velocity_from_acceleration -= body2.last_frame_acceleration * duration * contact.contact_normal
	}

	// @TODO: Why? To prevent jittering?
	velocity_limit := 0.25
	restitution := contact.restitution
	if math.abs(contact.contact_velocity.x) < velocity_limit {
		restitution = 0.
	}

	contact.desired_delta_velocity = (
		-contact.contact_velocity.x - restitution*(contact.contact_velocity-velocity_from_acceleration)
	);
}

contact_calculate_internals ::proc(contact: ^Contact, duration: real){
	if contact.body[0] == nil do contact_swap_bodies(contact)
	assert(contact.body[0] != nil)

	contact_calculate_contact_basis(contact)

	contact.relative_contact_position[0] = contact.contact_point - contact.body[0].position
	if contact.body[1] != nil {
		contact.relative_contact_position[1] = contact.contact_point - contact.body[1].position
	}

	contact.contact_velocity = contact_calculate_local_velocity(contact, 0, duration)
	if contact.body[1] != nil {
		contact.contact_velocity -= contact_calculate_local_velocity(contact, 1, duration)
	}

	contact_calculate_desired_delta_velocity(contact, duration)
}

contact_apply_velocity_change :: proc(contact: ^Contact, velocity_change, rotation_change: [2]Vector3) {
	body1 := contact.body[0]
	body2 := contact.body[1]

	inverse_inertia_tensors := [2]Matrix3{
		body1.inverse_inertia_tensor_world,
		(body2 != nil) ? body2.inverse_inertia_tensor_world : Matrix3{},
	}

	impulse_contact : Vector3
	if contact.friction == 0.0 {
		impulse_contact = calculate_frictionless_impulse(contact, inverse_inertia_tensors)
	} else {
		impulse_contact = calculate_friction_impulse(contact, inverse_inertia_tensors)
	}

	impulse := contact.contact_to_world * impulse_contact

	for i in 0..<=2 {
		if body[i] == nil do continue

		impulsive_torque := linalg.cross(contact.relative_contact_position[i], impulse)

		rotation_change[i] = inverse_inertia_tensors[i] * impulsive_torque
		velocity_change[i] = impulse * body1.inverse_mass

		body[i].velocity += velocity_change[i]
		body[i].rotation += rotation_change[i]
	}
}

contact_calculate_frictionless_impulse :: proc(contact: ^Contact, inverse_inertia_tensors: [2]Matrix3) -> Vector3 {
	// Calculate the impulse for each contact axis

	// Calculate the change in velocity per unit impulse for each contact axis
	delta_vel_world := linalg.cross(contact.relative_contact_position[0], contact.contact_normal)
	delta_vel_world = inverse_inertia_tensors[0] * delta_vel_world
	delta_vel_world = linalg.cross(delta_vel_world, contact.relative_contact_position[0])

	delta_velocity := delta_vel_world * contact.contact_normal + contact.body[0].inverse_mass

	if contact.body[1] != nil {
		delta_vel_world = linalg.cross(contact.relative_contact_position[1], contact.contact_normal)
		delta_vel_world = inverse_inertia_tensors[1] * delta_vel_world
		delta_vel_world = linalg.cross(delta_vel_world, contact.relative_contact_position[1])

		delta_velocity += delta_vel_world.x + contact.body[1].inverse_mass
	}

	assert(delta_velocity != 0.0)

	impulse_contact := Vector3{contact.desired_delta_velocity, 0, 0}
	return impulse_contact / delta_velocity
}

calculate_friction_impulse :: proc(contact: ^Contact, inverse_inertia_tensors: [2]Matrix3) -> Vector3 {
	
}

ContactResolver :: struct {
	position_iterations: u32,
	velocity_iterations: u32,
	velocity_epsilon: real,
	position_epsilon: real,
	position_iterations_used: u32,
	velocity_iterations_used: u32,
	valid_settings: bool,
}

// make_particle :: proc(position: Vector3={0,0,0}) -> Particle {
// 	return Particle{
// 		position=position,
// 		velocity={0.0, 0.0, 0.0},
// 		acceleration={0.0, 0.0, 0.0},
// 		damping=0.99,
// 		inverse_mass=1.0,
// 		force_accum={0.0, 0.0, 0.0},
// 	}
// }

// update_physics :: proc(dt: f32) {
// 	for &p, i in particles {
// 		// INTEGRATE MOVEMENT:
// 		if p.inverse_mass == 0.0 {
// 			continue // Infinite mass objects do not move
// 		}

// 		p.force_accum = Vector3{0.0, -9.81, 0.0} // Clear the accumulated force

// 		p.position += p.velocity * dt

// 		resulting_acceleration := p.acceleration
// 		resulting_acceleration += p.force_accum * p.inverse_mass
// 		p.velocity += resulting_acceleration * dt
// 		p.velocity *= math.pow(p.damping, dt)

// 		// Age fireworks and apply rules:
// 		p.age -= dt

// 	}
// }
