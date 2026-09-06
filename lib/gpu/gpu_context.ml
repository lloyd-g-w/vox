type queue_families = { graphics : int; present : int }

type t = {
  instance : Vk.Instance.t;
  surface : Vk.SurfaceKHR.t;
  physical_device : Vk.PhysicalDevice.t;
  device : Vk.Device.t;
  graphics_queue : Vk.Queue.t;
  present_queue : Vk.Queue.t;
  graphics_family : int;
  present_family : int;
}

let get = Ctypes.getf
let first = function [] -> None | item :: _ -> Some item

let vk_error result =
  `Msg (Printf.sprintf "Vulkan error: %s" (Vk.Result.to_string result))

let function_not_loaded name =
  `Msg (Printf.sprintf "Vulkan function not loaded: %s" name)

let find_queue_families physical_device surface =
  let properties =
    Vk.get_physical_device_queue_family_properties physical_device
  in

  let rec search index graphics present = function
    | [] -> (
        match (graphics, present) with
        | Some graphics, Some present -> Some { graphics; present }
        | _ -> None)
    | properties :: remaining -> (
        let queue_count = get properties Vk.QueueFamilyProperties.queue_count in
        let flags = get properties Vk.QueueFamilyProperties.queue_flags in
        let graphics =
          if
            Option.is_none graphics && queue_count > 0
            && Vk.QueueFlags.mem flags Vk.QueueFlags.graphics
          then Some index
          else graphics
        in
        let present =
          if
            Option.is_none present && queue_count > 0
            && Vk.get_physical_device_surface_support_khr physical_device index
                 surface
          then Some index
          else present
        in
        match (graphics, present) with
        | Some graphics, Some present -> Some { graphics; present }
        | _ -> search (index + 1) graphics present remaining)
  in

  search 0 None None properties

let supports_swapchain physical_device =
  Vk.enumerate_device_extension_properties physical_device
  |> List.exists (fun extension ->
         String.equal
           (Vk.ExtensionProperties.get_extension_name extension)
           Vk.Ext.khr_swapchain)

let has_swapchain_support physical_device surface =
  let formats =
    Vk.get_physical_device_surface_formats_khr physical_device surface
  in
  let present_modes =
    Vk.get_physical_device_surface_present_modes_khr physical_device surface
  in
  formats <> [] && present_modes <> []

let device_score physical_device =
  let properties = Vk.get_physical_device_properties physical_device in
  let device_type = get properties Vk.PhysicalDeviceProperties.device_type in
  if Vk.PhysicalDeviceType.equal device_type Vk.PhysicalDeviceType.discrete_gpu
  then 1_000
  else if
    Vk.PhysicalDeviceType.equal device_type Vk.PhysicalDeviceType.integrated_gpu
  then 500
  else 0

let select_physical_device instance surface =
  Vk.enumerate_physical_devices instance
  |> List.filter_map (fun physical_device ->
         match find_queue_families physical_device surface with
         | Some queue_families
           when supports_swapchain physical_device
                && has_swapchain_support physical_device surface ->
             Some (device_score physical_device, physical_device, queue_families)
         | _ -> None)
  |> List.sort (fun (left_score, _, _) (right_score, _, _) ->
         Int.compare right_score left_score)
  |> first
  |> Option.map (fun (_, physical_device, queue_families) ->
         (physical_device, queue_families))

let unique_queue_families queue_families =
  if queue_families.graphics = queue_families.present then
    [ queue_families.graphics ]
  else [ queue_families.graphics; queue_families.present ]

let create_logical_device physical_device queue_families =
  let queue_create_infos =
    unique_queue_families queue_families
    |> List.map (fun queue_family_index ->
           Vk.DeviceQueueCreateInfo.make ~queue_family_index
             ~queue_priorities:[ 1.0 ] ())
  in
  let device_create_info =
    Vk.DeviceCreateInfo.make ~queue_create_infos
      ~enabled_extension_names:[ Vk.Ext.khr_swapchain ] ()
  in
  Vk.create_device physical_device device_create_info

let destroy_instance instance = Vk.destroy_instance instance ()

let destroy_surface_and_instance instance surface =
  Vk.destroy_surface_khr instance surface ();
  destroy_instance instance

let create_instance extensions =
  let application_info =
    Vk.ApplicationInfo.make ~application_name:"Vox" ~engine_name:"Vox"
      ~api_version:Vk.api_version_1_3 ()
  in
  let instance_create_info =
    Vk.InstanceCreateInfo.make ~application_info
      ~enabled_extension_names:(List.sort_uniq String.compare extensions)
      ()
  in
  try Ok (Vk.create_instance instance_create_info) with
  | Vk.Error result -> Error (vk_error result)
  | Vk.Not_loaded name -> Error (function_not_loaded name)

let create (window : Window.t) : t Error.result =
  match Window.required_vulkan_extensions window with
  | Error error -> Error error
  | Ok extensions -> (
      match create_instance extensions with
      | Error error -> Error error
      | Ok instance -> (
          match Window.create_vulkan_surface window instance with
          | Error error ->
              destroy_instance instance;
              Error error
          | Ok surface -> (
              try
                match select_physical_device instance surface with
                | None ->
                    destroy_surface_and_instance instance surface;
                    Error `No_physical_device
                | Some (physical_device, queue_families) ->
                    let device =
                      create_logical_device physical_device queue_families
                    in
                    let graphics_queue =
                      Vk.get_device_queue device queue_families.graphics 0
                    in
                    let present_queue =
                      Vk.get_device_queue device queue_families.present 0
                    in
                    if
                      Vk.Queue.is_null graphics_queue
                      || Vk.Queue.is_null present_queue
                    then (
                      Vk.destroy_device device ();
                      destroy_surface_and_instance instance surface;
                      Error (`Msg "Vulkan returned a null queue"))
                    else
                      Ok
                        {
                          instance;
                          surface;
                          physical_device;
                          device;
                          graphics_queue;
                          present_queue;
                          graphics_family = queue_families.graphics;
                          present_family = queue_families.present;
                        }
              with
              | Vk.Error result ->
                  destroy_surface_and_instance instance surface;
                  Error (vk_error result)
              | Vk.Not_loaded name ->
                  destroy_surface_and_instance instance surface;
                  Error (function_not_loaded name))))

let instance context = context.instance
let surface context = context.surface
let physical_device context = context.physical_device
let device context = context.device
let graphics_queue context = context.graphics_queue
let present_queue context = context.present_queue
let graphics_family context = context.graphics_family
let present_family context = context.present_family
let wait_idle context = Vk.device_wait_idle context.device

let destroy context =
  Vk.destroy_device context.device ();
  Vk.destroy_surface_khr context.instance context.surface ();
  Vk.destroy_instance context.instance ()
