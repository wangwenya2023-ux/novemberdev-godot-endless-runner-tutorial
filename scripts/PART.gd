extends Node3D
class_name PART

var visited = false
@export var type: String

# 如果该部分被标记为已访问，则卸载它
func _process(delta):
	if visited:
		visited = false
		ObjectPooling.queue_free_instance(self)
		Globals.on_unload_part.emit(self)

# 移除该部分内所有活跃的障碍物
func on_object_pooling_reset(activate):
	if !activate:
		visited = false
		for obstacle in $OBSTACLES.get_children():
			ObjectPooling.queue_free_instance(obstacle)
