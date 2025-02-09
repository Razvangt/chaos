package chaos

import "vendor:vulkan"


VALIDATION_LAYERS := [?]cstring{"VK_LAYER_KHRONOS_validation"};

ckVkInstance:: proc(){
  appInfo := vulkan.ApplicationInfo{};
  appInfo.sType = vulkan.StructureType.APPLICATION_INFO;
  appInfo.pApplicationName = "ChaosRenderer";
  appInfo.applicationVersion =  vulkan.MAKE_VERSION(1,0,0);
  appInfo.pEngineName =  "ChaosEngine";
  appInfo.engineVersion = vulkan.MAKE_VERSION(1,0,0);
  appInfo.apiVersion = vulkan.API_VERSION_1_3

  createinfo := vulkan.InstanceCreateInfo{};
  createinfo.sType = vulkan.StructureType.INSTANCE_CREATE_INFO;
  createinfo.pApplicationInfo = &appInfo;

  
  when ODIN_DEBUG {
    
    validationLayers:: 0;
  } else {
    validationLayers:: 0;
  }
}
