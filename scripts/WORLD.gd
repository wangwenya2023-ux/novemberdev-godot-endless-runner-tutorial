extends Node3D

var coins = 0
var parts = {}
var dead = false
var distance = 0
var speed_time = 0.0
var dead_timer = 0.0
var magnet_coins = []
var magnet_time = 0.0
var total_speed = 0.0
var current_speed = 40
var themes = ["TERRAN"]
var part_instances = []
var part_free_queue = []
var obstacle_scenes = {}
var obstacle_layouts = {}
var left_turn_counter = 0
var right_turn_counter = 0
var spawn_part_counter = 0
var current_theme_index = 0
var theme_switch_time = 45.0
var part_lane_coordinates = []
var current_direction = -Vector3.FORWARD

# 此脚本控制整个游戏状态。
# 它围绕玩家生成和移动部件，
# 基于预录制的和当前的车道点，
# 即玩家附近的位置。

func _ready():
	prepare_parts()
	preparte_obstacles()
	preparte_obstacle_scenes()
	Globals.on_collect.connect(on_collect)
	Globals.on_obstacle.connect(on_obstacle)
	$Control/SPEEDBTN.pressed.connect(on_speed)
	Globals.on_unload_part.connect(on_unload_part)
	Globals.on_coin_magnet_collision.connect(on_coin_magnet_collision)
	
	# 在开始时生成几个部件
	# 索引确保不会生成障碍物
	for i in 5:
		spawn_next_part(i)
		await get_tree().process_frame

func _process(delta):
	current_speed += delta * 0.4
	distance += delta * current_speed * 0.1
	$Control/COINS.text = "%s Coins" % [int(coins)]
	$Control/DISTANCE.text = "%s Distance" % [int(distance)]
	$Control/SPEED.text = "%s Speed" % [int(current_speed)]
	
	# 根据时间切换主题
	theme_switch_time -= delta
	if theme_switch_time <= 0.0:
		theme_switch_time = 45.0
		current_theme_index += 1
		if current_theme_index > themes.size()-1:
			current_theme_index = 0
			
	# 激活超级速度
	if speed_time > 0.0:
		speed_time -= delta 
		total_speed = min(current_speed + 50.0, 200.0)
	else:
		total_speed = current_speed
		
	# 如果玩家死亡一段时间后重新加载游戏
	if dead:
		dead_timer -= delta
		if dead_timer < 0.0:
			for part in $PARTS.get_children():
				ObjectPooling.queue_free_instance(part)
			get_tree().reload_current_scene()
		return
		
	# 如果玩家携带磁铁，将收集的金币移向玩家
	for coin in magnet_coins:
		if !coin.is_inside_tree():
			magnet_coins.erase(coin)
		else:
			coin.global_transform.origin += delta * 80.0 * ($PLAYER.get_node("ANCHOR/MESH/MODEL").global_transform.origin - coin.global_transform.origin).normalized()
		
	# 一段时间后停用磁铁
	if magnet_time > 0:
		magnet_time -= delta
		if magnet_time < 0:
			Globals.on_toggle_magnet.emit(false)
		
	# 如果部件被标记为移除，
	# 在达到一定距离后移除它们，
	# 这样玩家不会注意到
	while part_free_queue.size() > 0:
		var part_free_instance = part_free_queue[0]
		if part_free_instance.global_transform.origin.distance_to($PLAYER.global_transform.origin) > 150:
			part_free_instance.visited = true
			part_free_queue.pop_front()
		else:
			break

	# 检查当前车道点是否在不同的部件上
	# 如果是，标记当前部件为卸载
	if part_lane_coordinates[0].name != part_lane_coordinates[1].name:
		if part_free_queue.find($PARTS.get_node(NodePath(part_lane_coordinates[0].name))) == -1:
			part_free_queue.push_back($PARTS.get_node(NodePath(part_lane_coordinates[0].name)))
	
	var current_lane_coordinate = part_lane_coordinates[0].point.global_transform.origin
	
	# 如果玩家到达该点，弹出车道点栈的下一个点
	if current_lane_coordinate.distance_to($PLAYER.global_transform.origin) < 3.0:
		part_lane_coordinates.pop_front()
	
	current_direction = (current_lane_coordinate - $PLAYER.global_transform.origin).normalized()
	$PLAYER.set_look_at(current_direction)
	
	# 围绕玩家移动世界
	$PARTS.global_transform.origin -= current_direction * delta * total_speed
	$PARTS.global_transform.origin.y = 0
	
	# 如果部件被卸载，自动生成更多部件
	if spawn_part_counter > 0:
		for i in range(spawn_part_counter):
			spawn_next_part(10)
		spawn_part_counter = 0

# 卸载部件并检查有多少转弯被卸载
func on_unload_part(part):
	match part.type:
		"RCURVE":
			right_turn_counter -= 1
		"LCURVE":
			left_turn_counter -= 1
	part_instances.erase(part)
	spawn_part_counter += 1

# 生成新部件
func spawn_next_part(index):
	randomize()
	
	# 根据当前主题索引获取任意部件
	var part = parts[themes[current_theme_index]][randi()%parts[themes[current_theme_index]].size()]
	
	# 检查转弯数量是否会产生重叠
	match part.type:
		"LCURVE":
			if left_turn_counter > 0 or index < 4:
				return spawn_next_part(index)
			left_turn_counter += 1
		"RCURVE":
			if right_turn_counter > 0 or index < 4:
				return spawn_next_part(index)
			right_turn_counter += 1
	
	var part_instance = ObjectPooling.load_from_pool(part.file)
	
	# 生成障碍物
	initialize_part(part, part_instance, index)
	$PARTS.add_child(part_instance)
	
	if part_instance.has_node("OBJECT_LAYOUTS"):
		print("Warning: " + str(part.file) + " has uncompiled OBJECT_LAYOUTS, this can lead to invisible collisions")
	
	# 通过获取最后一个部件的前端位置来连接部件，
	# 将新部件的后端位置对齐到该位置，
	# 并使其朝向前方方向
	if part_instances.size() > 0:
		var latest_part = part_instances[part_instances.size()-1]
		part_instance.global_transform.origin = latest_part.get_node("FRONT").global_transform.origin
		part_instance.look_at(
			part_instance.global_transform.origin 
			- (latest_part.get_node("FRONT").global_transform.origin 
				- latest_part.get_node("FRONT_DIRECTION").global_transform.origin).normalized(), 
			Vector3.UP)
		part_instance.global_transform.origin -= (part_instance.get_node("BACK").global_transform.origin - part_instance.global_transform.origin)
		part_instance.global_transform.origin.y = 0
		
	# 记录该部件的所有车道点
	initialize_lane_points(part_instance, index)
	part_instances.push_back(part_instance)
	
# 记录该部件实例的所有车道点
func initialize_lane_points(part_instance, index):
	for lane_point in part_instance.get_node("LANE").get_children():
		# 如果点在玩家后面，跳过它
		if index < 2:
			if($PLAYER.global_transform.origin - lane_point.global_transform.origin).normalized().dot($PLAYER.global_transform.basis.z) < 0:
				continue
		part_lane_coordinates.push_back({ 
			name = part_instance.name,
			point = lane_point
		})
	
	part_instances.push_back(part_instance)
	
# 在该部件上生成障碍物
func initialize_part(part, part_instance, index):
	
	# 不在前两个部件上生成障碍物
	# 以避免在生成时立即碰撞
	if index < 2: 
		return
	if obstacle_layouts.has(part.type):
		var layouts = obstacle_layouts[part.type]
		var layout = layouts[randi()%layouts.size()]
		
		# 扩展此处以覆盖下面拾取物的行为
		var pickups = ["MAGNET"]
		for obstacle in layout.children:
			randomize()
			var object_instance = null
			# 覆盖某些拾取物和障碍物的行为
			if obstacle.name.begins_with("COIN"):
				object_instance = ObjectPooling.load_from_pool("res://scenes/COIN.tscn")
			elif pickups.find(obstacle.name.split('_')[0]) != -1:
				object_instance = ObjectPooling.load_from_pool("res://scenes/" + pickups[randi()%pickups.size()] + ".tscn")
			else:
				var obstacle_type = obstacle.name.split('_')[0]
				var obstacle_file = obstacle_scenes[obstacle_type + "_" + themes[current_theme_index]][randi()%obstacle_scenes[obstacle_type + "_" + themes[current_theme_index]].size()]
				object_instance = ObjectPooling.load_from_pool(obstacle_file.file)
			part_instance.get_node("OBSTACLES").add_child(object_instance)
			object_instance.transform.origin = Vector3(obstacle.x, obstacle.y, obstacle.z)
			object_instance.rotation = Vector3(obstacle.rx, obstacle.ry, obstacle.rz)
			object_instance.visible = true
			
func prepare_parts():
	# 此方法获取 res://scenes/parts 内的所有场景
	# 并按主题（Space...）存储到 parts 中
	# 以存储它们的场景路径
	var dir = DirAccess.open("res://scenes/parts")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir():
				var part = {
					file = "res://scenes/parts/" + file_name,
					type = file_name.split('_')[0],
					theme = file_name.split('_')[1],
					difficulty = file_name.split('_')[2].replace(".tscn", "")
				}
				if !parts.has(part.theme):
					parts[part.theme] = []
				parts[part.theme].push_back(part) 
			file_name = dir.get_next()
	else:
		print("WORLD.gd: error loading res://scenes/parts/*")

func preparte_obstacles():
	# 此方法获取 res://scenes/obstacles 内的所有场景
	# 并按类型（middle, single, side）存储到 obstacle_types 中
	# 以存储它们的场景路径到相应数组中
	var file = FileAccess.open("res://compiled_parts.tres", FileAccess.READ)
	if file == null:
		print("World.gd: error reading compiled_parts.tres")
	else:
		var json = JSON.new()
		json.parse(file.get_as_text())
		obstacle_layouts = json.data

# 获取所有障碍物并存储到字典中以便快速检索
func preparte_obstacle_scenes():
	var dir = DirAccess.open("res://scenes/obstacle_scenes")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if !dir.current_is_dir():
				var obstacle_scene = {
					file = "res://scenes/obstacle_scenes/" + file_name,
					type = file_name.split('_')[0],
					theme = file_name.split('_')[1]
				}
				if !obstacle_scenes.has(obstacle_scene.type + "_" + obstacle_scene.theme):
					obstacle_scenes[obstacle_scene.type + "_" + obstacle_scene.theme] = []
				obstacle_scenes[obstacle_scene.type + "_" + obstacle_scene.theme].push_back(obstacle_scene) 
			file_name = dir.get_next()
	else:
		print("WORLD.gd: error loading res://scenes/obstace_scenes/*")

# 判断收集拾取物后的行为
func on_collect(type):
	match type:
		"magnet":
			Globals.on_toggle_magnet.emit(true)
			magnet_time = 8.0
		"coin":
			coins += 1
			$Control/COINLEVEL.value = min($Control/COINLEVEL.value + 4.0, 100.0)
			if $Control/COINLEVEL.value == 100.0:
				$Control/SPEEDBTN.disabled = false

func on_coin_magnet_collision(body):
	magnet_coins.push_back(body)

# 控制碰撞障碍物后的行为
func on_obstacle():
	if dead:
		return
	if speed_time > 0.0:
		return
	if current_speed < 50:
		Globals.on_die.emit()
		$Control/SPEEDBTN.disabled = true
		dead_timer = 2.0
		dead = true
	else:
		current_speed -= 10.0
		
func on_speed():
	speed_time = 10.0
	$Control/COINLEVEL.value = 0
	$Control/SPEEDBTN.disabled = true
