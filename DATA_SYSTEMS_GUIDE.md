# Data Systems Plugin - User Guide

A comprehensive data management system for Godot 4.6 games with three core subsystems:
- **GameData System**: CRUD for game data types and instances
- **User Data System**: User progress, preferences, and persistence
- **Actions System**: Event-driven system for decoupled game logic

## Installation

1. The plugin is located in `addons/diablohumastudio/`
2. Enable it in Project → Project Settings → Plugins
3. The following autoloads are registered automatically:
   - `UserDataSystem` - User data management
   - `ActionsSystem` - Action/event handling

## Quick Start

### 1. Enable the Plugin

Go to **Project Settings → Plugins** and enable "Data Systems".

### 2. Open Data Editors

Access the data editors via **Window Menu** (top menu bar):
- **Data Type Editor** - Define master and user data types
- **Data Instance Editor** - Edit data instances in a spreadsheet view
- **Action Editor** - Configure action handlers (coming soon)

### 3. Define Data Types

**GameData** - Game content (levels, items, achievements):
```
Type: Level
Properties:
  - id: int = 0
  - name: String = ""
  - difficulty: int = 1
  - unlocked_by_default: bool = false
```

**User Data** - Player progress:
```
Type: UserLevel
Properties:
  - level_id: int = 0
  - unlocked: bool = false
  - complete: bool = false
  - best_time: float = 0.0
```

### 4. Add Data Instances

Use the **Data Instance Editor** to add level data:
- Select data type from dropdown
- Click "Add Instance"
- Edit values in the table
- Click "Save"

### 5. Use in Game Code

#### User Management
```gdscript
# Create a new user
var user_id = UserDataSystem.create_user("PlayerName")

# Switch active user
UserDataSystem.set_active_user(user_id)

# Save/Load
UserDataSystem.save_user_data()
UserDataSystem.load_user_data(user_id)
```

#### Access User Data
```gdscript
# Get specific data instance
var level_data = UserDataSystem.get_data("UserLevel", "level_id", 1)
print(level_data.complete)  # false

# Update data
UserDataSystem.set_data_property("UserLevel", "level_id", 1, "complete", true)

# Using fluent query API
UserDataSystem.queries.get_user_level_by_id(1).set_complete(true)
UserDataSystem.queries.get_user_level_by_id(1).set_unlocked(true)
```

#### Dispatch Actions
```gdscript
# In your game code, dispatch actions instead of directly modifying data
func _on_level_complete():
    ActionsSystem.dispatch("level_completed", {
        "level_id": current_level.id,
        "time": completion_time,
        "no_deaths": player.deaths == 0
    })

# The Actions System will:
# 1. Execute registered handlers (update UserLevel data)
# 2. Check achievements
# 3. Broadcast signals for UI updates
```

#### Listen to Actions
```gdscript
# In UI or game objects
func _ready():
    ActionsSystem.on_action("level_completed").connect(_on_level_completed_action)

func _on_level_completed_action(action_type: String, data: Dictionary):
    if action_type == "level_completed":
        show_completion_screen(data)
```

## System Architecture

### GameData System

**Purpose**: Manage game content (levels, items, achievements, enemies, etc.)

**Key Classes**:
- `GameDataSystem` - Core system
- `DataTypeRegistry` - Type definitions
- `DataTypeDefinition` - Schema for data types
- `ResourceGenerator` - Creates custom Resource classes

**File Storage**: `res://data/`
- `game_data_types.json` - Type definitions
- `level.json`, `achievement.json`, etc. - Data instances

**Generated Resources**:
Each master data type generates a GDScript Resource class in `addons/diablohumastudio/game_data/resources/`.
You can use these in the Inspector:

```gdscript
extends Node2D

@export var level: Level  # Assign in inspector!

func _ready():
    print(level.name)
    print(level.difficulty)
```

### User Data System

**Purpose**: Manage user accounts, progress, and save games

**Key Classes**:
- `UserDataSystem` - Main singleton (autoload)
- `UserManager` - User CRUD operations
- `UserDataManager` - User-specific data instances
- `PersistenceManager` - Save/load system
- `UserDataQueries` - Fluent query API

**File Storage**: `user://data_systems/`
- `users.json` - User accounts
- `saves/{user_id}/data.json` - User data per user

**Auto-Save**: Enabled by default (5-minute interval, saves on quit)

### Actions System

**Purpose**: Decouple game events from data modifications

**Key Classes**:
- `ActionsSystem` - Main singleton (autoload)
- `ActionDispatcher` - Routes actions to handlers
- `ActionRegistry` - Configuration management
- `ActionHandler` - Base handler class
- `DirectDataHandler` - Modifies user data
- `NotificationHandler` - Broadcasts signals

**File Storage**: `res://data/actions.json` - Action configurations

**Benefits**:
- Decouple game code from data system
- Easy to add/modify game logic without code changes
- Achievements automatically track actions
- UI components can listen to actions

## Example: Complete Game Flow

```gdscript
# game.gd - Main game script

extends Node

func _ready():
    # Initialize user if needed
    if UserDataSystem.user_manager.get_user_count() == 0:
        UserDataSystem.create_user("Player1")

    # Initialize user levels from master data
    _initialize_user_levels()

func _initialize_user_levels():
    # Get all level master data
    var game_data_system = GameDataSystem.new()
    var levels = game_data_system.get_instances("Level")

    # Create user level data for each
    for level in levels:
        var user_level = {
            "level_id": level.id,
            "unlocked": level.unlocked_by_default,
            "complete": false,
            "completed_no_deaths": false,
            "best_time": 0.0
        }
        UserDataSystem.add_data("UserLevel", user_level)

    # Save
    UserDataSystem.save_user_data()

# level.gd - Individual level script

extends Node2D

@export var level_id: int = 1
var completion_time: float = 0.0

func _on_level_complete():
    # Dispatch action - don't modify data directly!
    ActionsSystem.dispatch("level_completed", {
        "level_id": level_id,
        "time": completion_time,
        "no_deaths": $Player.deaths == 0
    })

    # Unlock next level
    ActionsSystem.dispatch("level_unlocked", {
        "level_id": level_id + 1
    })

# achievement_ui.gd - Achievement notification

extends Control

func _ready():
    ActionsSystem.on_action("achievement_unlocked").connect(_show_achievement)

func _show_achievement(action_type: String, data: Dictionary):
    if action_type == "achievement_unlocked":
        var achievement_id = data.get("achievement_id")
        # Show notification popup
        $AnimationPlayer.play("show_achievement")
```

## Configuring Actions (JSON)

Create action handlers in `res://data/actions.json`:

```json
{
  "version": 1,
  "actions": {
    "level_completed": {
      "handlers": [
        {
          "type": "direct_data",
          "name": "Mark Level Complete",
          "enabled": true,
          "data_type": "UserLevel",
          "property_to_match": "level_id",
          "property_source": "level_id",
          "properties_to_set": {
            "complete": true,
            "best_time": "$time",
            "completed_no_deaths": "$no_deaths"
          }
        },
        {
          "type": "notification",
          "name": "Notify UI",
          "enabled": true,
          "notification_type": "level_completed"
        }
      ]
    },
    "level_unlocked": {
      "handlers": [
        {
          "type": "direct_data",
          "name": "Unlock Level",
          "enabled": true,
          "data_type": "UserLevel",
          "property_to_match": "level_id",
          "property_source": "level_id",
          "properties_to_set": {
            "unlocked": true
          }
        }
      ]
    }
  }
}
```

## Tips & Best Practices

### 1. Always Use Actions for Game Events
```gdscript
# ❌ DON'T modify user data directly in game code
UserDataSystem.queries.get_user_level_by_id(1).set_complete(true)

# ✅ DO dispatch actions
ActionsSystem.dispatch("level_completed", {"level_id": 1})
```

### 2. Initialize User Data on First Run
```gdscript
func _ready():
    if UserDataSystem.get_all_data("UserLevel").is_empty():
        _initialize_default_user_data()
```

### 3. Use Custom Resources in Scenes
```gdscript
# Level scene script
@export var level_data: Level  # Assign in inspector

func _ready():
    $Label.text = level_data.name
    print("Difficulty: %d" % level_data.difficulty)
```

### 4. Save Periodically
```gdscript
# Auto-save is enabled by default (5 min interval)
# Manual save:
UserDataSystem.save_user_data()

# Adjust auto-save interval:
UserDataSystem.persistence_manager.set_auto_save(true, 180.0)  # 3 minutes
```

### 5. Handle Multiple Users
```gdscript
# Create multiple users
UserDataSystem.create_user("Player1")
UserDataSystem.create_user("Player2")

# Switch between users
UserDataSystem.set_active_user("user_12345")
```

## File Structure

```
project/
├── addons/diablohumastudio/          # Plugin files
│   ├── plugin.gd                 # Main plugin
│   ├── core/                     # Core utilities
│   ├── game_data/              # GameData System
│   │   ├── ui/                   # Visual editors
│   │   └── resources/            # Generated Resource classes
│   ├── user_data/                # User Data System
│   │   └── api/                  # Query API
│   └── actions/                  # Actions System
│       └── handlers/             # Action handlers
└── data/                         # Data storage
    ├── game_data_types.json    # Type schemas
    ├── level.json                # Level data
    ├── achievement.json          # Achievement data
    └── actions.json              # Action configurations
```

## Troubleshooting

### Data not persisting
- Check that UserDataSystem.save_user_data() is being called
- Verify user://data_systems/ directory exists
- Enable auto-save: `UserDataSystem.persistence_manager.set_auto_save(true)`

### Actions not firing
- Verify ActionsSystem is initialized (check Output console)
- Check actions.json syntax
- Ensure handler type matches (direct_data, notification)

### Type not found errors
- Regenerate resources: Open Data Type Editor and re-save types
- Check that type_name matches between definition and usage
- Verify game_data_types.json syntax

## Advanced: Custom Action Handlers

Create custom handlers by extending `ActionHandler`:

```gdscript
# custom_handler.gd
extends ActionHandler

func handle(action_data: Dictionary) -> void:
    # Custom logic here
    var level_id = action_data.get("level_id")
    print("Custom handler for level: %d" % level_id)

    # Access UserDataSystem
    var user_data = get_node("/root/UserDataSystem")
    # ... modify data as needed
```

Register in code:
```gdscript
var custom_handler = preload("res://custom_handler.gd").new()
ActionsSystem.register_handler("level_completed", custom_handler)
```

## Next Steps

1. Open **Data Type Editor** and create your data types
2. Open **Data Instance Editor** and add game content
3. Create custom Resource scripts (auto-generated)
4. Use Resources in your scenes
5. Dispatch actions from game code
6. Configure action handlers in actions.json
7. Test save/load functionality

Happy game developing! 🎮
