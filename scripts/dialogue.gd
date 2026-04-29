extends CanvasLayer

# Slow, one-sentence-at-a-time NPC ramble. Each sentence types out, then a
# short pause before auto-advancing. Pressing "interact" while typing fast-
# forwards the current sentence; pressing it during the pause skips to the
# next sentence. Non-blocking — the player can still move during dialogue.

const SENTENCES: Array[String] = [
	"You're really going down there?",
	"Most don't come back.",
	"Some come back wrong.",
	"I've seen what they bring up.",
	"Cold things. Wet things. Things with too many joints.",
	"There are voices down there that sound like home.",
	"Don't answer them.",
	"There's a light at the bottom.",
	"It's not the kind of light you want to find.",
	"Take your rope. Cut it before they grab on.",
	"Good luck, friend.",
]

const TYPE_SPEED: float = 22.0
const POST_SENTENCE_PAUSE: float = 1.6

enum {STATE_TYPING, STATE_PAUSING}

@onready var prompt: Label = $Prompt
@onready var box: Panel = $Box
@onready var text_label: Label = $Box/Text

var _player_in_range: bool = false
var _talking: bool = false
var _sentence_index: int = 0
var _typewriter_progress: float = 0.0
var _pause_timer: float = 0.0
var _state: int = STATE_TYPING


func _ready() -> void:
	box.visible = false
	prompt.visible = false


func _on_npc_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		_player_in_range = true
		_refresh_prompt()


func _on_npc_body_exited(body: Node) -> void:
	if body is CharacterBody3D:
		_player_in_range = false
		_refresh_prompt()


func _refresh_prompt() -> void:
	prompt.visible = _player_in_range and not _talking


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("interact"):
		return
	if _talking:
		if _state == STATE_TYPING:
			_typewriter_progress = float(SENTENCES[_sentence_index].length())
			_update_text()
			_state = STATE_PAUSING
			_pause_timer = POST_SENTENCE_PAUSE
		else:
			_advance_sentence()
		get_viewport().set_input_as_handled()
	elif _player_in_range:
		_start()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if not _talking:
		return
	if _state == STATE_TYPING:
		var sentence: String = SENTENCES[_sentence_index]
		_typewriter_progress += TYPE_SPEED * delta
		if _typewriter_progress >= float(sentence.length()):
			_typewriter_progress = float(sentence.length())
			_state = STATE_PAUSING
			_pause_timer = POST_SENTENCE_PAUSE
		_update_text()
	else:
		_pause_timer -= delta
		if _pause_timer <= 0.0:
			_advance_sentence()


func _start() -> void:
	_talking = true
	_sentence_index = 0
	_typewriter_progress = 0.0
	_state = STATE_TYPING
	box.visible = true
	_refresh_prompt()
	_update_text()


func _advance_sentence() -> void:
	_sentence_index += 1
	if _sentence_index >= SENTENCES.size():
		_stop()
		return
	_typewriter_progress = 0.0
	_state = STATE_TYPING
	_update_text()


func _stop() -> void:
	_talking = false
	box.visible = false
	text_label.text = ""
	_refresh_prompt()


func _update_text() -> void:
	text_label.text = SENTENCES[_sentence_index].substr(0, int(_typewriter_progress))
