package utils


import "core:fmt"
import "core:mem"
import "vendor:stb/image"


ImageInfo :: struct {
	data:     []u8,
	width:    u32,
	height:   u32,
	channels: i32,
}


load_texture_from_file :: proc(path: string) -> (img: ImageInfo, ok: bool) {
	x, y, c, dc: i32
	callbacks: image.Io_Callbacks = {}


	result := image.load_from_callbacks(&callbacks, nil, &x, &y, &c, dc)

	if result == nil {
		fmt.eprintln("Failed to load image from path ", path)
		return img, false
	}

	img.width = u32(x)
	img.height = u32(y)
	img.channels = c
	ok = true
	return
}


free_image :: proc(img: ^ImageInfo) {
	free(&img.data)
	free(&img.width)
	free(&img.height)
	free(&img.channels)
	free(img)
}
