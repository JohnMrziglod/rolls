package game

import "core:math"
import "core:math/linalg"
import "core:fmt"

SLEEP_EPSILON :: real(0.1)
VELOCITY_EPSILON :: real(0.01)
POSITION_EPSILON :: real(0.01)
FRICTION :: real(0.95)
RESITUTION :: real(0.4)
TOLERANCE :: real(0.1)

ShapeBox :: struct {half_size: real,}
Shape :: union {ShapeBox,}

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

	// Are we a box, a sphere, or something else? This is used for collision detection.
	shape: Shape
}

// We use this to limit the throwing area
Plane :: struct {
	direction: Vector3,
	offset: real,
}

check_inverse_inertia_tensor :: proc(iit: Matrix3) {
	assert(iit[0, 0] != 0.0)
	assert(iit[1, 1] != 0.0)
	assert(iit[2, 2] != 0.0)
}

/**
 * Sets the value of the matrix from inertia tensor values.
 */
// void setInertiaTensorCoeffs(real ix, real iy, real iz,
//     real ixy=0, real ixz=0, real iyz=0)
// {
//     data[0] = ix;
//     data[1] = data[3] = -ixy;
//     data[2] = data[6] = -ixz;
//     data[4] = iy;
//     data[5] = data[7] = -iyz;
//     data[8] = iz;
// }

// /**
//  * Sets the value of the matrix as an inertia tensor of
//  * a rectangular block aligned with the body's coordinate
//  * system with the given axis half-sizes and mass.
//  */
// void setBlockInertiaTensor(const Vector3 &halfSizes, real mass)
// {
//     Vector3 squares = halfSizes.componentProduct(halfSizes);
//     setInertiaTensorCoeffs(0.3f*mass*(squares.y + squares.z),
//         0.3f*mass*(squares.x + squares.z),
//         0.3f*mass*(squares.x + squares.y));
// }

body_set_block_inertia_tensor :: proc(body: ^RigidBody, half_size: real, mass: real) {
	squares := Vector3{half_size*half_size, half_size*half_size, half_size*half_size}
	body_set_inertia_tensor(body, Matrix3{
		0.3*mass*(squares.y + squares.z), 0, 0,
		0, 0.3*mass*(squares.x + squares.z), 0,
		0, 0, 0.3*mass*(squares.x + squares.y),
	})
}

body_update_inertia_tensor :: proc(body: ^RigidBody){
    transform_inertia_tensor(&body.inverse_inertia_tensor_world, body.orientation, body.inverse_inertia_tensor, body.transform_matrix)
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

body_calculate_derived_data :: proc(body: ^RigidBody) {
	body.orientation = linalg.quaternion_normalize(body.orientation)
	body.transform_matrix = calculate_transform_matrix(body.position, body.orientation)
	body_update_inertia_tensor(body)
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
		} else if body.motion > 10. * SLEEP_EPSILON {
			body.motion = 10. * SLEEP_EPSILON
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

body_get_gl_transform :: proc(body: RigidBody) -> [16]f32 {
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

body_get_axis :: proc(body: RigidBody, index: i32) -> Vector3 {
	return matrix_axis_vector(body.transform_matrix, index)
}

box_transform_to_axis :: proc(body: RigidBody, axis: Vector3) -> real{
	box := body.shape.(ShapeBox) // we assume the body is a box, we should probably check this

    return (
        box.half_size * math.abs(linalg.dot(axis, body_get_axis(body, 0))) +
        box.half_size * math.abs(linalg.dot(axis, body_get_axis(body, 1))) +
        box.half_size * math.abs(linalg.dot(axis, body_get_axis(body, 2)))
    )
}

collision_detect_box_plane :: proc(body: ^RigidBody, plane: Plane, contacts: ^[dynamic]Contact) -> bool{
	projected_radius := box_transform_to_axis(body^, plane.direction)
	box_distance := linalg.dot(plane.direction, body_get_axis(body^, 3)) - projected_radius

	if box_distance > plane.offset {
		return false
	}

	// We have an intersection, so find the intersection points. We can make
    // do with only checking vertices. If the box is resting on a plane
    // or on an edge, it will be reported as four or two contact points.
    // static real mults[8][3] = {{1,1,1},{-1,1,1},{1,-1,1},{-1,-1,1},
                                  // {1,1,-1},{-1,1,-1},{1,-1,-1},{-1,-1,-1}};

    mults := []Vector3{
    	{1, 1, 1},
		{-1, 1, 1},
		{1, -1, 1},
		{-1, -1, 1},
		{1, 1, -1},
		{-1, 1, -1},
		{1, -1, -1},
		{-1, -1, -1},
    }

    for i in 0..=7 {
		vertex_pos := Vector3(body.transform_matrix * homogenous(mults[i] * body.shape.(ShapeBox).half_size))

		vertex_distance := linalg.dot(plane.direction, vertex_pos) - plane.offset
		if vertex_distance <= 0 {
			contact := Contact{
				point= vertex_pos - plane.direction * vertex_distance * 0.5,
				normal= plane.direction,
				penetration= -vertex_distance,
			}
			contact_set_body_data(&contact, body, nil, FRICTION, RESITUTION)
			append(contacts, contact)
		}
	}

	return true
}

collision_check_axis :: proc(one, two: RigidBody, axis, to_centre: Vector3, index: i32,
								smallest_penetration: ^real, smalled_case: ^i32) -> bool {
	if linalg.length2(axis) < 0.0001 do return true

	axis := linalg.normalize(axis)

	// penetration of the axis:
	one_project := box_transform_to_axis(one, axis)
	two_project := box_transform_to_axis(two, axis)
	distance := math.abs(linalg.dot(to_centre, axis))
	penetration :=	one_project + two_project - distance

	if penetration < 0 do return false
	if penetration < smallest_penetration^ {
		smallest_penetration ^= penetration
		smalled_case ^= index
	}

	return true
}

cross_axes :: proc(one, two: RigidBody, axis_one, axis_two: i32) -> Vector3{
	return linalg.cross(body_get_axis(one, axis_one), body_get_axis(two, axis_two))
}

fill_point_face_box_box :: proc(one, two: ^RigidBody, to_centre: Vector3, contacts: ^[dynamic]Contact, best: i32, pen: real) {
	// we know which axis is the best, we can use this to determine which
	// of the faces we are colliding with. We also know that the axis is
	// perpendicular to the face, so we can use this information to determine
	// which of the vertices we are colliding with.
	face_normal := body_get_axis(one^, best)
	if linalg.dot(face_normal, to_centre) > 0 {
		face_normal *= -1.0
	}

	// Vector3 vertex = two.halfSize;
	 //    if (two.getAxis(0) * normal < 0) vertex.x = -vertex.x;
	 //    if (two.getAxis(1) * normal < 0) vertex.y = -vertex.y;
	 //    if (two.getAxis(2) * normal < 0) vertex.z = -vertex.z;
	half_size := two.shape.(ShapeBox).half_size
	vertex := Vector3{half_size, half_size, half_size}
	if linalg.dot(body_get_axis(two^, 0), face_normal) < 0 do vertex.x *= -1
	if linalg.dot(body_get_axis(two^, 1), face_normal) < 0 do vertex.y *= -1
	if linalg.dot(body_get_axis(two^, 2), face_normal) < 0 do vertex.z *= -1

	contact := Contact{
		normal= face_normal,
		penetration= pen,
		point= body_get_point_in_world_space(two, vertex),
	}
	contact_set_body_data(&contact, one, two, FRICTION, RESITUTION)
	append(contacts, contact)
}

collision_detect_box_box :: proc(one, two: ^RigidBody, contacts: ^[dynamic]Contact) -> bool{
	to_centre := body_get_axis(two^, 3) - body_get_axis(one^, 3)

	// we start assuming there is no contact:
	pen := REAL_MAX
	// Use -1 as a sentinel value meaning "unchanged / no axis recorded".
	// This lets us detect the degenerate case where none of the checks
	// updated `best` and avoid an assert/crash.
	best := i32(-1)

	if !collision_check_axis(one^, two^, body_get_axis(one^, 0), to_centre, 0, &pen, &best) do return false
	if !collision_check_axis(one^, two^, body_get_axis(one^, 1), to_centre, 1, &pen, &best) do return false
	if !collision_check_axis(one^, two^, body_get_axis(one^, 2), to_centre, 2, &pen, &best) do return false

	if !collision_check_axis(one^, two^, body_get_axis(two^, 0), to_centre, 3, &pen, &best) do return false
	if !collision_check_axis(one^, two^, body_get_axis(two^, 1), to_centre, 4, &pen, &best) do return false
	if !collision_check_axis(one^, two^, body_get_axis(two^, 2), to_centre, 5, &pen, &best) do return false

	// store the best axis major, in case we run into almost parallel edge collisions later:
	best_single_axis := best

	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 0, 0), to_centre, 6, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 0, 1), to_centre, 7, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 0, 2), to_centre, 8, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 1, 0), to_centre, 9, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 1, 1), to_centre, 10, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 1, 2), to_centre, 11, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 2, 0), to_centre, 12, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 2, 1), to_centre, 13, &pen, &best) do return false
	if !collision_check_axis(one^, two^, cross_axes(one^, two^, 2, 2), to_centre, 14, &pen, &best) do return false

	// make sure we got a result. If `best` is still the sentinel value it means
	// no axis was recorded (degenerate case). Treat this as "no collision"
	// rather than asserting and crashing.
	if best == i32(-1) do return false

	// We now know there's a collision, and we know which
    // of the axes gave the smallest penetration. We now
    // can deal with it in different ways depending on
    // the case.
    if best < 3 {
        // We've got a vertex of box two on a face of box one.
        fill_point_face_box_box(one, two, to_centre, contacts, best, pen)
        return true
    } else if best < 6{
        // We've got a vertex of box one on a face of box two.
        // We use the same algorithm as above, but swap around
        // one and two (and therefore also the vector between their
        // centres).
        fill_point_face_box_box(two, one, to_centre*-1.0, contacts, best-3, pen)
        return true
    } else {
   		// we got  an edge-edge contact. Find out which axes:
		best -= 6
		one_axis_index := best / 3
		two_axis_index := best % 3
		one_axis := body_get_axis(one^, one_axis_index)
		two_axis := body_get_axis(two^, two_axis_index)
		axis := linalg.cross(one_axis, two_axis)
		axis = linalg.normalize(axis)

		// the axis should point from box one to box two:
		if linalg.dot(axis, to_centre) > 0 do axis *= -1.0

		// we have the axes, but not the edges: each axis has 4 edges parallel
		// to it, we need to find which of the 4 for each object. We do
		// that by finding the point in the centre of the edge. We know
		// its component in the direction of the box's collision axis is zero
		// (its a mid-point) and we determine which of the extremes in each
		// of the other axes is closest.
		one_half_size := one.shape.(ShapeBox).half_size
		two_half_size := two.shape.(ShapeBox).half_size
		pt_on_one_edge := Vector3{one_half_size, one_half_size, one_half_size}
		pt_on_two_edge := Vector3{two_half_size, two_half_size, two_half_size}
		for i in 0..=2 {
			if i32(i) == one_axis_index do pt_on_one_edge[i] = 0
			else if linalg.dot(body_get_axis(one^, i32(i)), axis) > 0 do pt_on_one_edge[i] *= -1

			if i32(i) == two_axis_index do pt_on_two_edge[i] = 0
			else if linalg.dot(body_get_axis(two^, i32(i)), axis) < 0 do pt_on_two_edge[i] *= -1
		}

		// move them into world coordinates (they are already oriented
		// correctly, since they have been derived from the axes):
		pt_on_one_edge = body_get_point_in_world_space(one, pt_on_one_edge)
		pt_on_two_edge = body_get_point_in_world_space(two, pt_on_two_edge)

		// so we have a point and a direction for the colliding edges.
		// we need to find out point of closest approach of the two
		// line-segments:
		vertex := collision_contact_point(
			pt_on_one_edge, one_axis, one_half_size,
			pt_on_two_edge, two_axis, two_half_size,
			best_single_axis > 2
		)

		contact := Contact{
			point= vertex,
			normal= axis,
			penetration= pen,
		}
		contact_set_body_data(&contact, one, two, FRICTION, RESITUTION)

		return true
    }

    return false
}

collision_contact_point :: proc(p_one, d_one: Vector3, one_size: real, p_two, d_two: Vector3, two_size: real, use_one: bool) -> Vector3{
	sm_one := linalg.length2(d_one)
	sm_two := linalg.length2(d_two)
	dp_one_two := linalg.dot(d_two, d_one)

	to_st := p_one - p_two
	dp_stat_one := linalg.dot(d_one, to_st)
	dp_stat_two := linalg.dot(d_two, to_st)

	denom := sm_one*sm_two - dp_one_two*dp_one_two

	if math.abs(denom) < 0.0001 do return use_one ? p_one : p_two

	mua := (dp_one_two * dp_stat_two - sm_two * dp_stat_one) / denom
	mub := (sm_one * dp_stat_two - dp_one_two * dp_stat_one) / denom

	// If either of the edges has the nearest point out
    // of bounds, then the edges aren't crossed, we have
    // an edge-face contact. Our point is on the edge, which
    // we know from the useOne parameter.
    if mua > one_size || mua < -one_size || mub > two_size || mub < -two_size {
		return use_one ? p_one : p_two
	} else {
		c_one := p_one + d_one * mua
		c_two := p_two + d_two * mub
		return (c_one + c_two) * 0.5
	}
    // if (mua > oneSize ||
    //     mua < -oneSize ||
    //     mub > twoSize ||
    //     mub < -twoSize)
    // {
    //     return useOne?pOne:pTwo;
    // }
    // else
    // {
    //     cOne = pOne + dOne * mua;
    //     cTwo = pTwo + dTwo * mub;

    //     return cOne * 0.5 + cTwo * 0.5;
    // }

}

// This preprocessor definition is only used as a convenience
// in the boxAndBox contact generation method.
// #define CHECK_OVERLAP(axis, index) \
//     if (!tryAxis(one, two, (axis), toCentre, (index), pen, best)) return 0;

// unsigned CollisionDetector::boxAndBox(
//     const CollisionBox &one,
//     const CollisionBox &two,
//     CollisionData *data
//     )
// {
//     //if (!IntersectionTests::boxAndBox(one, two)) return 0;

//     // Find the vector between the two centres
//     Vector3 toCentre = two.getAxis(3) - one.getAxis(3);

//     // We start assuming there is no contact
//     real pen = REAL_MAX;
//     unsigned best = 0xffffff;

//     // Now we check each axes, returning if it gives us
//     // a separating axis, and keeping track of the axis with
//     // the smallest penetration otherwise.
//     CHECK_OVERLAP(one.getAxis(0), 0);
//     CHECK_OVERLAP(one.getAxis(1), 1);
//     CHECK_OVERLAP(one.getAxis(2), 2);

//     CHECK_OVERLAP(two.getAxis(0), 3);
//     CHECK_OVERLAP(two.getAxis(1), 4);
//     CHECK_OVERLAP(two.getAxis(2), 5);

//     // Store the best axis-major, in case we run into almost
//     // parallel edge collisions later
//     unsigned bestSingleAxis = best;

//     CHECK_OVERLAP(one.getAxis(0) % two.getAxis(0), 6);
//     CHECK_OVERLAP(one.getAxis(0) % two.getAxis(1), 7);
//     CHECK_OVERLAP(one.getAxis(0) % two.getAxis(2), 8);
//     CHECK_OVERLAP(one.getAxis(1) % two.getAxis(0), 9);
//     CHECK_OVERLAP(one.getAxis(1) % two.getAxis(1), 10);
//     CHECK_OVERLAP(one.getAxis(1) % two.getAxis(2), 11);
//     CHECK_OVERLAP(one.getAxis(2) % two.getAxis(0), 12);
//     CHECK_OVERLAP(one.getAxis(2) % two.getAxis(1), 13);
//     CHECK_OVERLAP(one.getAxis(2) % two.getAxis(2), 14);

//     // Make sure we've got a result.
//     assert(best != 0xffffff);

//     // We now know there's a collision, and we know which
//     // of the axes gave the smallest penetration. We now
//     // can deal with it in different ways depending on
//     // the case.
//     if (best < 3)
//     {
//         // We've got a vertex of box two on a face of box one.
//         fillPointFaceBoxBox(one, two, toCentre, data, best, pen);
//         data->addContacts(1);
//         return 1;
//     }
//     else if (best < 6)
//     {
//         // We've got a vertex of box one on a face of box two.
//         // We use the same algorithm as above, but swap around
//         // one and two (and therefore also the vector between their
//         // centres).
//         fillPointFaceBoxBox(two, one, toCentre*-1.0f, data, best-3, pen);
//         data->addContacts(1);
//         return 1;
//     }
//     else
//     {
//         // We've got an edge-edge contact. Find out which axes
//         best -= 6;
//         unsigned oneAxisIndex = best / 3;
//         unsigned twoAxisIndex = best % 3;
//         Vector3 oneAxis = one.getAxis(oneAxisIndex);
//         Vector3 twoAxis = two.getAxis(twoAxisIndex);
//         Vector3 axis = oneAxis % twoAxis;
//         axis.normalise();

//         // The axis should point from box one to box two.
//         if (axis * toCentre > 0) axis = axis * -1.0f;

//         // We have the axes, but not the edges: each axis has 4 edges parallel
//         // to it, we need to find which of the 4 for each object. We do
//         // that by finding the point in the centre of the edge. We know
//         // its component in the direction of the box's collision axis is zero
//         // (its a mid-point) and we determine which of the extremes in each
//         // of the other axes is closest.
//         Vector3 ptOnOneEdge = one.halfSize;
//         Vector3 ptOnTwoEdge = two.halfSize;
//         for (unsigned i = 0; i < 3; i++)
//         {
//             if (i == oneAxisIndex) ptOnOneEdge[i] = 0;
//             else if (one.getAxis(i) * axis > 0) ptOnOneEdge[i] = -ptOnOneEdge[i];

//             if (i == twoAxisIndex) ptOnTwoEdge[i] = 0;
//             else if (two.getAxis(i) * axis < 0) ptOnTwoEdge[i] = -ptOnTwoEdge[i];
//         }

//         // Move them into world coordinates (they are already oriented
//         // correctly, since they have been derived from the axes).
//         ptOnOneEdge = one.transform * ptOnOneEdge;
//         ptOnTwoEdge = two.transform * ptOnTwoEdge;

//         // So we have a point and a direction for the colliding edges.
//         // We need to find out point of closest approach of the two
//         // line-segments.
//         Vector3 vertex = contactPoint(
//             ptOnOneEdge, oneAxis, one.halfSize[oneAxisIndex],
//             ptOnTwoEdge, twoAxis, two.halfSize[twoAxisIndex],
//             bestSingleAxis > 2
//             );

//         // We can fill the contact.
//         Contact* contact = data->contacts;

//         contact->penetration = pen;
//         contact->contactNormal = axis;
//         contact->contactPoint = vertex;
//         contact->setBodyData(one.body, two.body,
//             data->friction, data->restitution);
//         data->addContacts(1);
//         return 1;
//     }
//     return 0;
// }
// #undef CHECK_OVERLAP

Contact :: struct {
	body: [2]^RigidBody,
	friction: real,
	restitution: real,
	point: Vector3,
	normal: Vector3,
	velocity: Vector3,
	to_world: Matrix3,
	penetration: real,
	desired_delta_velocity: real,
	relative_position: [2]Vector3,
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
	contact.normal *= -1
	contact.body[0], contact.body[1] = contact.body[1], contact.body[0]
}

contact_calculate_contact_basis :: proc(contact: ^Contact) {
	contact.to_world[0] = contact.normal

	if math.abs(contact.normal.x) > math.abs(contact.normal.y) {
		s := 1.0 / math.sqrt(contact.normal.z*contact.normal.z + contact.normal.x*contact.normal.x)

		contact.to_world[1] = Vector3{contact.normal.z * s, 0, -contact.normal.x * s}
		contact.to_world[2] = Vector3{
			contact.normal.y * contact.to_world[1].x,
			contact.normal.z * contact.to_world[1].x - contact.normal.x * contact.to_world[1].z,
			-contact.normal.y * contact.to_world[1].x}
	} else {
		s := 1.0 / math.sqrt(contact.normal.z*contact.normal.z + contact.normal.y*contact.normal.y)

		contact.to_world[1] = Vector3{0, -contact.normal.z * s, contact.normal.y * s}
		contact.to_world[2] = Vector3{
			contact.normal.y * contact.to_world[1].z - contact.normal.z * contact.to_world[1].y,
			-contact.normal.x * contact.to_world[1].z,
			contact.normal.x * contact.to_world[1].y,
		}
	}
}

contact_calculate_local_velocity :: proc(contact: ^Contact, body_index: i32, duration: real) -> Vector3 {
	body := contact.body[body_index]

	// Velocity of the contact point
	velocity := body.velocity + linalg.cross(body.rotation, contact.relative_position[body_index])

	// Into contact coordinates
	contact_velocity := linalg.transpose(contact.to_world) * velocity

	// velocity due to forces without reactions
	acceleration_velocity := body.last_frame_acceleration * duration
	acceleration_velocity = linalg.transpose(contact.to_world) * acceleration_velocity

	// we ignore any component of acceleration in the contact normal direction, we are only interested in planar acceleration
	acceleration_velocity.x = 0

	contact_velocity += acceleration_velocity

	return contact_velocity
}

contact_calculate_desired_delta_velocity :: proc(contact: ^Contact, duration: real) {
	velocity_from_acceleration := real(0.0)
	body1 := contact.body[0]
	if body1.is_awake {
		velocity_from_acceleration += linalg.dot(duration * body1.last_frame_acceleration, contact.normal)
	}

	body2 := contact.body[1]
	if body2 != nil && body2.is_awake {
		velocity_from_acceleration -= linalg.dot(duration * body2.last_frame_acceleration, contact.normal)
	}

	// @TODO: Why? To prevent jittering?
	velocity_limit := real(0.25)
	restitution := contact.restitution
	if math.abs(contact.velocity.x) < velocity_limit {
		restitution = 0.
	}

	contact.desired_delta_velocity = (
		-contact.velocity.x - restitution*(contact.velocity.x-velocity_from_acceleration)
	);
}

contact_calculate_internals ::proc(contact: ^Contact, duration: real){
	if contact.body[0] == nil do contact_swap_bodies(contact)
	assert(contact.body[0] != nil)

	contact_calculate_contact_basis(contact)

	contact.relative_position[0] = contact.point - contact.body[0].position
	if contact.body[1] != nil {
		contact.relative_position[1] = contact.point - contact.body[1].position
	}

	contact.velocity = contact_calculate_local_velocity(contact, 0, duration)
	if contact.body[1] != nil {
		contact.velocity -= contact_calculate_local_velocity(contact, 1, duration)
	}

	contact_calculate_desired_delta_velocity(contact, duration)
}

contact_apply_velocity_change :: proc(contact: ^Contact, velocity_change, rotation_change: ^[2]Vector3) {
	body1 := contact.body[0]
	body2 := contact.body[1]

	inverse_inertia_tensors := [2]Matrix3{
		body1.inverse_inertia_tensor_world,
		(body2 != nil) ? body2.inverse_inertia_tensor_world : Matrix3{},
	}

	impulse_contact : Vector3
	if contact.friction == real(0.0) {
		impulse_contact = contact_calculate_frictionless_impulse(contact, inverse_inertia_tensors)
	} else {
		impulse_contact = contact_calculate_friction_impulse(contact, inverse_inertia_tensors)
	}

	impulse := contact.to_world * impulse_contact

	impulsive_torque := linalg.cross(contact.relative_position[0], impulse)

	rotation_change[0] = inverse_inertia_tensors[0] * impulsive_torque
	velocity_change[0] = impulse * body1.inverse_mass

	contact.body[0].velocity += velocity_change[0]
	contact.body[0].rotation += rotation_change[0]

	if contact.body[1] != nil {
		impulsive_torque = linalg.cross(impulse, contact.relative_position[1])
		rotation_change[1] = inverse_inertia_tensors[1] * impulsive_torque
		velocity_change[1] = impulse * -contact.body[1].inverse_mass

		contact.body[1].velocity += velocity_change[1]
		contact.body[1].rotation += rotation_change[1]
	}
}

contact_calculate_frictionless_impulse :: proc(contact: ^Contact, inverse_inertia_tensors: [2]Matrix3) -> Vector3 {
	// Calculate the impulse for each contact axis

	// Calculate the change in velocity per unit impulse for each contact axis
	delta_vel_world := linalg.cross(contact.relative_position[0], contact.normal)
	delta_vel_world = inverse_inertia_tensors[0] * delta_vel_world
	delta_vel_world = linalg.cross(delta_vel_world, contact.relative_position[0])

	delta_velocity := delta_vel_world * contact.normal + contact.body[0].inverse_mass

	if contact.body[1] != nil {
		delta_vel_world = linalg.cross(contact.relative_position[1], contact.normal)
		delta_vel_world = inverse_inertia_tensors[1] * delta_vel_world
		delta_vel_world = linalg.cross(delta_vel_world, contact.relative_position[1])

		delta_velocity += delta_vel_world.x + contact.body[1].inverse_mass
	}

	assert(delta_velocity != 0.0)

	impulse_contact := Vector3{contact.desired_delta_velocity, 0, 0}
	return impulse_contact / delta_velocity
}

contact_calculate_friction_impulse :: proc(contact: ^Contact, inverse_inertia_tensors: [2]Matrix3) -> Vector3 {
	inverse_mass := contact.body[0].inverse_mass

    crp := contact.relative_position
    impulse_to_torque := Matrix3{
    	0, -crp[0].z, crp[0].y,
      	crp[0].z, 0, -crp[0].x,
        -crp[0].y, crp[0].x, 0,
    }

    delta_vel_world := impulse_to_torque * inverse_inertia_tensors[0]
    delta_vel_world *= impulse_to_torque
	delta_vel_world *= -1

    if contact.body[1] != nil {
		impulse_to_torque = Matrix3{
	    	0, -crp[1].z, crp[1].y,
	      	crp[1].z, 0, -crp[1].x,
	        -crp[1].y, crp[1].x, 0,
	    }

	    delta_vel_world2 := impulse_to_torque * inverse_inertia_tensors[1]
		delta_vel_world2 *= impulse_to_torque
	 	delta_vel_world2 *= -1
		delta_vel_world += delta_vel_world2

		inverse_mass += contact.body[1].inverse_mass
	}

	delta_velocity := linalg.transpose(contact.to_world)
	delta_velocity *= delta_vel_world
	delta_velocity *= contact.to_world

	delta_velocity[0, 0] += inverse_mass
	delta_velocity[1, 1] += inverse_mass
	delta_velocity[2, 2] += inverse_mass

	impulse_matrix := linalg.inverse(delta_velocity)
	kill_velocity := Vector3{contact.desired_delta_velocity, -contact.velocity.y, -contact.velocity.z}

	impulse_contact := impulse_matrix * kill_velocity
	planar_impulse := math.sqrt(impulse_contact.y*impulse_contact.y + impulse_contact.z*impulse_contact.z)

	if planar_impulse > impulse_contact.x * contact.friction {
		impulse_contact.y /= planar_impulse
		impulse_contact.z /= planar_impulse

		impulse_contact.x = delta_velocity[0,0] +
			delta_velocity[0,1]*contact.friction*impulse_contact.y +
			delta_velocity[0,2]*contact.friction*impulse_contact.z
		impulse_contact.x = contact.desired_delta_velocity / impulse_contact.x
		impulse_contact.y *= contact.friction * impulse_contact.x
		impulse_contact.z *= contact.friction * impulse_contact.x
	}

	return impulse_contact
}

contact_apply_position_change :: proc(contact: ^Contact, linear_change, angular_change: ^[2]Vector3, penetration: real) {
	angular_limit :: real(0.2)
	angular_move := [2]real{}
	linear_move := [2]real{}

	total_inertia := real(0.0)
	linear_inertia := [2]real{}
	angular_inertia := [2]real{}

	// We need to work out the inertia of each object in the direction
	// of the contact normal, due to angular inertia only.
	for i in 0..=1 {
		if contact.body[i] == nil do continue

		inverse_inertia_tensor := contact.body[i].inverse_inertia_tensor_world

		// Use the same procedure as for calculating frictionless
		// velocity change to work out the angular inertia.
		angular_inertia_world := linalg.cross(contact.relative_position[i], contact.normal)
		angular_inertia_world = inverse_inertia_tensor * angular_inertia_world
		angular_inertia_world = linalg.cross(angular_inertia_world, contact.relative_position[i])
		angular_inertia[i] = linalg.dot(angular_inertia_world, contact.normal)

		// The linear component is simply the inverse mass
		linear_inertia[i] = contact.body[i].inverse_mass

		// Keep track of the total inertia from all components
		total_inertia += linear_inertia[i] + angular_inertia[i]

		// We break the loop here so that the totalInertia value is
		// completely calculated (by both iterations) before
		// continuing.
	}

	// Loop through again calculating and applying the changes
	for i in 0..=1 {
		if contact.body[i] == nil do continue

		// The linear and angular movements required are in proportion to
		// the two inverse inertias.
		sign := (i == 0) ? real(1.0) : real(-1.0)
		angular_move[i] = sign * penetration * (angular_inertia[i] / total_inertia)
		linear_move[i] = sign * penetration * (linear_inertia[i] / total_inertia)

		// To avoid angular projections that are too great (when mass is large
		// but inertia tensor is small) limit the angular move.
		projection := contact.relative_position[i]
		projection += contact.normal * -linalg.dot(contact.relative_position[i], contact.normal)

		// Use the small angle approximation for the sine of the angle (i.e.
		// the magnitude would be sine(angularLimit) * projection.magnitude
		// but we approximate sine(angularLimit) to angularLimit).
		max_magnitude := angular_limit * linalg.length(projection)

		if angular_move[i] < -max_magnitude {
			total_move := angular_move[i] + linear_move[i]
			angular_move[i] = -max_magnitude
			linear_move[i] = total_move - angular_move[i]
		} else if angular_move[i] > max_magnitude {
			total_move := angular_move[i] + linear_move[i]
			angular_move[i] = max_magnitude
			linear_move[i] = total_move - angular_move[i]
		}

		// We have the linear amount of movement required by turning
		// the rigid body (in angularMove[i]). We now need to
		// calculate the desired rotation to achieve that.
		if angular_move[i] == 0.0 {
			// Easy case - no angular movement means no rotation.
			angular_change[i] = {}
		} else {
			// Work out the direction we'd like to rotate in.
			target_angular_direction := linalg.cross(contact.relative_position[i], contact.normal)

			inverse_inertia_tensor := contact.body[i].inverse_inertia_tensor_world

			// Work out the direction we'd need to rotate to achieve that
			angular_change[i] = (inverse_inertia_tensor * target_angular_direction) * (angular_move[i] / angular_inertia[i])
		}


		// Velocity change is easier - it is just the linear movement
		// along the contact normal.
		linear_change[i] = contact.normal * linear_move[i]

		// Now we can start to apply the values we've calculated.
		// Apply the linear movement
		contact.body[i].position += contact.normal * linear_move[i]

		// And the change in orientation
		quaternion_add_vector(&contact.body[i].orientation, angular_change[i])

		// We need to calculate the derived data for any body that is
		// asleep, so that the changes are reflected in the object's
		// data. Otherwise the resolution will not change the position
		// of the object, and the next collision detection round will
		// have the same penetration.
		if !contact.body[i].is_awake do body_calculate_derived_data(contact.body[i])
	}
}

ContactResolver :: struct {
	position_iterations: i32,
	velocity_iterations: i32,
	position_iterations_used: i32,
	velocity_iterations_used: i32,
	valid_settings: bool,
}

contact_resolver_is_valid :: proc(resolver: ^ContactResolver) -> bool {
	return resolver.position_iterations > 0 && resolver.velocity_iterations > 0 && VELOCITY_EPSILON >= 0 && POSITION_EPSILON >= 0
}

contact_resolve_contacts :: proc(resolver: ^ContactResolver, contacts: []Contact, duration: real) {
	// Make sure we have something to do.
	if len(contacts) == 0 do return
	if !contact_resolver_is_valid(resolver)	do return

	// Prepare the contacts for processing
	for &contact in contacts {
		contact_calculate_internals(&contact, duration)
	}

	contact_resolver_adjust_positions(resolver, contacts, duration)
	contact_resolver_adjust_velocities(resolver, contacts, duration)
}

contact_resolver_adjust_velocities :: proc(resolver: ^ContactResolver, c: []Contact, duration: real) {
	velocity_change := [2]Vector3{}
	rotation_change := [2]Vector3{}
	delta_vel := Vector3{}

	resolver.velocity_iterations_used = 0
	for resolver.velocity_iterations_used < resolver.velocity_iterations {
		// Find contact with maximum magnitude of desired velocity change.
		max := VELOCITY_EPSILON
		max_index := len(c)
		for &contact, i in c {
			if contact.desired_delta_velocity > max {
				max = contact.desired_delta_velocity
				max_index = i
			}
		}
		if max_index == len(c) do break
		contact_match_awake_state(&c[max_index])
		contact_apply_velocity_change(&c[max_index], &velocity_change, &rotation_change)

		// With the change in velocity of the two bodies, the update of contact velocities means that some of the relative closing velocities need to be re-calculated.
		for &contact, i in c {
			// Check each body in the contact
			for b in 0..=1 {
				if contact.body[b] == nil do continue

				// Check for a match with each body in the newly
                // resolved contact
				for d in 0..=1 {
					if contact.body[b] == c[max_index].body[d] {
						delta_vel = velocity_change[d] + linalg.cross(rotation_change[d], contact.relative_position[b])
						contact.velocity += linalg.transpose(contact.to_world) * delta_vel * ((b == 1) ? -1 : 1)
						contact_calculate_desired_delta_velocity(&contact, duration)
					}
				}
			}
		}

		resolver.velocity_iterations_used += 1
	}
}

contact_resolver_adjust_positions :: proc(resolver: ^ContactResolver, c: []Contact, duration: real) {
	linear_change, angular_change := [2]Vector3{}, [2]Vector3{}
	resolver.position_iterations_used = 0
	for resolver.position_iterations_used < resolver.position_iterations {
		// Find biggest penetration
		max := POSITION_EPSILON
		max_index := len(c)
		for &contact, i in c {
			if contact.penetration > max {
				max = contact.penetration
				max_index = i
			}
		}
		if max_index == len(c) do break

		contact_match_awake_state(&c[max_index])
		contact_apply_position_change(&c[max_index], &linear_change, &angular_change, max)

		for &contact, i in c {
			for b in 0..=1 {
				if contact.body[b] == nil do continue

				for d in 0..=1 {
					if contact.body[b] == c[max_index].body[d] {
						delta_position := linear_change[b] + linalg.cross(angular_change[b], contact.relative_position[b])
						contact.penetration += linalg.dot(delta_position, contact.normal) * (b==1 ? 1 : -1)
					}
				}
			}
		}

		resolver.position_iterations_used += 1
	}
}
