package game

import "core:math"
import "core:math/linalg"
import "core:math/rand"

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

    // iitWorld[0,0] = t4*rotmat[0,0]+
    //     t9*rotmat[0,1]+
    //     t14*rotmat[0,2];
    // iitWorld[0,1] = t4*rotmat[1,0]+
    //     t9*rotmat[1,1]+
    //     t14*rotmat[1,2];
    // iitWorld[0,2] = t4*rotmat[2,0]+
    //     t9*rotmat[2,1]+
    //     t14*rotmat[2,2];
    // iitWorld.data[3] = t28*rotmat[0,0]+
    //     t33*rotmat[0,1]+
    //     t38*rotmat[0,2];
    // iitWorld.data[4] = t28*rotmat[1,0]+
    //     t33*rotmat[1,1]+
    //     t38*rotmat[1,2];
    // iitWorld.data[5] = t28*rotmat[2,0]+
    //     t33*rotmat[2,1]+
    //     t38*rotmat[2,2];
    // iitWorld.data[6] = t52*rotmat[0,0]+
    //     t57*rotmat[0,1]+
    //     t62*rotmat[0,2];
    // iitWorld.data[7] = t52*rotmat[1,0]+
    //     t57*rotmat[1,1]+
    //     t62*rotmat[1,2];
    // iitWorld.data[8] = t52*rotmat[2,0]+
    //     t57*rotmat[2,1]+
    //     t62*rotmat[2,2];
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

random_vector :: proc(min, max: f32) -> Vector3 {
	return Vector3{
		rand.float32_range(min, max),
		rand.float32_range(min, max),
		rand.float32_range(min, max),
	}
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
