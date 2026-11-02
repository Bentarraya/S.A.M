extends SceneTree

const SUITES: Array = [
	preload("res://tests/layout_test.gd"),
	preload("res://tests/route_test.gd"),
]

func _initialize() -> void:
	var failures := 0
	for suite in SUITES:
		failures += suite.new().run()
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(0 if failures == 0 else 1)
