@tool
extends EditorPlugin

var menu

func _enter_tree():
	menu = Button.new()
	menu.text = "Compute Parts"
	menu.pressed.connect(on_compute_parts)
	add_control_to_container(EditorPlugin.CONTAINER_TOOLBAR, menu)

func _exit_tree():
	remove_control_from_container(EditorPlugin.CONTAINER_TOOLBAR, menu)

func on_compute_parts():
	var root = get_tree().get_edited_scene_root()
	
	# 如果此节点存在
	if root.has_node("OBJECT_LAYOUTS"):
		var layouts = {}
		# 遍历所有子节点
		for node in root.get_node("OBJECT_LAYOUTS").get_children():
			# 记录所有布局并存储放置了哪些节点
			var s = node.name.split('_')
			var type = s[0]
			if !layouts.has(type):
				layouts[type] = []
			var new_layout = {
				name = node.name,
				children = []
			}
			for item in node.get_children():
				var v = item.transform.origin
				new_layout.children.push_back({
					name = item.name,
					x = v.x,
					y = v.y,
					z = v.z,
					rx = item.rotation.x,
					ry = item.rotation.y,
					rz = item.rotation.z
				})
			layouts[type].push_back(new_layout)
		var f = FileAccess.open("res://compiled_parts.tres", FileAccess.WRITE)
		if f == null:
			print("compiling parts: error opening file")
		else:
			f.store_string(JSON.stringify(layouts))
		root.remove_child(root.get_node("OBJECT_LAYOUTS"))
	else:
		# 读取布局部件
		var f = FileAccess.open("res://compiled_parts.tres", FileAccess.READ)
		if f == null:
			print("reading parts: error opening file")
			return
		var json = JSON.new()
		json.parse(f.get_as_text())
		var layouts = json.data
		var layouts_node
		if !root.has_node("OBJECT_LAYOUTS"):
			layouts_node = Node3D.new()
			layouts_node.name = "OBJECT_LAYOUTS"
			root.add_child(layouts_node)
			layouts_node.set_owner(root)
		else:
			layouts_node = root.get_node("OBJECT_LAYOUTS")
		# 遍历布局并在这些位置实例化相关场景
		for part in layouts.values():
			for layout in part:
				var s = Node3D.new()
				s.name = layout.name
				s.visible = false
				layouts_node.add_child(s)
				s.set_owner(root)
				for item in layout.children:
					var n = item.name.split('_')
					var p = null
					if item.name.begins_with("COIN"):
						p = load("res://scenes/COIN.tscn").instantiate()
					elif item.name.begins_with("PICKUP"):
						p = load("res://scenes/MAGNET.tscn").instantiate()
					elif item.name.begins_with("SHIELD"):
						p = load("res://scenes/SHIELD.tscn").instantiate()
					elif item.name.begins_with("SPEED"):
						p = load("res://scenes/SPEED.tscn").instantiate()
					elif item.name.begins_with("TOKEN"):
						p = load("res://scenes/TOKEN.tscn").instantiate()
					else:
						p = load("res://scenes/obstacles/" + n[0].to_lower() + ".tscn").instantiate()
					p.name = item.name
					p.transform.origin = Vector3(item.x, item.y, item.z)
					p.rotation = Vector3(item.rx, item.ry, item.rz)
					s.add_child(p)
					p.set_owner(root)
