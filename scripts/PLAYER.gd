extends Node3D

var cam_transform
var look_at_direction
var target_look_at_direction

var lane_index = 1
var rotation_speed = 5.0
var cam_position
var cam_rotation_speed = 5.0

var shake_intensity = 0
var vertical_force = 0.0
var magnet_active = false
var dead = false

func _ready():
	cam_position = $ANCHOR/MESH/Camera.transform.origin
	look_at_direction = global_transform.basis.z
	cam_transform = $ANCHOR/MESH/Camera.transform
	target_look_at_direction = global_transform.basis.z
	$ANCHOR/MESH/MODEL/AnimationTree.active = true
	$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 1)
	$ANCHOR/MESH/MODEL/SENSOR.body_entered.connect(on_collision)
	$ANCHOR/MESH/MODEL/MAGNET_SENSOR.body_entered.connect(on_magnet_collision)
	Globals.on_die.connect(on_die)
	Globals.on_toggle_magnet.connect(on_toggle_magnet)

func _process(delta):
	# 相机震动
	if shake_intensity > 0.0:
		shake_intensity -= delta
		$ANCHOR/MESH/Camera.transform.origin = cam_position + 2.0 * shake_intensity * Vector3(cos(0.05 * Time.get_ticks_msec()), sin(0.05 * Time.get_ticks_msec()), 0.0)
	
	# 如果玩家已死亡，不再处理后续逻辑
	if dead: return
	
	# 朝行走方向看
	look_at_direction = lerp(look_at_direction, target_look_at_direction, delta * 5.0)
	$ANCHOR.global_transform.basis = Globals.slerp_look_at($ANCHOR.global_transform, global_transform.origin + look_at_direction, cam_rotation_speed * delta)
	$ANCHOR/MESH/MODEL.global_transform.basis = Globals.slerp_look_at($ANCHOR/MESH/MODEL.global_transform, $ANCHOR/MESH/MODEL.global_transform.origin - look_at_direction + Vector3.UP, rotation_speed * delta)

	# 在车道之间插值移动玩家
	$ANCHOR/MESH.transform.origin.x = lerp($ANCHOR/MESH.transform.origin.x, float((lane_index * 5) - 5), delta * 15.0)
	$ANCHOR/MESH.transform.origin.x = clamp($ANCHOR/MESH.transform.origin.x, -5.0, 5.0)

	# 左右移动并播放动画，切换车道索引
	if Input.is_action_just_pressed("r_left"):
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe_state/current", 0)
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe/active", true)
		switch_lane(-1)
	if Input.is_action_just_pressed("r_right"):
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe_state/current", 1)
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/strafe/active", true)
		switch_lane(1)
		
	# 跳跃并缓慢将玩家拉回地面
	if Input.is_action_just_pressed("r_jump") and $ANCHOR/MESH.transform.origin.y < 1.0:
		vertical_force = 5.0
	vertical_force = lerp(vertical_force, -3.0, 5.0 * delta)
	
	if vertical_force > 0:
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 2)
	elif $ANCHOR/MESH.transform.origin.y > 0:
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 3)
	else:
		$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/state/current", 1)
		vertical_force = 0.0
	
	$ANCHOR/MESH.transform.origin.y += vertical_force
	$ANCHOR/MESH.transform.origin.y = clamp($ANCHOR/MESH.transform.origin.y, 0.0, 40.0)

	# 模拟重力
	if global_transform.origin.y > 0:
		global_transform.origin.y -= delta * 10.0
	
	# 模拟跑步时的相机晃动
	if shake_intensity <= 0.0:
		$ANCHOR/MESH/Camera.transform.origin.x = 0.35 * cos(0.0075 * Time.get_ticks_msec())
		$ANCHOR/MESH/Camera.transform.origin.y = cam_position.y + 0.35 * sin(0.0075 * Time.get_ticks_msec())
		
func set_look_at(dir):
	target_look_at_direction = dir * 10.0

func switch_lane(dir):
	lane_index += dir
	if lane_index > 2:
		lane_index = 2
	if lane_index < 0:
		lane_index = 0

# 判断碰撞后的行为
func on_collision(body):
	if body.is_in_group("coin"):
		Globals.on_collect.emit("coin")
		ObjectPooling.queue_free_instance(body)
	if body.is_in_group("magnet"):
		Globals.on_collect.emit("magnet")
		ObjectPooling.queue_free_instance(body)
	if body.is_in_group("obstacle"):
		shake_intensity = 0.5
		Globals.on_obstacle.emit()

func on_die():
	dead = true
	$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/dead/blend_amount", 1.0)

func on_toggle_magnet(activate):
	$ANCHOR/MESH/MODEL/AnimationTree.set("parameters/magnet/blend_amount", int(activate))
	$ANCHOR/MESH/MODEL/bee/rig/Skeleton/MAGNET.visible = activate
	magnet_active = activate

func on_magnet_collision(body):
	if body.is_in_group("coin") and magnet_active:
		Globals.on_coin_magnet_collision.emit(body)
