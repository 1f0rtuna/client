extends Node
class_name NPC_Controller


var aggro_type: UnitData.AggroType
var aggro_distance: float = 1.0
var deaggro_distance: float = 3.0

var aggro_collider: Area3D

var controlled_unit: Unit

func _ready():
	if not controlled_unit:
		var parent = get_parent()
		while parent.get_class() != "Unit":
			parent = parent.get_parent()

		controlled_unit = parent

	# Create the aggro collider.
	var aggro_shape = CapsuleShape3D.new()
	aggro_shape.radius = aggro_distance

	var aggro_collision_shape = CollisionShape3D.new()
	aggro_collision_shape.shape = aggro_shape

	aggro_collider = Area3D.new()
	aggro_collider.name = "AggroCollider"
	aggro_collider.add_child(aggro_collision_shape)

	aggro_collider.body_entered.connect(_enter_aggro_range)

	add_child(aggro_collider)

	# create the deaggro collider.
	var deaggro_shape = CapsuleShape3D.new()
	deaggro_shape.radius = deaggro_distance

	var deaggro_collision_shape = CollisionShape3D.new()
	deaggro_collision_shape.shape = deaggro_shape

	var deaggro_collider = Area3D.new()
	deaggro_collider.name = "DeaggroCollider"
	deaggro_collider.add_child(deaggro_collision_shape)

	deaggro_collider.body_exited.connect(_exit_deaggro_range)

	add_child(deaggro_collider)


func _process(_delta):
	if not controlled_unit.target_entity: return
	
	controlled_unit.change_state("Moving", controlled_unit.target_entity.position)


func _enter_aggro_range(body: PhysicsBody3D):
	if aggro_type != UnitData.AggroType.AGGRESSIVE: return
	if controlled_unit.target_entity: return

	var _collided_unit = body as Unit
	if _collided_unit == null:
		return
	
	if _collided_unit == controlled_unit: return
	if _collided_unit.team == controlled_unit.team: return
	
	print("Now targeting:" + _collided_unit.name)
	
	controlled_unit.target_entity = body as Unit
	# Make the attacking work in the future, for now just follow the target
	#controlled_unit.change_state("Attacking", null)
	controlled_unit.change_state("Moving", _collided_unit.position)


func _exit_deaggro_range(body: PhysicsBody3D):
	if body != controlled_unit.target_entity: return
	
	controlled_unit.change_state("Idle", null)
