package game

import "core:math"
import "core:math/rand"


real :: f32
REAL_MAX :: math.F32_MAX
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

random_vector :: proc(min, max: f32) -> Vector3 {
	return Vector3{
		rand.float32_range(min, max),
		rand.float32_range(min, max),
		rand.float32_range(min, max),
	}
}

// transform_direction :: proc(m: Matrix4, v: Vector3) -> Vector3 {
// 	return Vector3{
// 		m[0, 0] * v[0] + m[0, 1] * v[1] + m[0, 2] * v[2],
// 		m[1, 0] * v[0] + m[1, 1] * v[1] + m[1, 2] * v[2],
// 		m[2, 0] * v[0] + m[2, 1] * v[1] + m[2, 2] * v[2],
// 	}
// }
