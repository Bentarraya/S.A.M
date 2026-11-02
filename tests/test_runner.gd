extends SceneTree

const SUITES: Array = [
	preload("res://tests/layout_test.gd"),
	preload("res://tests/route_test.gd"),
	preload("res://tests/resource_manager_test.gd"),
]

func _initialize() -> void:
	var failures := 0
	for suite in SUITES:
		var result = suite.new().run()
		if typeof(result) != TYPE_INT:
			failures += 1
			printerr("FAIL: %s did not return an int (suite aborted)" % suite.resource_path)
		else:
			failures += result
	if failures == 0:
		print("ALL TESTS PASSED")
	else:
		printerr("%d TEST(S) FAILED" % failures)
	quit(0 if failures == 0 else 1)
