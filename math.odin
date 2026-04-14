package game

import "core:math"
import "core:math/linalg"
import "core:math/rand"


real :: f32
REAL_MAX :: real(math.F32_MAX)
Vector3 :: [3]real
Matrix3 :: matrix[3,3]real
Matrix4 :: matrix[3,4]real // the last row is awlays 0,0,0,1, we don't need to store it
Quaternion :: quaternion128

homogenous :: proc(v: Vector3) -> [4]real {
	return [4]real{v[0], v[1], v[2], 1.0}
}

only_rot :: proc(m: Matrix4) -> Matrix3 {
	return Matrix3{
		m[0, 0], m[0, 1], m[0, 2],
		m[1, 0], m[1, 1], m[1, 2],
		m[2, 0], m[2, 1], m[2, 2],
	}
}

matrix3_axis_vector :: proc(m: Matrix3, index: i32) -> Vector3{
	return Vector3{
		m[0, index],
		m[1, index],
		m[2, index],
	}
}

matrix4_axis_vector :: proc(m: Matrix4, index: i32) -> Vector3{
	return Vector3{
		m[0, index],
		m[1, index],
		m[2, index],
	}
}

matrix_axis_vector :: proc{
	matrix3_axis_vector, matrix4_axis_vector,
}

quaternion_add_vector :: proc(q: ^Quaternion, vector: Vector3) {
	nq := quaternion(w=0., x=vector.x, y=vector.y, z=vector.z)
	nq *= q^
	q.w += nq.w * 0.5
	q.x += nq.x * 0.5
	q.y += nq.y * 0.5
	q.z += nq.z * 0.5
}

random_vector :: proc(min, max: f32, y_min:f32=99999.) -> Vector3 {
	y_min := y_min
	if y_min == 99999. {
		y_min = min
	}

	return Vector3{
		rand.float32_range(min, max),
		rand.float32_range(y_min, max),
		rand.float32_range(min, max),
	}
}

random_orientation :: proc() -> Quaternion {
	q := quaternion(
		w= rand.float32_range(-1., 1.),
		x= rand.float32_range(-1., 1.),
		y= rand.float32_range(-1., 1.),
		z= rand.float32_range(-1., 1.),
	)
	return linalg.normalize(q)
}

// transform_direction :: proc(m: Matrix4, v: Vector3) -> Vector3 {
// 	return Vector3{
// 		m[0, 0] * v[0] + m[0, 1] * v[1] + m[0, 2] * v[2],
// 		m[1, 0] * v[0] + m[1, 1] * v[1] + m[1, 2] * v[2],
// 		m[2, 0] * v[0] + m[2, 1] * v[1] + m[2, 2] * v[2],
// 	}
// }
