class_name NetPeer
extends RefCounted
## Thin wrapper over a raw ENetMultiplayerPeer (no high-level MultiplayerAPI):
## we own the poll loop, reliability channels and target routing ourselves.
## This keeps the protocol testable in-process (server + N clients in one
## headless SceneTree) and makes bandwidth measurable per packet type.
##
## Channel 0 = unreliable (INPUT / SNAPSHOT / ACK / PING / PONG),
## channel 1 = reliable ordered (HELLO / WELCOME / PLAYER_LIST / START /
## FINISHED). See NetCodec header comment.

signal packet_received(data: PackedByteArray, channel: int)
signal remote_connected(id: int)
signal remote_disconnected(id: int)
signal connected_to_host
signal connect_failed
signal host_disconnected

const CH_UNRELIABLE := 0
const CH_RELIABLE := 1

var peer: ENetMultiplayerPeer = null
var is_host := false
var last_error: int = OK

var _was_connected := false


func host_server(port: int, max_clients: int) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	last_error = peer.create_server(port, max_clients)
	if last_error != OK:
		peer = null
		return last_error
	is_host = true
	_wire_signals()
	return OK


func connect_to_host(address: String, port: int) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	last_error = peer.create_client(address, port)
	if last_error != OK:
		peer = null
		return last_error
	is_host = false
	_wire_signals()
	return OK


func close() -> void:
	if peer != null:
		peer.close()
		peer = null
	is_host = false
	_was_connected = false


func is_active() -> bool:
	return peer != null


func my_id() -> int:
	if peer == null:
		return 0
	return peer.get_unique_id()


func poll() -> void:
	if peer == null:
		return
	peer.poll()
	if not is_host:
		var status := peer.get_connection_status()
		if status == MultiplayerPeer.CONNECTION_CONNECTED and not _was_connected:
			_was_connected = true
			connected_to_host.emit()
		elif status == MultiplayerPeer.CONNECTION_DISCONNECTED and _was_connected:
			_was_connected = false
			host_disconnected.emit()


## Server: broadcast to everyone (target 0). Client: send to the server.
func send(data: PackedByteArray, reliable: bool) -> void:
	_send_to(0, data, reliable)


func send_to(id: int, data: PackedByteArray, reliable: bool) -> void:
	_send_to(id, data, reliable)


func _send_to(target: int, data: PackedByteArray, reliable: bool) -> void:
	if peer == null or data.is_empty():
		return
	peer.set_target_peer(target)
	peer.set_transfer_channel(CH_RELIABLE if reliable else CH_UNRELIABLE)
	peer.set_transfer_mode(
		(
			MultiplayerPeer.TRANSFER_MODE_RELIABLE
			if reliable
			else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE
		)
	)
	peer.put_packet(data)


func drain_packets() -> void:
	if peer == null:
		return
	while peer.get_available_packet_count() > 0:
		var data := peer.get_packet()
		packet_received.emit(data, peer.get_packet_channel())


func _wire_signals() -> void:
	peer.peer_connected.connect(func(id: int) -> void: remote_connected.emit(id))
	peer.peer_disconnected.connect(func(id: int) -> void: remote_disconnected.emit(id))
	peer.server_disconnected.connect(func() -> void: host_disconnected.emit())
