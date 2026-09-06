type t

val create :
  Window.t ->
  t Error.result

val instance :
  t ->
  Vk.Instance.t

val surface :
  t ->
  Vk.SurfaceKHR.t

val physical_device :
  t ->
  Vk.PhysicalDevice.t

val device :
  t ->
  Vk.Device.t

val graphics_queue :
  t ->
  Vk.Queue.t

val present_queue :
  t ->
  Vk.Queue.t

val graphics_family :
  t ->
  int

val present_family :
  t ->
  int

val wait_idle :
  t ->
  unit

val destroy :
  t ->
  unit
