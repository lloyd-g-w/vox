module Sdl = Tsdl.Sdl

type t = Sdl.window

let create ~title ~width ~height : t Error.result =
  Sdl.create_window ~x:Sdl.Window.pos_centered ~y:Sdl.Window.pos_centered
    ~w:width ~h:height title
    Sdl.Window.(resizable + allow_highdpi)
  |> Error.of_sdl

let size = Sdl.get_window_size
let set_title = Sdl.set_window_title
let destroy = Sdl.destroy_window
