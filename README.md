# Data Systems Plugin for Godot 4.6

A comprehensive, production-ready data management system for your game. Manages game data, user progress, and event-driven logic through three integrated subsystems.

## ✨ Features

### 🗂️ GameData System
- **Visual Data Type Editor** - Define data schemas (Level, Achievement, Item, etc.)
- **Spreadsheet-Style Instance Editor** - Edit game data in bulk
- **Auto-Generated Resource Classes** - Use custom types in Inspector
- **JSON-Based Storage** - Version control friendly

### 👤 User Data System
- **Multi-User Support** - Multiple save slots
- **Progress Tracking** - Track completion, unlocks, stats
- **Auto-Save** - Periodic saves + save on quit
- **Fluent Query API** - Clean, readable data access

### ⚡ Actions System
- **Event-Driven Architecture** - Decouple game logic from data
- **Configurable Handlers** - Modify behavior via JSON
- **Achievement Integration** - Built-in condition support
- **Signal Broadcasting** - React to game events

## 🚀 Quick Start

### 1. Enable the Plugin

1. Open Godot
2. Go to **Project → Project Settings → Plugins**
3. Enable **"Data Systems"**

### 2. Run the Demo

1. Open `demo.tscn`
2. Click Play (F6)
3. Follow the button prompts to see the system in action

### 3. Open Data Editors

Access via **Window** menu (top menu bar):
- **Data Type Editor** - Define your data types
- **Data Instance Editor** - Edit your game data

### 4. Read the Guide

Open [`DATA_SYSTEMS_GUIDE.md`](./DATA_SYSTEMS_GUIDE.md) for complete documentation.

## 📁 Project Structure

```
data-systems-2/
├── addons/diablohumastudio/          # 📦 Plugin (do not modify manually)
│   ├── plugin.gd                 # Main plugin entry point
│   ├── core/                     # Core utilities
│   ├── game_data/              # GameData System
│   │   ├── ui/                   # Visual editors
│   │   └── resources/            # Generated Resource classes (auto-created)
│   ├── user_data/                # User Data System
│   └── actions/                  # Actions System
│
├── data/                         # 📊 Your Game Data (edit these!)
│   ├── game_data_types.json    # Data type definitions
│   ├── level.json                # Example: Level data
│   ├── achievement.json          # Example: Achievement data
│   └── actions.json              # Action handler configurations
│
├── demo.tscn                     # 🎮 Interactive demo scene
├── demo.gd                       # Demo script
├── README.md                     # This file
└── DATA_SYSTEMS_GUIDE.md         # Complete documentation

User data saved to: user://data_systems/
```

## 💡 Example Usage

### Define a Data Type

1. **Window → Data Type Editor**
2. Click "New Type"
3. Set name: `Level`
4. Add properties:
   - `id` (int)
   - `name` (String)
   - `difficulty` (int)
5. Click "Save Type"

### Add Game Data

1. **Window → Data Instance Editor**
2. Select `Level` from dropdown
3. Click "Add Instance"
4. Fill in values: `id=1, name="Tutorial", difficulty=1`
5. Click "Save"

### Use in Game Code

```gdscript
extends Node2D

func _ready():
    # Create user
    UserDataSystem.create_user("Player1")

    # Initialize user progress
    UserDataSystem.add_data("UserLevel", {
        "level_id": 1,
        "unlocked": true,
        "complete": false
    })

func _on_level_complete():
    # Dispatch action instead of modifying data directly
    ActionsSystem.dispatch("level_completed", {
        "level_id": 1
    })

    # Data is automatically updated by action handlers!
```

### Check User Progress

```gdscript
# Fluent API
if UserDataSystem.queries.get_user_level_by_id(1).is_complete():
    print("Level 1 completed!")

# Direct access
var level_data = UserDataSystem.get_data("UserLevel", "level_id", 1)
print(level_data.complete)  # true/false
```

## 🎯 Key Concepts

### GameData vs User Data

- **GameData**: Game content (levels, items, enemies) - same for all players
- **User Data**: Player progress (unlocks, completion, stats) - unique per player

### Actions System Benefits

Instead of:
```gdscript
# ❌ Tightly coupled, hard to maintain
UserDataSystem.set_data_property("UserLevel", "level_id", 1, "complete", true)
UserDataSystem.set_data_property("PlayerStats", "stat_id", 1, "levels_completed", levels + 1)
check_achievement_conditions()
update_ui()
```

You write:
```gdscript
# ✅ Clean, decoupled, maintainable
ActionsSystem.dispatch("level_completed", {"level_id": 1})
```

The Actions System handles:
- Updating user data
- Checking achievements
- Broadcasting to UI
- All configured in JSON (no code changes needed!)

## 📚 Documentation

- **[DATA_SYSTEMS_GUIDE.md](./DATA_SYSTEMS_GUIDE.md)** - Complete user guide
- **[Implementation Plan](/.claude/plans/stateless-chasing-thunder.md)** - Technical architecture

## 🛠️ What's Implemented

✅ **Core Foundation**
- Plugin system with editor integration
- Data type definition system
- JSON persistence layer
- Resource class generation

✅ **GameData System**
- Visual data type editor
- Spreadsheet-style instance editor
- Auto-generated custom Resources
- Bulk editing support

✅ **User Data System**
- Multi-user management
- Progress tracking
- Auto-save system
- Fluent query API

✅ **Actions System**
- Action dispatcher
- Direct data handlers
- Notification handlers
- JSON configuration

✅ **Examples & Documentation**
- Interactive demo scene
- Example data types (Level, Achievement, UserLevel)
- Complete usage guide
- Code examples

## 🔮 Future Enhancements

The following features are designed but not yet implemented (you can add them as needed):

- **Visual Action Editor** - GUI for configuring action handlers
- **Achievement System** - Built-in multi-condition achievement tracking
- **Visual Achievement Editor** - Drag-drop condition builder
- **Undo/Redo** - For data editors
- **Data Validation** - Custom validation rules
- **Import/Export** - CSV, Excel support

## 🤝 Usage Tips

1. **Always use actions for game events** - Keeps code clean and maintainable
2. **Initialize user data on first run** - Create default progress data
3. **Use custom Resources in scenes** - Drag-drop data in Inspector
4. **Save periodically** - Auto-save is enabled by default
5. **Test with multiple users** - Verify save/load works correctly

## ⚠️ Important Notes

- **Enable the plugin first** in Project Settings → Plugins
- **Don't modify** files in `addons/diablohumastudio/` directly
- **Edit data** in `data/` folder or via the visual editors
- **Generated Resources** are created in `addons/diablohumastudio/game_data/resources/`
- **User save files** are stored in `user://data_systems/`

## 🎮 Try It Now!

1. Enable the plugin
2. Open `demo.tscn`
3. Click Play (F6)
4. Click the buttons to see the system in action!

## 📖 Next Steps

1. Read [`DATA_SYSTEMS_GUIDE.md`](./DATA_SYSTEMS_GUIDE.md)
2. Open the Data Type Editor and create your types
3. Add your game data in the Data Instance Editor
4. Configure actions in `data/actions.json`
5. Start building your game!

---

**Built for Godot 4.6** | **Plugin Version 1.0.0**

Happy game developing! 🚀
