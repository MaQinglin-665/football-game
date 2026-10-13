extends SceneTree

func _initialize() -> void:
	var file := FileAccess.open("res://licenses/Godot-and-components.txt", FileAccess.WRITE)
	file.store_string("Godot Engine 4.6.3 - engine and bundled component notices\n\n")
	file.store_string(Engine.get_license_text() + "\n\n")
	for component in Engine.get_copyright_info():
		file.store_string(str(component.name) + "\n")
		for section in component.parts:
			file.store_string("License: " + str(section.license) + "\n")
			for author in section.copyright:
				file.store_string(str(author) + "\n")
			file.store_string("\n")
	file.store_string("\nFULL COMPONENT LICENSE TEXTS\n\n")
	var licenses := Engine.get_license_info()
	for name in licenses:
		file.store_string(str(name) + "\n" + str(licenses[name]) + "\n\n")
	file.close()
	print("Engine and bundled library notices collected from the exact installed runtime.")
	quit()
