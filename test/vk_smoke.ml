let () =
  let application =
    Vk.ApplicationInfo.make ~application_name:"vox vulkan smoke test"
      ~api_version:Vk.api_version_1_4 ()
  in
  let instance_info = Vk.InstanceCreateInfo.make ~application_info:application () in
  let instance = Vk.create_instance instance_info in
  let physical_devices = Vk.enumerate_physical_devices instance in
  Printf.printf "vulkan bindings ok: found %d physical device(s)\n"
    (List.length physical_devices);
  List.iter
    (fun device ->
      let properties = Vk.get_physical_device_properties device in
      let name = Vk.PhysicalDeviceProperties.get_device_name properties in
      Printf.printf "  - %s\n" name)
    physical_devices;
  Vk.destroy_instance instance ()
