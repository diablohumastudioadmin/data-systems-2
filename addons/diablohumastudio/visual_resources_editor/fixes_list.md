# Visual Resources Editor — Fix List

List of ites to fix. Each have creator (if was an ai or me or another programer), severity (low, medium, high, critical), file[s] and line [s], solved (yes/no, not a problem), problem (is the descripttion), fix (the proposed fix by the creator), and correction to fix (done by you)

---

## Items

### 1. Example item

**Creator**: Claude
**Severity**: HIGH
**File**: `core/project_class_scanner.gd` — `get_class_from_tres_file()` lines 89-94
**Solved**: yes 

~~**Problem**: When `ResourceLoader.load()` returns null (corrupt file, missing script), the function silently returns `""`. Resource vanishes from list with no warning.~~

~~**Fix**: Add `push_warning("VRE: Failed to load resource at '%s'" % tres_file_path)` before returning empty.~~

---


