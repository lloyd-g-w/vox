module Sdl = Tsdl.Sdl

type t = Sdl.window

let create ~title ~width ~height : t Error.result =
  Sdl.create_window ~x:Sdl.Window.pos_centered ~y:Sdl.Window.pos_centered
    ~w:width ~h:height title
    Sdl.Window.(vulkan + resizable + allow_highdpi)
  |> Error.of_sdl

let required_vulkan_extensions (window : t) : string list Error.result =
  match Sdl.Vulkan.get_instance_extensions window with
  | Some extensions -> Ok extensions
  | None -> Error (`Msg (Sdl.get_error ()))

let create_vulkan_surface (window : t) (instance : Vk.Instance.t) :
    Vk.SurfaceKHR.t Error.result =
  let sdl_instance =
    instance |> Vk.Instance.to_nativeint |> Sdl.Vulkan.unsafe_instance_of_ptr
  in
  match Sdl.Vulkan.create_surface window sdl_instance with
  | Some surface ->
      let surface =
        surface |> Sdl.Vulkan.unsafe_uint64_of_surface |> Vk.SurfaceKHR.of_int64
      in
      Ok surface
  | None -> Error (`Msg (Sdl.get_error ()))

let drawable_size = Sdl.Vulkan.get_drawable_size
let size = Sdl.get_window_size
let set_title = Sdl.set_window_title
let destroy = Sdl.destroy_window
