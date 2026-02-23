@tool
class_name SuggestionProvider
extends RefCounted

## Abstract base class for autocomplete suggestion providers.
## Subclass and override get_suggestions() and validate() to provide
## domain-specific autocomplete behavior to LineEditAutocomplete.


## Override: return an array of suggestion strings matching the current text.
func get_suggestions(_text: String) -> Array[String]:
	return []


## Override: return true if the given text is considered valid input.
func validate(_text: String) -> bool:
	return true
