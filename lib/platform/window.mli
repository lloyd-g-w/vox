type t

val create : title:string -> width:int -> height:int -> t Error.result
val required_vulkan_extensions : t -> string list Error.result
val create_vulkan_surface : t -> Vk.Instance.t -> Vk.SurfaceKHR.t Error.result
val drawable_size : t -> int * int
val size : t -> int * int
val set_title : t -> string -> unit
val destroy : t -> unit
