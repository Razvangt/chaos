package utils

// Data i need right now from the Model :
// Texture Data:
//
// Model :
// VecrtexData: 
//  position: vec3
//  normals: 
//  texture coordinates uvs vec2
//  colors: vec3 or vec4
//  Tangents and Bitangents
//IndexData:
//  indices:

load_model :: proc( path: cstring) -> bool {
	log.debug("vulkan load_model: START")
	options: cgltf.options = {}
	data, res := cgltf.parse_file(options, path)
	if (res != .success) {
		log.error("vulkan load_model: failed to parse file")
		return false
	}
	defer cgltf.free(data)
  

	log.info("Loaded gltf file: %s\n", path)
	log.info("Number of meshes : %s\n", path)

	log.debug("vulkan load_model: SUCCESSFULL")
	return true
}
