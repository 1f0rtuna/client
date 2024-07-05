extends CharacterBody3D
class_name Unit


# General Stats:
@export var id: int
@export var team: int
# Defensive Stats:

#@export var magic_resist:float = 20.0

# Offensive Stats:
#@export var attack_windup: float = 0.2
#@export var attack_time: float = 0.1
#@export var critical_chance: float = 0.0
#@export var critical_damage: float = 100


var maximum_stats: StatCollection
var current_stats: StatCollection
var per_level_stats: StatCollection

var has_mana: bool = false

var current_shielding: int = 0

# Rotation:
@export var turn_speed: float = 15.0

@export var unit_id : String = ""

# Each bit of cc_state represents a different type of crowd control.
var cc_state: int = 0
var effect_array: Array[UnitEffect] = []

var target_entity: Node = null
var server_position

var nav_agent : NavigationAgent3D

@export var can_respawn: bool = false

# Signals
signal died

# UI
@export var projectile_scene: PackedScene = null
var healthbar : ProgressBar

# Preloaded scripts and scenes
const state_machine_script = preload("res://scripts/states/_state_machine.gd")
const state_idle_script = preload("res://scripts/states/unit_idle.gd")
const state_move_script = preload("res://scripts/states/unit_move.gd")
const state_auto_attack_script = preload("res://scripts/states/unit_auto_attack.gd")

const healthbar_scene = preload("res://ui/player_stats/healthbar.tscn")


func _init():
	if maximum_stats == null:
		maximum_stats = StatCollection.from_dict({
			"health_max": 640,
			"health_regen": 3.5,

			"mana_max": 280,
			"mana_regen": 7,
			
			"armor": 26,
			"magic_resist": 30,

			"attack_range": 3.0,
			"attack_damage": 60,
			"attack_speed": 0.75,

			"movement_speed": 100,
		} as Dictionary)
	
	if current_stats == null:
		current_stats = maximum_stats.get_copy()

	if per_level_stats == null:
		per_level_stats = StatCollection.new()


func _ready():
	# setting up the multiplayer synchronization
	var replication_config = SceneReplicationConfig.new()

	replication_config.add_property(NodePath(".:rotation"))
	replication_config.property_set_spawn(NodePath(".:rotation"), true)
	replication_config.property_set_replication_mode(NodePath(".:rotation"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	replication_config.add_property(NodePath(".:id"))
	replication_config.property_set_spawn(NodePath(".:id"), true)
	replication_config.property_set_replication_mode(NodePath(".:id"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	replication_config.add_property(NodePath(".:maximum_stats"))
	replication_config.property_set_spawn(NodePath(".:maximum_stats"), true)
	replication_config.property_set_replication_mode(NodePath(".:maximum_stats"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	replication_config.add_property(NodePath(".:current_stats"))
	replication_config.property_set_spawn(NodePath(".:current_stats"), true)
	replication_config.property_set_replication_mode(NodePath(".:current_stats"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)

	replication_config.add_property(NodePath(".:server_position"))
	replication_config.property_set_spawn(NodePath(".:server_position"), true)
	replication_config.property_set_replication_mode(NodePath(".:server_position"), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
	
	var multiplayer_synchronizer = MultiplayerSynchronizer.new()
	multiplayer_synchronizer.set_replication_config(replication_config)
	multiplayer_synchronizer.name = "MultiplayerSynchronizer"
	add_child(multiplayer_synchronizer)

	# setting up the state machine
	var state_machine_node = Node.new()
	state_machine_node.name = "StateMachine"
	state_machine_node.set_script(state_machine_script)

	var state_idle_node = Node.new()
	state_idle_node.name = "Idle"
	state_idle_node.set_script(state_idle_script)
	state_machine_node.add_child(state_idle_node)

	var state_move_node = Node.new()
	state_move_node.name = "Moving"
	state_move_node.set_script(state_move_script)
	state_machine_node.add_child(state_move_node)

	var state_auto_attack_node = Node.new()
	state_auto_attack_node.name = "Attacking"
	state_auto_attack_node.set_script(state_auto_attack_script)
	state_machine_node.add_child(state_auto_attack_node)

	add_child(state_machine_node)

	# set up the abilities
	var abilities_node = Node.new()
	abilities_node.name = "Abilities"

	var auto_attack_node = Node.new()
	auto_attack_node.name = "AutoAttack"

	var aa_windup_node = Timer.new()
	aa_windup_node.name = "AAWindup"
	aa_windup_node.one_shot = true
	aa_windup_node.process_callback = Timer.TIMER_PROCESS_PHYSICS
	auto_attack_node.add_child(aa_windup_node)

	var aa_cooldown_node = Timer.new()
	aa_cooldown_node.name = "AACooldown"
	aa_cooldown_node.one_shot = true
	aa_cooldown_node.process_callback = Timer.TIMER_PROCESS_PHYSICS
	auto_attack_node.add_child(aa_cooldown_node)

	abilities_node.add_child(auto_attack_node)
	add_child(abilities_node)

	# set up projectile spawning
	var projectiles_node = Node.new()
	projectiles_node.name = "Projectiles"
	add_child(projectiles_node)

	var projectile_spawner_node = MultiplayerSpawner.new()
	projectile_spawner_node.name = "ProjectileSpawner"
	projectile_spawner_node.add_spawnable_scene("res://scenes/projectiles/arrow.tscn")
	projectile_spawner_node.spawn_limit = 999
	projectile_spawner_node.spawn_path = NodePath("../Projectiles")
	add_child(projectile_spawner_node)

	# set up the navitation agent
	var _nav_agent = NavigationAgent3D.new()
	_nav_agent.name = "NavigationAgent3D"
	add_child(_nav_agent)
	nav_agent = get_node("NavigationAgent3D")

	# set up the healthbar
	var healthbar_node = healthbar_scene.instantiate()
	healthbar_node.name = "Healthbar"
	add_child(healthbar_node)
	healthbar = get_node("Healthbar")



# Movement
func update_target_location(target_location: Vector3):
	print("Target Location Updated");
	target_entity = null
	nav_agent.target_position = target_location


## Combat
func take_damage(damage: float):
	if not can_take_damage(): return

	var taken = float(current_stats.armor) / 100.0
	taken = damage / (taken + 1)

	var actual_damage = int(taken)
	if current_shielding > 0:
		current_shielding -= actual_damage
		if current_shielding <= 0:
			current_stats.health_max += current_shielding
			current_shielding = 0
	else:
		current_stats.health_max -= actual_damage
	
	if current_stats.health_max <= 0:
		current_stats.health_max = 0
		die()


func heal(amount:float, keep_extra:bool = false):
	current_stats.health_max += int(amount)
	if current_stats.health_max <= maximum_stats.health_max: return
	if keep_extra:
		current_shielding = current_stats.health_max - maximum_stats.health_max
	current_stats.health_max = maximum_stats.health_max


func die():
	get_tree().quit()

# UI
func _update_healthbar(node: ProgressBar):
	node.value = current_stats.health_max


func move_on_path(delta: float):
	if nav_agent.is_navigation_finished(): return
	if not can_move(): return
	server_position = global_position
	
	var target_location = nav_agent.get_next_path_position()
	var direction = target_location - global_position
	
	velocity = direction.normalized() * current_stats.movement_speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(-direction.x, -direction.z), turn_speed * delta)
	move_and_slide()


func apply_effect(effect: UnitEffect):
	effect_array.append(effect)
	add_child(effect)
	recalculate_cc_state()


func _on_cc_end(effect: UnitEffect):
	effect_array.erase(effect)
	effect.end()
	recalculate_cc_state()


func recalculate_cc_state() -> int:
	var new_state := 0
	for effect in effect_array:
		new_state = new_state | effect.cc_mask
	cc_state = new_state
	return new_state


func can_move() -> bool:
	return cc_state & CCTypesRegistry.CC_MASK_MOVEMENT == 0


func can_cast_movement() -> bool:
	return cc_state & CCTypesRegistry.CC_MASK_CAST_MOBILITY == 0


func can_attack() -> bool:
	return cc_state & CCTypesRegistry.CC_MASK_ATTACK == 0


func can_cast() -> bool:
	return cc_state & CCTypesRegistry.CC_MASK_CAST == 0


func can_change_target() -> bool:
	return cc_state & CCTypesRegistry.CC_MASK_TARGET == 0


func can_take_damage() -> bool:
	return cc_state & CCTypesRegistry.CC_MASK_TAKE_DAMAGE == 0


@rpc("authority", "call_local")
func change_state(new, args):
	$StateMachine.change_state(new, args);
