extends Control

## Data Systems Demo
## Demonstrates game data, user data, and actions

@onready var output_label: Label = $VBox/ScrollContainer/OutputLabel
@onready var init_btn: Button = $VBox/Buttons/InitBtn
@onready var complete_level_btn: Button = $VBox/Buttons/CompleteLevelBtn
@onready var check_data_btn: Button = $VBox/Buttons/CheckDataBtn
@onready var save_btn: Button = $VBox/Buttons/SaveBtn
@onready var load_btn: Button = $VBox/Buttons/LoadBtn

var output_text: String = ""


func _ready() -> void:
	# Connect buttons
	init_btn.pressed.connect(_on_init_pressed)
	complete_level_btn.pressed.connect(_on_complete_level_pressed)
	check_data_btn.pressed.connect(_on_check_data_pressed)
	save_btn.pressed.connect(_on_save_pressed)
	load_btn.pressed.connect(_on_load_pressed)

	# Connect to actions system
	if ActionsSystem:
		ActionsSystem.action_fired.connect(_on_action_fired)

	_log("Data Systems Demo Ready!")
	_log("Click 'Initialize Data' to start")


func _on_init_pressed() -> void:
	_log("\n=== Initializing Data ===")

	# Create user if needed
	if UserDataSystem.user_manager.get_user_count() == 0:
		var user_id = UserDataSystem.create_user("DemoPlayer")
		_log("Created user: DemoPlayer (ID: %s)" % user_id)
	else:
		_log("User already exists")

	# Initialize user level data
	var user_levels = UserDataSystem.get_all_data("UserLevel")
	if user_levels.is_empty():
		_log("Initializing user level data...")

		# For demo, we'll manually create user level data
		# In real game, you'd load from game data
		for i in range(1, 6):
			var user_level = {
				"level_id": i,
				"unlocked": i == 1,  # Only first level unlocked
				"complete": false,
				"completed_no_deaths": false,
				"best_time": 0.0
			}
			UserDataSystem.add_data("UserLevel", user_level)
			_log("  Created UserLevel for level %d" % i)

		UserDataSystem.save_user_data()
		_log("User data saved!")
	else:
		_log("User data already initialized (%d levels)" % user_levels.size())


func _on_complete_level_pressed() -> void:
	_log("\n=== Completing Level 1 ===")

	# Dispatch action (the recommended way!)
	ActionsSystem.dispatch("level_completed", {
		"level_id": 1,
		"time": 45.5,
		"no_deaths": true
	})

	_log("Dispatched 'level_completed' action")

	# Unlock next level
	ActionsSystem.dispatch("level_unlocked", {
		"level_id": 2
	})

	_log("Dispatched 'level_unlocked' action for level 2")


func _on_check_data_pressed() -> void:
	_log("\n=== Checking User Data ===")

	var user_levels = UserDataSystem.get_all_data("UserLevel")

	if user_levels.is_empty():
		_log("No user data found! Click 'Initialize Data' first.")
		return

	for level_data in user_levels:
		var status = "Locked"
		if level_data.complete:
			status = "Complete"
		elif level_data.unlocked:
			status = "Unlocked"

		_log("Level %d: %s" % [level_data.level_id, status])


func _on_save_pressed() -> void:
	_log("\n=== Saving User Data ===")
	var error = UserDataSystem.save_user_data()
	if error == OK:
		_log("User data saved successfully!")
	else:
		_log("ERROR: Failed to save user data (Error: %d)" % error)


func _on_load_pressed() -> void:
	_log("\n=== Loading User Data ===")

	var user_id = UserDataSystem.current_user_id
	if user_id.is_empty():
		_log("No active user!")
		return

	var error = UserDataSystem.load_user_data(user_id)
	if error == OK:
		_log("User data loaded successfully!")
		_on_check_data_pressed()  # Show loaded data
	else:
		_log("ERROR: Failed to load user data (Error: %d)" % error)


func _on_action_fired(action_type: String, action_data: Dictionary) -> void:
	_log("[ACTION] %s: %s" % [action_type, action_data])


func _log(message: String) -> void:
	output_text += message + "\n"
	output_label.text = output_text

	# Auto-scroll to bottom
	await get_tree().process_frame
	if is_instance_valid($VBox/ScrollContainer):
		$VBox/ScrollContainer.scroll_vertical = 9999
