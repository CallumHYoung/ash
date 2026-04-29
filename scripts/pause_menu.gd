extends CanvasLayer

const DEFAULT_VOLUME: float = 0.7

@onready var resume_button: Button = $Panel/VBox/ResumeButton
@onready var exit_button: Button = $Panel/VBox/ExitButton
@onready var volume_slider: HSlider = $Panel/VBox/VolumeSlider


func _ready() -> void:
	visible = false
	resume_button.pressed.connect(_resume)
	exit_button.pressed.connect(get_tree().quit)
	volume_slider.value = DEFAULT_VOLUME
	volume_slider.value_changed.connect(_on_volume_changed)
	_on_volume_changed(DEFAULT_VOLUME)


func _on_volume_changed(v: float) -> void:
	# Drive the master bus so future SFX scale with the same slider. Mute below
	# the floor instead of feeding -inf dB to the audio server.
	var bus := AudioServer.get_bus_index("Master")
	AudioServer.set_bus_mute(bus, v <= 0.0)
	if v > 0.0:
		AudioServer.set_bus_volume_db(bus, linear_to_db(v))


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if get_tree().paused:
			_resume()
		else:
			_pause()
		get_viewport().set_input_as_handled()


func _pause() -> void:
	visible = true
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _resume() -> void:
	visible = false
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
