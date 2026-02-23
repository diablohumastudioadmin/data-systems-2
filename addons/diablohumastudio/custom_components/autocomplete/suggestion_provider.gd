@tool
class_name SuggestionProvider
extends RefCounted

## Abstract base class for autocomplete suggestion providers.
## Subclass and override get_suggestions() and validate() to provide
## domain-specific autocomplete behavior to LineEditAutocomplete.


## Override: return an array of suggestion strings matching the current text.
func get_suggestions(_text: String) -> Array[String]:
	return []


## Override: return empty string if valid, or an error message if invalid.
func validate(_text: String) -> String:
	return ""
