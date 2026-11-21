class_name NetCodec
extends RefCounted
## Wire format for the Apex GP league core (Phase 3). Little-endian binary,
## hand-rolled quantization so bandwidth stays tiny for mobile targets.
##
## Channel split (ENet):
##   channel 0 - unreliable, time-critical: INPUT, SNAPSHOT, ACK, PING, PONG
##   channel 1 - reliable, ordered:        HELLO, WELCOME, PLAYER_LIST,
##                                         START, FINISHED
##
## All packets start with a u8 message id. See docs/ARCHITECTURE.md (Phase 3)
## for the byte budgets; measurement lives in the net test driver.

const PROTOCOL_VERSION := 3
const DEFAULT_PORT := 24565
const TICK_RATE := 120.0
const SNAPSHOT_HZ := 20.0
const INPUT_HZ := 30.0
const MAX_PLAYERS := 8
const SNAPSHOT_EVERY_TICKS := 6  # 120 / 20 Hz
const RECONNECT_GRACE_S := 30.0
const MAX_NAME_LEN := 24

# C2S
const MSG_HELLO := 0x01
const MSG_INPUT := 0x10
const MSG_READY := 0x11
const MSG_PING := 0x40
# S2C
const MSG_WELCOME := 0x02
const MSG_PLAYER_LIST := 0x03
const MSG_START := 0x04
const MSG_FINISHED := 0x05
const MSG_SNAPSHOT := 0x20
const MSG_ACK := 0x30
const MSG_PONG := 0x41

# input flag bits
const FLAG_NITRO := 1
const FLAG_SHIFT_UP := 2
const FLAG_SHIFT_DOWN := 4
const FLAG_DRS := 8
# snapshot car flag bits
const CARF_DRS := 1
const CARF_FINISHED := 2
const CARF_AI := 4
const CARF_HUMAN := 8

const ANGLE_SCALE := 32767.0 / PI  # radians -> s16
const VEL_SCALE := 1000.0  # m/s -> mm/s, clamped to s16 range
const VEL_MAX := 32.767
const PROG_UNKNOWN := 0xFFFF


static func put_pstr(buf: StreamPeerBuffer, s: String) -> void:
	var data := s.to_utf8_buffer()
	data.resize(mini(data.size(), MAX_NAME_LEN * 4))
	buf.put_u8(data.size())
	buf.put_data(data)


static func get_pstr(buf: StreamPeerBuffer) -> String:
	var length := buf.get_u8()
	if length == 0:
		return ""
	var data := buf.get_data(length)
	return (data[1] as PackedByteArray).get_string_from_utf8()


# ---------------------------------------------------------------- inputs


## Quantized driver input. Client sends 8 bytes at INPUT_HZ; the server
## clamps and stores the dequantized value, so prediction and authority
## always simulate the exact same numbers.
static func encode_input(seq: int, input: Dictionary) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_INPUT)
	buf.put_u32(seq)
	buf.put_u8(int(round(clampf(float(input.get("throttle", 0.0)), 0.0, 1.0) * 255.0)))
	buf.put_u8(int(round(clampf(float(input.get("brake", 0.0)), 0.0, 1.0) * 255.0)))
	buf.put_8(int(round(clampf(float(input.get("steer", 0.0)), -1.0, 1.0) * 127.0)))
	var flags := 0
	if bool(input.get("nitro", false)):
		flags |= FLAG_NITRO
	if bool(input.get("shift_up", false)):
		flags |= FLAG_SHIFT_UP
	if bool(input.get("shift_down", false)):
		flags |= FLAG_SHIFT_DOWN
	if bool(input.get("drs", false)):
		flags |= FLAG_DRS
	buf.put_u8(flags)
	return buf.data_array


## Returns {seq, throttle, brake, steer, nitro, shift_up, shift_down, drs}.
static func decode_input(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	var seq := buf.get_u32()
	var input := {
		"seq": seq,
		"throttle": float(buf.get_u8()) / 255.0,
		"brake": float(buf.get_u8()) / 255.0,
		"steer": float(buf.get_8()) / 127.0,
	}
	var flags := buf.get_u8()
	input["nitro"] = (flags & FLAG_NITRO) != 0
	input["shift_up"] = (flags & FLAG_SHIFT_UP) != 0
	input["shift_down"] = (flags & FLAG_SHIFT_DOWN) != 0
	input["drs"] = (flags & FLAG_DRS) != 0
	return input


## Server-side safety net: force ranges/types on any decoded input before it
## reaches the physics. Impossible values are clamped, not rejected (a driver
## with a stuck key must not lose control authority).
static func sanitize_input(input: Dictionary) -> Dictionary:
	return {
		"seq": int(input.get("seq", 0)),
		"throttle": clampf(float(input.get("throttle", 0.0)), 0.0, 1.0),
		"brake": clampf(float(input.get("brake", 0.0)), 0.0, 1.0),
		"steer": clampf(float(input.get("steer", 0.0)), -1.0, 1.0),
		"nitro": bool(input.get("nitro", false)),
		"shift_up": bool(input.get("shift_up", false)),
		"shift_down": bool(input.get("shift_down", false)),
		"drs": bool(input.get("drs", false)),
	}


# ---------------------------------------------------------------- snapshots


## Snapshot car state. pos/vel are world-space; angles are body Euler in
## radians; progress is the lap fraction (-1 unknown); race_pos is 1-based.
static func encode_snapshot(tick: int, states: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_SNAPSHOT)
	buf.put_u32(tick)
	buf.put_u8(states.size())
	for state: Dictionary in states:
		var pos: Vector3 = state.get("pos", Vector3.ZERO)
		buf.put_float(pos.x)
		buf.put_float(pos.y)
		buf.put_float(pos.z)
		for angle in [state.get("yaw", 0.0), state.get("pitch", 0.0), state.get("roll", 0.0)]:
			buf.put_16(int(round(clampf(float(angle), -PI, PI) * ANGLE_SCALE)))
		var vel: Vector3 = state.get("vel", Vector3.ZERO)
		for axis in [vel.x, vel.y, vel.z]:
			buf.put_16(int(round(clampf(float(axis), -VEL_MAX, VEL_MAX) * VEL_SCALE)))
		var flags := 0
		if bool(state.get("drs_active", false)):
			flags |= CARF_DRS
		if bool(state.get("finished", false)):
			flags |= CARF_FINISHED
		if bool(state.get("ai", false)):
			flags |= CARF_AI
		if bool(state.get("human", false)):
			flags |= CARF_HUMAN
		buf.put_u8(flags)
		var progress := float(state.get("progress", -1.0))
		if progress < 0.0:
			buf.put_u16(PROG_UNKNOWN)
		else:
			buf.put_u16(int(round(clampf(progress, 0.0, 1.0) * 65535.0)))
		buf.put_u8(clampi(int(state.get("laps", 0)), 0, 255))
		buf.put_u8(clampi(int(state.get("race_pos", 1)), 1, 255))
	return buf.data_array


static func decode_snapshot(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	var tick := buf.get_u32()
	var count := buf.get_u8()
	var cars: Array = []
	for i in range(count):
		var pos := Vector3(buf.get_float(), buf.get_float(), buf.get_float())
		var yaw := float(buf.get_16()) / ANGLE_SCALE
		var pitch := float(buf.get_16()) / ANGLE_SCALE
		var roll := float(buf.get_16()) / ANGLE_SCALE
		var vel := Vector3(
			float(buf.get_16()) / VEL_SCALE,
			float(buf.get_16()) / VEL_SCALE,
			float(buf.get_16()) / VEL_SCALE
		)
		var flags := buf.get_u8()
		var raw_prog := buf.get_u16()
		(
			cars
			. append(
				{
					"pos": pos,
					"yaw": yaw,
					"pitch": pitch,
					"roll": roll,
					"vel": vel,
					"drs_active": (flags & CARF_DRS) != 0,
					"finished": (flags & CARF_FINISHED) != 0,
					"ai": (flags & CARF_AI) != 0,
					"human": (flags & CARF_HUMAN) != 0,
					"progress": -1.0 if raw_prog == PROG_UNKNOWN else float(raw_prog) / 65535.0,
					"laps": buf.get_u8(),
					"race_pos": buf.get_u8(),
				}
			)
		)
	return {"tick": tick, "cars": cars}


# ---------------------------------------------------------------- lobby


static func encode_hello(proto: int, token: int, name: String) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_HELLO)
	buf.put_u16(proto)
	buf.put_u32(token)
	put_pstr(buf, name)
	return buf.data_array


static func decode_hello(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	return {"proto": buf.get_u16(), "token": buf.get_u32(), "name": get_pstr(buf)}


static func encode_welcome(
	slot: int, token: int, seed: int, laps: int, track_name: String
) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_WELCOME)
	buf.put_u8(slot)
	buf.put_u32(token)
	buf.put_u32(seed)
	buf.put_u8(laps)
	put_pstr(buf, track_name)
	return buf.data_array


static func decode_welcome(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	var slot := buf.get_u8()
	var token := buf.get_u32()
	var seed := buf.get_u32()
	var laps := buf.get_u8()
	var track := get_pstr(buf)
	return {"slot": slot, "token": token, "seed": seed, "laps": laps, "track": track}


## players: Array of {slot, name, ready}
static func encode_player_list(players: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_PLAYER_LIST)
	buf.put_u8(players.size())
	for player: Dictionary in players:
		buf.put_u8(int(player.get("slot", 0)))
		buf.put_u8(1 if bool(player.get("ready", false)) else 0)
		put_pstr(buf, str(player.get("name", "")))
	return buf.data_array


static func decode_player_list(data: PackedByteArray) -> Array:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	var count := buf.get_u8()
	var players: Array = []
	for i in range(count):
		var slot := buf.get_u8()
		var ready := buf.get_u8() == 1
		players.append({"slot": slot, "ready": ready, "name": get_pstr(buf)})
	return players


static func encode_start(seed: int, laps: int, car_count: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_START)
	buf.put_u32(seed)
	buf.put_u8(laps)
	buf.put_u8(car_count)
	return buf.data_array


static func decode_start(data: PackedByteArray) -> Dictionary:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	return {"seed": buf.get_u32(), "laps": buf.get_u8(), "car_count": buf.get_u8()}


## classification: Array of {slot, position, laps, best_lap, finish_time}
static func encode_finished(classification: Array) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_FINISHED)
	buf.put_u8(classification.size())
	for entry: Dictionary in classification:
		buf.put_u8(int(entry.get("slot", 0)))
		buf.put_u8(int(entry.get("position", 0)))
		buf.put_u8(int(entry.get("laps", 0)))
		buf.put_float(float(entry.get("best_lap", -1.0)))
		buf.put_float(float(entry.get("finish_time", -1.0)))
	return buf.data_array


static func decode_finished(data: PackedByteArray) -> Array:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	var count := buf.get_u8()
	var out: Array = []
	for i in range(count):
		(
			out
			. append(
				{
					"slot": buf.get_u8(),
					"position": buf.get_u8(),
					"laps": buf.get_u8(),
					"best_lap": buf.get_float(),
					"finish_time": buf.get_float(),
				}
			)
		)
	return out


static func encode_ack(last_seq: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_ACK)
	buf.put_u32(last_seq)
	return buf.data_array


static func decode_ack(data: PackedByteArray) -> int:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	return buf.get_u32()


## C2S reliable: driver toggles readiness in the lobby.
static func encode_ready(ready: bool) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_READY)
	buf.put_u8(1 if ready else 0)
	return buf.data_array


static func decode_ready(data: PackedByteArray) -> bool:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	return buf.get_u8() == 1


static func encode_ping(time_ms: int) -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u8(MSG_PING)
	buf.put_u32(time_ms)
	return buf.data_array


static func decode_ping(data: PackedByteArray) -> int:
	var buf := StreamPeerBuffer.new()
	buf.data_array = data
	buf.seek(1)
	return buf.get_u32()
