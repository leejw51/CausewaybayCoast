## Client persistence in ~/.causewaybaycoast/client (JSONL): settings.jsonl (last line wins) + chat.jsonl (append).
extends Node

var dir := ""
var data := {"name": "", "url": "", "zoom": 25.0, "muted": false}


func _ready() -> void:
	var home := OS.get_environment("HOME")
	var override_dir := OS.get_environment("COAST_CLIENT_DIR")
	if override_dir != "":
		dir = override_dir
	elif OS.has_feature("web") or home == "":
		dir = "user://causewaybaycoast/client"
	else:
		dir = home.path_join(".causewaybaycoast/client")
	DirAccess.make_dir_recursive_absolute(dir)
	_load()


func _load() -> void:
	var f := FileAccess.open(dir.path_join("settings.jsonl"), FileAccess.READ)
	if f == null:
		return
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var d = JSON.parse_string(line)
		if d is Dictionary:
			for k in d:
				data[k] = d[k]


func _append(file: String, rec: Dictionary) -> void:
	var path := dir.path_join(file)
	var f := (
		FileAccess.open(path, FileAccess.READ_WRITE)
		if FileAccess.file_exists(path)
		else FileAccess.open(path, FileAccess.WRITE)
	)
	if f == null:
		return
	f.seek_end()
	rec["ts"] = Time.get_datetime_string_from_system(true)
	f.store_line(JSON.stringify(rec))


func save() -> void:
	_append("settings.jsonl", data.duplicate())


func log_chat(room_id: int, name: String, text: String) -> void:
	if OS.get_environment("COAST_LOG_CHAT") != "1":
		return
	_append("chat.jsonl", {"room": room_id, "name": name, "text": text})
