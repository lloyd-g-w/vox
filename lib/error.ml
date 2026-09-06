type t =
  [ `Msg of string
  | `No_physical_device
  | `No_graphics_queue
  | `No_present_queue
  | `No_surface_format
  | `No_present_mode ]

type 'a result = ('a, t) Stdlib.result

let of_sdl (std_res : 'a Tsdl.Sdl.result) : 'a result =
  Stdlib.Result.map_error (fun (`Msg message) : t -> `Msg message) std_res
