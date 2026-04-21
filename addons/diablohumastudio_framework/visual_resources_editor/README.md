# Visual Resources Editor

## Description
The Visual Resources Editor is a Godot 4 `@tool` editor plugin designed for visually browsing, creating, bulk-editing, and deleting `.tres` resource files filtered by their script class. It provides a streamlined, tabular interface for managing large numbers of data-driven resources directly within the Godot editor, avoiding the need to manually hunt through the FileSystem dock.

## User Manual
1. **Launch**: Open the plugin from the editor toolbar via **VisualResourcesEditor → Launch Visual Editor**.
2. **Selecting Classes**: Use the top-left **Class Selector** dropdown to filter your project's `.tres` resources by their specific GDScript class.
3. **Subclasses**: Toggle **"Include Subclasses"** to seamlessly show or hide resources that inherit from the currently selected class.
4. **Editing**: 
   - Click on a resource row to select it.
   - Use `Ctrl+Click` to toggle individual selection or `Shift+Click` for range selection.
   - With resources selected, use Godot's built-in **Inspector** panel (on the right side of the editor) to bulk-edit properties across all selected resources simultaneously. Changes are saved automatically.
5. **Creating & Deleting**: 
   - Use the **"Create New"** button in the toolbar to instantiate new resources of the current class type.
   - Use the **"Delete Selected"** button (or the individual trash can icons on each row) to safely move resources to the OS trash.

## Visuals
*(Not implemented yet as we don't have screen captures)*

## Architecture
For a deep dive into the plugin's internal design, data flow, component hierarchy, and signal structures, please refer to the [Architecture Documentation](docs/ARCHITECTURE.md).
