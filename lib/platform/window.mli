type t

val create : title:string -> width:int -> height:int -> t Error.result
val size : t -> int * int
val set_title : t -> string -> unit
val destroy : t -> unit
