package game

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"

get_text :: proc{get_text_string_int, get_text_id_string}
get_text_string_int :: proc(id: string, key: i32) -> string{
	return app.texts[fmt.tprintf("%v/%d", id, key)]
}
get_text_id_string :: proc(id: any, key: string) -> string{
	return app.texts[fmt.tprintf("%v/%v", id, key)]
}
has_text :: proc(id: any, key: string) -> bool{
	return fmt.tprintf("%v/%v", id, key) in app.texts
}

load_data :: proc(texts_buffer: ^string, path: string) {
	file, file_ok := os.read_entire_file(path, context.allocator)
	if file_ok != nil{
		fmt.println("Error loading texts!")
		os.exit(1)
	}
	texts_buffer ^= string(file)

    when ODIN_OS == .Windows{
	    shift_end := 1 // +1 to remove the \r before \n
    } else {
        shift_end := 0
    }

	Token :: enum{Root, Section, Key, Value, Comment}
	token: Token
	expect_section_or_key := true
	section_start, section_end := 0, 0
	key_start, key_end := 0, 0
	for r, i in texts_buffer {
		if token == .Root && r == '/' {
			key_start = i
			token = .Key
		} else if token == .Root && r == '#' {
			token = .Comment
		} else if token == .Comment && r == '\n' {
			token = .Root
		} else if token == .Key && r == '=' {
			key_end = i // we don't need the =
			token = .Value
		} else if token == .Value && r == '\n' {
		    section := texts_buffer[section_start:section_end]
			local_key := texts_buffer[key_start+1:key_end]
			global_key := strings.join({section, local_key}, "/")

            value := texts_buffer[key_end+2:i-1-shift_end] // +2 for =", -2 to remove " and the \r before \n
			if texts_buffer[key_end+1] == '"' {
			    app.texts[global_key] = value
			} else if texts_buffer[key_end+1] == '[' && local_key == "texture_id"{
			    values := strings.split(value, ",", context.temp_allocator)
				fmt.println("Parsed texture coordinates for", section, ": ", values)
				x_coord, x_ok := strconv.parse_int(values[0])
				y_coord, y_ok := strconv.parse_int(values[1])
				if x_ok && y_ok {
                    app.sub_textures[section] = {
                        f32(x_coord),
                        f32(y_coord),
                    }
				} else {
				    fmt.printfln("Error parsing texture coordinates for %v (0: %v, 1: %v)", section, x_ok, y_ok)
				}
            } else {
                fmt.printfln("Warning: value for key %s in section %s is neither a string nor a texture id:\n%s", local_key, section, value)
            }

			token = .Root
		} else if token == .Section && r == '\n'{
			section_end = i-shift_end
			token = .Root
		} else if token == .Root && !strings.is_space(r) {
			section_start = i
			token = .Section
		}
	}
}
