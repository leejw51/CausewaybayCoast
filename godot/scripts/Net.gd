## WebSocket client: JSON envelopes in, Dictionaries out.
extends Node

signal connected
signal disconnected
signal message(msg: Dictionary)

const DEFAULT_URL := "ws://127.0.0.1:8787/ws"

var ws := WebSocketPeer.new()
var url := DEFAULT_URL
var player_id := -1
var _was_open := false
var _connecting := false
var _connect_time := 0.0


func open(u: String = "") -> void:
	if u != "":
		url = u
	ws.close()
	ws = WebSocketPeer.new()
	_was_open = false
	_connecting = true
	_connect_time = 0.0
	var err := ws.connect_to_url(url)
	if err != OK:
		_connecting = false
		disconnected.emit()


func is_open() -> bool:
	return ws.get_ready_state() == WebSocketPeer.STATE_OPEN


func send(d: Dictionary) -> void:
	if is_open():
		ws.send_text(JSON.stringify(d))


func _process(delta: float) -> void:
	if _connecting:
		_connect_time += delta
		if _connect_time > 8.0:
			_connecting = false
			ws.close()
			disconnected.emit()
			return
	ws.poll()
	var st := ws.get_ready_state()
	if st == WebSocketPeer.STATE_OPEN:
		if not _was_open:
			_connecting = false
			_was_open = true
			connected.emit()
		while ws.get_available_packet_count() > 0:
			var txt := ws.get_packet().get_string_from_utf8()
			var d = JSON.parse_string(txt)
			if d is Dictionary:
				message.emit(d)
	elif st == WebSocketPeer.STATE_CLOSED:
		if _was_open or _connecting:
			_connecting = false
			_was_open = false
			disconnected.emit()
