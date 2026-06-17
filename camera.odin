package game

import "core:math"
import rl "vendor:raylib"

CAMERA_MAX_HEIGHT :f32: 50.

camera_zoom :: proc(position: Vector3){
	return
	// game.camera3d.desired_target = position
	// // never look down directly...
	// game.camera3d.desired_position = {position.x, 40, position.z}
	// game.camera3d.desired_fovy = 50
}

camera_reset :: proc(){
	game.camera3d.desired_target = {0, 0, 3.0}
	game.camera3d.desired_position = {
		0.,//math.cos(game.camera3d.angle)*30.,
		CAMERA_MAX_HEIGHT,
		3.0,// math.sin(game.camera3d.angle)*30.
	}
	game.camera3d.desired_fovy = 40
}

ring_position_2d :: proc(index: int, radius: f32) -> (Vector2, TextAnchor){
	// There are seven possible positions
	//   1
	// 6   2
	//   0
	// 5   3
	//   4
	angle :f32= math.PI/6.
	switch index {
	case 1:
		return {0, -radius}, .CENTER
	case 2:
		return {radius*math.cos(angle), -radius*math.sin(angle)}, .LEFT
	case 3:
		return {radius*math.cos(angle), radius*math.sin(angle)}, .LEFT
	case 4:
		return {0, radius}, .CENTER
	case 5:
		return {-radius*math.cos(angle), radius*math.sin(angle)}, .RIGHT
	case 6:
		return {-radius*math.cos(angle), -radius*math.sin(angle)}, .RIGHT
	case:
		return {}, .CENTER
	}
}
ring_position_3d :: proc(index: int, radius: f32) -> (Vector3, TextAnchor){
	// There are seven possible positions
	//   1
	// 6   2
	//   0
	// 5   3
	//   4
	angle :f32= math.PI/6.
	switch index {
	case 1:
		return {0, 0, -radius}, .CENTER
	case 2:
		return {radius*math.cos(angle), 0, -radius*math.sin(angle)}, .LEFT
	case 3:
		return {radius*math.cos(angle), 0, radius*math.sin(angle)}, .LEFT
	case 4:
		return {0, 0, radius}, .CENTER
	case 5:
		return {-radius*math.cos(angle), 0, -radius*math.sin(angle)}, .RIGHT
	case 6:
		return {-radius*math.cos(angle), 0, radius*math.sin(angle)}, .RIGHT
	case:
		return {}, .CENTER
	}
}
