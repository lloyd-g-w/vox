(* Windowed render: draw a triangle into an SDL2 window every frame.

   This is [offscreen_render.ml] with a surface instead of a texture, in the
   shape of wgpu-native's own C example (examples/triangle/main.c) with GLFW
   replaced by tsdl (https://github.com/dbuenzli/tsdl).  It is the raw binding
   throughout: every descriptor starts from the header's [init ()] defaults, is
   filled with [Ctypes.setf], and every handle is released explicitly.

   The window handle comes from [Sdl_syswm], which binds [SDL_GetWindowWMInfo]
   with ctypes-foreign because tsdl does not expose it; see that file and
   [test/sdl], which checks the [SDL_SysWMinfo] layout it declares against
   SDL's own headers.

   tsdl is not a dependency of this package, so examples/dune picks between this
   file and the sdl_window.without_tsdl.ml stub with dune's (select): with tsdl
   installed, sdl_window.exe is this program.

   Run with:  dune exec examples/sdl_window.exe
              dune exec examples/sdl_window.exe -- --frames 30

   [--frames N] renders exactly N frames and exits, which is what CI runs under
   Xvfb.  The exit status is non-zero if any frame's surface texture came back
   with a status other than success/suboptimal, or if the uncaptured-error
   callback fired.  That is deliberately strict: a program meant to survive
   compositor changes would treat [Outdated] as routine rather than as a
   failure to report at the end.

   Tested on Linux/X11 only (Xvfb + lavapipe).  The Wayland branch is written
   but has never been executed, and there is no Windows or macOS branch: see
   the guide, "Rendering to a window with tsdl". *)

module T = Wgpu.Types
module F = Wgpu.Fn
module U = Wgpu_utils

let u32 = Unsigned.UInt32.of_int
let sz = Unsigned.Size_t.of_int
let nullp typ = Ctypes.from_voidp typ Ctypes.null
let initial_width = 640
let initial_height = 480

(* A [WGPUStringView] points at memory we own. *)
let owned_strings = ref []

let sv s =
  let view, keepalive = U.String_view.of_string s in
  owned_strings := keepalive :: !owned_strings;
  view

let shader =
  {|
@vertex
fn vs_main(@builtin(vertex_index) i: u32) -> @builtin(position) vec4<f32> {
  var p = array<vec2<f32>, 3>(vec2<f32>(-1.0, -1.0), vec2<f32>(1.0, -1.0), vec2<f32>(-1.0, 1.0));
  return vec4<f32>(p[i], 0.0, 1.0);
}

@fragment
fn fs_main() -> @location(0) vec4<f32> {
  return vec4<f32>(1.0, 0.0, 0.0, 1.0);
}
|}

let device_errors = ref 0

let uncaptured_error =
  Wgpu.Callback.permanent T.UncapturedErrorCallback.fn
    (fun _device ty message _u1 _u2 ->
      Wgpu.Callback.protect ~where:"uncaptured error callback" (fun () ->
          incr device_errors;
          Printf.eprintf "[wgpu %s] %s\n%!" (T.ErrorType.to_string ty)
            (U.String_view.to_string message)))

let die fmt =
  Printf.ksprintf
    (fun s ->
      prerr_endline s;
      exit 1)
    fmt

let frames_wanted =
  let rec parse = function
    | [] -> None
    | "--frames" :: n :: _ -> (
        match int_of_string_opt n with
        | Some n when n > 0 -> Some n
        | _ -> die "--frames wants a positive integer, got %S" n)
    | [ "--frames" ] -> die "--frames wants a positive integer"
    | _ :: rest -> parse rest
  in
  parse (Array.to_list Sys.argv)

(* ------------------------------------------------------------------ *)
(* The window, and the surface source its native handles fill in       *)
(* ------------------------------------------------------------------ *)

let () =
  match Tsdl.Sdl.init Tsdl.Sdl.Init.video with
  | Error (`Msg m) -> die "SDL_Init: %s" m
  | Ok () -> ()

let window =
  match
    Tsdl.Sdl.create_window "triangle [wgpu-ocaml + tsdl]" ~w:initial_width
      ~h:initial_height Tsdl.Sdl.Window.resizable
  with
  | Error (`Msg m) -> die "SDL_CreateWindow: %s" m
  | Ok w -> w

(* [wgpuInstanceCreateSurface] reads the chained surface source through
   [SurfaceDescriptor.nextInChain], so the OCaml value behind that pointer must
   stay alive until the call returns — hence the [Sys.opaque_identity] in each
   branch, right after the call that reads it. *)
let create_surface instance =
  let desc = T.SurfaceDescriptor.init () in
  Ctypes.setf desc T.SurfaceDescriptor.label (sv "sdl-window");
  let chain source_t source =
    Ctypes.setf desc T.SurfaceDescriptor.nextInChain
      (Ctypes.coerce (Ctypes.ptr source_t)
         (Ctypes.ptr T.ChainedStruct.t)
         (Ctypes.addr source))
  in
  match Sdl_syswm.of_window (Tsdl.Sdl.unsafe_ptr_of_window window) with
  | Error msg -> die "%s" msg
  | Ok (Sdl_syswm.X11 { display; window }) ->
      let source = T.SurfaceSourceXlibWindow.init () in
      Ctypes.setf source T.SurfaceSourceXlibWindow.display display;
      Ctypes.setf source T.SurfaceSourceXlibWindow.window window;
      chain T.SurfaceSourceXlibWindow.t source;
      let surface = F.wgpuInstanceCreateSurface instance (Ctypes.addr desc) in
      ignore (Sys.opaque_identity (desc, source));
      (surface, "X11")
  (* Written from the header and wgpu-native's GLFW example, never executed:
     this project has only ever run the X11 path. *)
  | Ok (Sdl_syswm.Wayland { display; surface = wl_surface }) ->
      let source = T.SurfaceSourceWaylandSurface.init () in
      Ctypes.setf source T.SurfaceSourceWaylandSurface.display display;
      Ctypes.setf source T.SurfaceSourceWaylandSurface.surface wl_surface;
      chain T.SurfaceSourceWaylandSurface.t source;
      let surface = F.wgpuInstanceCreateSurface instance (Ctypes.addr desc) in
      ignore (Sys.opaque_identity (desc, source));
      (surface, "Wayland")
  (* Windows would chain WGPUSurfaceSourceWindowsHWND {hinstance; hwnd} and
     macOS WGPUSurfaceSourceMetalLayer {layer} — the latter after asking the
     NSView for a CAMetalLayer, which SDL2 only creates for a window opened
     with SDL_WINDOW_METAL.  Neither is written here, because neither could be
     tested. *)
  | Ok (Sdl_syswm.Unsupported subsystem) ->
      die "this example has no surface source for %s"
        (Sdl_syswm.subsystem_name subsystem)

let run () =
  let instance = F.wgpuCreateInstance (nullp T.InstanceDescriptor.t) in
  if T.Instance.is_null instance then die "wgpuCreateInstance returned NULL";

  let surface, platform = create_surface instance in
  if T.Surface.is_null surface then
    die "wgpuInstanceCreateSurface returned NULL";
  Printf.printf "surface: %s\n%!" platform;

  (* The adapter must be able to present to this surface. *)
  let options = T.RequestAdapterOptions.init () in
  Ctypes.setf options T.RequestAdapterOptions.compatibleSurface surface;
  let adapter =
    match U.Sync.request_adapter ~options instance with
    | Ok a -> a
    | Error (status, msg) ->
        die "no adapter: %s (%s)" (T.RequestAdapterStatus.to_string status) msg
  in
  let info = T.AdapterInfo.init () in
  if F.wgpuAdapterGetInfo adapter (Ctypes.addr info) <> T.Status.success then
    die "wgpuAdapterGetInfo failed";
  Printf.printf "adapter: %s (backend %s)\n%!"
    (U.String_view.to_string (Ctypes.getf info T.AdapterInfo.device))
    (T.BackendType.to_string (Ctypes.getf info T.AdapterInfo.backendType));
  F.wgpuAdapterInfoFreeMembers info;

  let device_desc = T.DeviceDescriptor.init () in
  Ctypes.setf device_desc T.DeviceDescriptor.label (sv "sdl-window");
  let uc = T.UncapturedErrorCallbackInfo.init () in
  Ctypes.setf uc T.UncapturedErrorCallbackInfo.callback uncaptured_error;
  Ctypes.setf device_desc T.DeviceDescriptor.uncapturedErrorCallbackInfo uc;
  let device =
    match U.Sync.request_device ~descriptor:device_desc adapter with
    | Ok d -> d
    | Error (status, msg) ->
        die "no device: %s (%s)" (T.RequestDeviceStatus.to_string status) msg
  in
  let queue = F.wgpuDeviceGetQueue device in

  (* What this surface/adapter pair supports.  The arrays belong to wgpu until
     wgpuSurfaceCapabilitiesFreeMembers, so read what is needed and free them. *)
  let caps = T.SurfaceCapabilities.init () in
  if
    F.wgpuSurfaceGetCapabilities surface adapter (Ctypes.addr caps)
    <> T.Status.success
  then die "wgpuSurfaceGetCapabilities failed";
  let array_of field count_field =
    let n = Unsigned.Size_t.to_int (Ctypes.getf caps count_field) in
    let p = Ctypes.getf caps field in
    List.init n (fun i -> Ctypes.( !@ ) (Ctypes.( +@ ) p i))
  in
  let formats =
    array_of T.SurfaceCapabilities.formats T.SurfaceCapabilities.formatCount
  in
  let present_modes =
    array_of T.SurfaceCapabilities.presentModes
      T.SurfaceCapabilities.presentModeCount
  in
  let alpha_modes =
    array_of T.SurfaceCapabilities.alphaModes
      T.SurfaceCapabilities.alphaModeCount
  in
  if formats = [] || present_modes = [] || alpha_modes = [] then
    die "the surface reports no format, present mode or alpha mode";
  (* The first format is the preferred one; Fifo is the only present mode
     WebGPU guarantees, so prefer it and fall back to whatever is first. *)
  let format = List.hd formats in
  let present_mode =
    if List.mem T.PresentMode.fifo present_modes then T.PresentMode.fifo
    else List.hd present_modes
  in
  let alpha_mode = List.hd alpha_modes in
  Printf.printf "surface format %s, present mode %s, alpha mode %s\n%!"
    (T.TextureFormat.to_string format)
    (T.PresentMode.to_string present_mode)
    (T.CompositeAlphaMode.to_string alpha_mode);
  F.wgpuSurfaceCapabilitiesFreeMembers caps;

  let wgsl = T.ShaderSourceWGSL.init () in
  Ctypes.setf wgsl T.ShaderSourceWGSL.code (sv shader);
  let module_desc = T.ShaderModuleDescriptor.init () in
  Ctypes.setf module_desc T.ShaderModuleDescriptor.label (sv "triangle");
  Ctypes.setf module_desc T.ShaderModuleDescriptor.nextInChain
    (Ctypes.coerce
       (Ctypes.ptr T.ShaderSourceWGSL.t)
       (Ctypes.ptr T.ChainedStruct.t)
       (Ctypes.addr wgsl));
  let shader_module =
    F.wgpuDeviceCreateShaderModule device (Ctypes.addr module_desc)
  in
  ignore (Sys.opaque_identity wgsl);
  if T.ShaderModule.is_null shader_module then
    die "wgpuDeviceCreateShaderModule returned NULL";

  let target = T.ColorTargetState.init () in
  Ctypes.setf target T.ColorTargetState.format format;
  Ctypes.setf target T.ColorTargetState.writeMask T.ColorWriteMask.all;
  let fragment = T.FragmentState.init () in
  Ctypes.setf fragment T.FragmentState.module_ shader_module;
  Ctypes.setf fragment T.FragmentState.entryPoint (sv "fs_main");
  Ctypes.setf fragment T.FragmentState.targetCount (sz 1);
  Ctypes.setf fragment T.FragmentState.targets (Ctypes.addr target);
  let pipeline_desc = T.RenderPipelineDescriptor.init () in
  Ctypes.setf pipeline_desc T.RenderPipelineDescriptor.label (sv "triangle");
  let vertex = T.VertexState.init () in
  Ctypes.setf vertex T.VertexState.module_ shader_module;
  Ctypes.setf vertex T.VertexState.entryPoint (sv "vs_main");
  Ctypes.setf pipeline_desc T.RenderPipelineDescriptor.vertex vertex;
  let primitive = T.PrimitiveState.init () in
  Ctypes.setf primitive T.PrimitiveState.topology
    T.PrimitiveTopology.triangle_list;
  Ctypes.setf pipeline_desc T.RenderPipelineDescriptor.primitive primitive;
  let multisample = T.MultisampleState.init () in
  Ctypes.setf multisample T.MultisampleState.count (u32 1);
  Ctypes.setf pipeline_desc T.RenderPipelineDescriptor.multisample multisample;
  Ctypes.setf pipeline_desc T.RenderPipelineDescriptor.fragment
    (Ctypes.addr fragment);
  let pipeline =
    F.wgpuDeviceCreateRenderPipeline device (Ctypes.addr pipeline_desc)
  in
  ignore (Sys.opaque_identity (fragment, target));
  if T.RenderPipeline.is_null pipeline then
    die "wgpuDeviceCreateRenderPipeline returned NULL";

  (* One configuration value, reused: reconfiguring on resize only changes
     width and height. *)
  let config = T.SurfaceConfiguration.init () in
  Ctypes.setf config T.SurfaceConfiguration.device device;
  Ctypes.setf config T.SurfaceConfiguration.format format;
  Ctypes.setf config T.SurfaceConfiguration.usage
    T.TextureUsage.render_attachment;
  Ctypes.setf config T.SurfaceConfiguration.alphaMode alpha_mode;
  Ctypes.setf config T.SurfaceConfiguration.presentMode present_mode;
  let configure () =
    (* Logical size == pixel size on X11 without high-DPI flags, which is the
       tested case.  A HiDPI-aware program (Wayland/macOS scaling) must use the
       drawable size (SDL_Vulkan_GetDrawableSize) here instead. *)
    let w, h = Tsdl.Sdl.get_window_size window in
    if w > 0 && h > 0 then (
      Ctypes.setf config T.SurfaceConfiguration.width (u32 w);
      Ctypes.setf config T.SurfaceConfiguration.height (u32 h);
      F.wgpuSurfaceConfigure surface (Ctypes.addr config))
  in
  configure ();

  let clear = T.Color.init () in
  Ctypes.setf clear T.Color.r 0.0;
  Ctypes.setf clear T.Color.g 0.0;
  Ctypes.setf clear T.Color.b 1.0;
  Ctypes.setf clear T.Color.a 1.0;

  (* Labels are constant, so build their views once: [sv] retains the bytes
     for the life of the process, and a frame loop must not grow that list. *)
  let label_frame = sv "frame" and label_triangle = sv "triangle" in

  let draw view =
    let encoder_desc = T.CommandEncoderDescriptor.init () in
    Ctypes.setf encoder_desc T.CommandEncoderDescriptor.label label_frame;
    let encoder =
      F.wgpuDeviceCreateCommandEncoder device (Ctypes.addr encoder_desc)
    in
    let attachment = T.RenderPassColorAttachment.init () in
    Ctypes.setf attachment T.RenderPassColorAttachment.view view;
    Ctypes.setf attachment T.RenderPassColorAttachment.loadOp T.LoadOp.clear;
    Ctypes.setf attachment T.RenderPassColorAttachment.storeOp T.StoreOp.store;
    Ctypes.setf attachment T.RenderPassColorAttachment.clearValue clear;
    let pass_desc = T.RenderPassDescriptor.init () in
    Ctypes.setf pass_desc T.RenderPassDescriptor.label label_triangle;
    Ctypes.setf pass_desc T.RenderPassDescriptor.colorAttachmentCount (sz 1);
    Ctypes.setf pass_desc T.RenderPassDescriptor.colorAttachments
      (Ctypes.addr attachment);
    let pass =
      F.wgpuCommandEncoderBeginRenderPass encoder (Ctypes.addr pass_desc)
    in
    ignore (Sys.opaque_identity attachment);
    F.wgpuRenderPassEncoderSetPipeline pass pipeline;
    F.wgpuRenderPassEncoderDraw pass (u32 3) (u32 1) (u32 0) (u32 0);
    F.wgpuRenderPassEncoderEnd pass;
    F.wgpuRenderPassEncoderRelease pass;
    let commands_desc = T.CommandBufferDescriptor.init () in
    Ctypes.setf commands_desc T.CommandBufferDescriptor.label label_frame;
    let commands =
      F.wgpuCommandEncoderFinish encoder (Ctypes.addr commands_desc)
    in
    let submitted = Ctypes.CArray.of_list T.CommandBuffer.t [ commands ] in
    F.wgpuQueueSubmit queue (sz 1) (Ctypes.CArray.start submitted);
    ignore (Sys.opaque_identity submitted);
    F.wgpuCommandBufferRelease commands;
    F.wgpuCommandEncoderRelease encoder
  in

  (* ---------------------------------------------------------------- *)
  (* The frame loop                                                    *)
  (* ---------------------------------------------------------------- *)
  let event = Tsdl.Sdl.Event.create () in
  let quit = ref false in
  let presented = ref 0 in
  let bad_status = ref 0 in
  let pump () =
    while Tsdl.Sdl.poll_event (Some event) do
      let typ = Tsdl.Sdl.Event.(get event typ) in
      if typ = Tsdl.Sdl.Event.quit then quit := true
      else if typ = Tsdl.Sdl.Event.window_event then
        match
          Tsdl.Sdl.Event.(window_event_enum (get event window_event_id))
        with
        | `Close -> quit := true
        | `Resized | `Size_changed -> configure ()
        | _ -> ()
    done
  in
  let done_ () =
    !quit
    || match frames_wanted with Some n -> !presented >= n | None -> false
  in
  let attempts = ref 0 in
  while not (done_ ()) do
    pump ();
    if not (done_ ()) then (
      (* A surface that never yields a usable texture must not spin forever
         in a --frames run; interactive runs keep trying. *)
      incr attempts;
      (match frames_wanted with
      | Some n when !attempts > 10 * n ->
          die "gave up after %d attempts: %d presented, %d bad statuses"
            !attempts !presented !bad_status
      | _ -> ());
      let frame = T.SurfaceTexture.init () in
      F.wgpuSurfaceGetCurrentTexture surface (Ctypes.addr frame);
      let status = Ctypes.getf frame T.SurfaceTexture.status in
      let texture = Ctypes.getf frame T.SurfaceTexture.texture in
      if
        status = T.SurfaceGetCurrentTextureStatus.success_optimal
        || status = T.SurfaceGetCurrentTextureStatus.success_suboptimal
      then (
        let view_desc = T.TextureViewDescriptor.init () in
        Ctypes.setf view_desc T.TextureViewDescriptor.label label_frame;
        let view = F.wgpuTextureCreateView texture (Ctypes.addr view_desc) in
        draw view;
        (match F.wgpuSurfacePresent surface with
        | s when s = T.Status.success -> incr presented
        | s ->
            incr bad_status;
            Printf.eprintf "wgpuSurfacePresent: %s\n%!" (T.Status.to_string s));
        F.wgpuTextureViewRelease view;
        F.wgpuTextureRelease texture)
      else (
        (* Timeout, Outdated and Lost are recoverable: drop the frame and
           reconfigure at the window's current size.  They are still counted,
           so --frames runs report them.  wgpu.h adds Occluded (0x00030001,
           Metal only) outside the webgpu.h enum; it lands here too and prints
           as hex. *)
        incr bad_status;
        Printf.eprintf "wgpuSurfaceGetCurrentTexture: %s\n%!"
          (T.SurfaceGetCurrentTextureStatus.to_string status);
        if not (T.Texture.is_null texture) then F.wgpuTextureRelease texture;
        if status = T.SurfaceGetCurrentTextureStatus.error then quit := true
        else configure ()))
  done;
  Printf.printf "presented %d frames\n%!" !presented;

  F.wgpuSurfaceUnconfigure surface;
  F.wgpuRenderPipelineRelease pipeline;
  F.wgpuShaderModuleRelease shader_module;
  F.wgpuQueueRelease queue;
  F.wgpuDeviceRelease device;
  F.wgpuAdapterRelease adapter;
  F.wgpuSurfaceRelease surface;
  F.wgpuInstanceRelease instance;
  Tsdl.Sdl.destroy_window window;
  Tsdl.Sdl.quit ();
  ignore (Sys.opaque_identity !owned_strings);

  List.iter
    (fun f ->
      Printf.eprintf "callback failure: %s\n%!"
        (Wgpu.Callback.string_of_failure f))
    (Wgpu.Callback.take_failures ());
  let asked = match frames_wanted with Some n -> n | None -> !presented in
  if !bad_status > 0 || !device_errors > 0 || !presented < asked then (
    Printf.eprintf
      "failed: %d surface status failure(s), %d device error(s), %d/%d frames\n\
       %!"
      !bad_status !device_errors !presented asked;
    exit 1)
