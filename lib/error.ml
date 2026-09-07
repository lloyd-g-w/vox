type t = [ `Msg of string ]
type 'a result = ('a, t) Stdlib.result

let of_sdl (std_res : 'a Tsdl.Sdl.result) : 'a result =
  Stdlib.Result.map_error (fun (`Msg message) : t -> `Msg message) std_res
