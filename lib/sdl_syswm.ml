(* [SDL_GetWindowWMInfo], bound with ctypes-foreign.

   wgpu needs a *native* window handle: an Xlib [Display *] plus a [Window], a
   Wayland [wl_display *] plus a [wl_surface *], an HWND, or a [CAMetalLayer].
   tsdl exposes [Sdl.unsafe_ptr_of_window : window -> nativeint] (the raw
   [SDL_Window *]) but not [SDL_GetWindowWMInfo], which is the SDL entry point
   that turns that into the native handles.  So this module binds it directly.
   No SDL library has to be found for that: tsdl's own C stubs already link
   libSDL2 into the process, so the symbol is in the global scope and
   [Foreign.foreign] resolves it through the default [dlsym] handle.  The
   explicit [dlopen] below is only a fallback.

   [SDL_SysWMinfo] is a *versioned* struct: [SDL_GetWindowWMInfo] refuses to
   fill one whose [version] field does not match the running SDL, which is what
   the [SDL_VERSION] macro sets in C.  Here the macro is not available, so the
   version is read from the running library with [SDL_GetVersion] — which is
   also the more honest thing to do from a binding that was not compiled
   against SDL's headers at all.

   Its layout is platform-specific, and this module *declares* it rather than
   reading it from SDL_syswm.h, so the declaration is checked against the real
   header by [test/sdl] (a C probe compiled against SDL2's own headers, in the
   shape of [test/abi]).  This file is compiled twice: once into
   [examples/sdl_window.exe] and once, through [dune]'s [copy_files], into
   that test.

   Nothing here depends on tsdl: the window is passed as the [nativeint] tsdl
   hands out, so [test/sdl] can link this module with ctypes alone. *)

open Ctypes

(* ------------------------------------------------------------------ *)
(* The declared layout, checked against SDL's headers by test/sdl      *)
(* ------------------------------------------------------------------ *)

(** [SDL_version] — three bytes, no padding. *)
module Version = struct
  type s

  type t = s structure

  let t : t typ = structure "SDL_version"
  let major = field t "major" uint8_t
  let minor = field t "minor" uint8_t
  let patch = field t "patch" uint8_t
  let () = seal t
end

(** The [x11] member of [SDL_SysWMinfo.info].  [Window] is an [XID], i.e. an
    [unsigned long]; [WGPUSurfaceSourceXlibWindow.window] is a [uint64_t]. *)
module X11 = struct
  type s

  type t = s structure

  let t : t typ = structure "SDL_SysWMinfo_x11"
  let display = field t "display" (ptr void)
  let window = field t "window" ulong
  let () = seal t
end

(** The first two members of the [wl] member of [SDL_SysWMinfo.info]; the rest
    of SDL's Wayland struct is not needed to build a WebGPU surface. *)
module Wayland = struct
  type s

  type t = s structure

  let t : t typ = structure "SDL_SysWMinfo_wl"
  let display = field t "display" (ptr void)
  let surface = field t "surface" (ptr void)
  let () = seal t
end

(** The [info] union.  SDL documents it as "always 64 bytes (8 64-bit
    pointers)" and pads it with [Uint8 dummy[64]] to guarantee that, so the
    union's size does not depend on which video drivers SDL was built with. *)
module Info = struct
  type s

  type t = s union

  let t : t typ = union "SDL_SysWMinfo_info"
  let x11 = field t "x11" X11.t
  let wl = field t "wl" Wayland.t
  let dummy = field t "dummy" (array 64 uint8_t)
  let () = seal t
end

(** [SDL_SysWMinfo]. *)
module Sys_wm_info = struct
  type s

  type t = s structure

  let t : t typ = structure "SDL_SysWMinfo"
  let version = field t "version" Version.t

  (* SDL_SYSWM_TYPE, a plain C enum. *)
  let subsystem = field t "subsystem" uint32_t
  let info = field t "info" Info.t
  let () = seal t
end

(* SDL_SYSWM_TYPE values, checked against the header by test/sdl. *)
let syswm_windows = 1
let syswm_x11 = 2
let syswm_cocoa = 4
let syswm_wayland = 6

(* ------------------------------------------------------------------ *)
(* The two entry points                                                *)
(* ------------------------------------------------------------------ *)

(* Fall back to opening libSDL2 explicitly if the process does not already
   export the symbols (it does when tsdl is linked in). *)
let sdl_handle =
  lazy
    (List.find_map
       (fun filename ->
         try Some (Dl.dlopen ~filename ~flags:[ Dl.RTLD_NOW; Dl.RTLD_GLOBAL ]) with
         | Dl.DL_error _ -> None)
       [ "libSDL2-2.0.so.0"; "libSDL2.so"; "libSDL2-2.0.0.dylib"; "SDL2.dll" ])

let sdl_foreign : type a b. string -> (a -> b) Ctypes.fn -> a -> b =
 fun name fn ->
  try Foreign.foreign name fn with
  | Dl.DL_error _ as e -> (
      match Lazy.force sdl_handle with
      | Some from -> Foreign.foreign ~from name fn
      | None -> raise e)

(* Resolved on first use, never at module initialisation: test/sdl links this
   module without linking SDL at all. *)
let sdl_get_error = lazy (sdl_foreign "SDL_GetError" (void @-> returning string))
let sdl_get_version = lazy (sdl_foreign "SDL_GetVersion" (ptr Version.t @-> returning void))

let sdl_get_window_wm_info =
  lazy (sdl_foreign "SDL_GetWindowWMInfo" (ptr void @-> ptr Sys_wm_info.t @-> returning int))

(** What a WebGPU surface can be built from. *)
type handles =
  | X11 of { display : unit ptr; window : Unsigned.UInt64.t }
  | Wayland of { display : unit ptr; surface : unit ptr }
  | Unsupported of int  (** the [SDL_SYSWM_TYPE] this build does not handle *)

let subsystem_name = function
  | n when n = syswm_windows -> "SDL_SYSWM_WINDOWS"
  | n when n = syswm_x11 -> "SDL_SYSWM_X11"
  | n when n = syswm_cocoa -> "SDL_SYSWM_COCOA"
  | n when n = syswm_wayland -> "SDL_SYSWM_WAYLAND"
  | n -> Printf.sprintf "SDL_SYSWM_TYPE %d" n

(** [of_window p] runs [SDL_GetWindowWMInfo] on the raw [SDL_Window *] [p]
    (what [Sdl.unsafe_ptr_of_window] returns) and reports the native handles it
    filled in.  The [Unsigned.UInt64.t] and the two [unit ptr]s point into
    memory SDL owns, i.e. they stay valid until the window is destroyed. *)
let of_window (window : nativeint) : (handles, string) result =
  if window = 0n then Error "SDL_GetWindowWMInfo: NULL window"
  else
    let info = allocate_n ~count:1 Sys_wm_info.t in
    (* Zero first: SDL only writes the union member of the subsystem it
       reports, and [allocate_n] does not promise zeroed memory. *)
    let bytes =
      CArray.from_ptr (coerce (ptr Sys_wm_info.t) (ptr char) info) (sizeof Sys_wm_info.t)
    in
    for i = 0 to CArray.length bytes - 1 do
      CArray.set bytes i '\000'
    done;
    (* SDL_VERSION(&info.version), at run time: the struct is versioned and
       SDL_GetWindowWMInfo fails if the version does not match. *)
    Lazy.force sdl_get_version (info |-> Sys_wm_info.version);
    let ok = Lazy.force sdl_get_window_wm_info (ptr_of_raw_address window) info in
    if ok = 0 then Error (Printf.sprintf "SDL_GetWindowWMInfo failed: %s" (Lazy.force sdl_get_error ()))
    else
      let subsystem = Unsigned.UInt32.to_int !@(info |-> Sys_wm_info.subsystem) in
      let union = info |-> Sys_wm_info.info in
      if subsystem = syswm_x11 then
        let x11 = union |-> Info.x11 in
        Ok
          (X11
             { display = !@(x11 |-> X11.display);
               (* [Window] is an XID; the bit pattern is what wgpu wants. *)
               window = Unsigned.UInt64.of_int64 (Unsigned.ULong.to_int64 !@(x11 |-> X11.window))
             })
      else if subsystem = syswm_wayland then
        let wl = union |-> Info.wl in
        Ok (Wayland { display = !@(wl |-> Wayland.display); surface = !@(wl |-> Wayland.surface) })
      else Ok (Unsupported subsystem)
