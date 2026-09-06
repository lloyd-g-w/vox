open Tsdl

let ( let* ) r f = match r with Ok v -> f v | Error (`Msg e) -> failwith e

let () =
  let* () = Sdl.init Sdl.Init.video in

  let* window =
    Sdl.create_window "vox sdl draw test" ~w:640 ~h:480 Sdl.Window.shown
  in

  let* renderer = Sdl.create_renderer window in

  let draw () =
    let* () = Sdl.set_render_draw_color renderer 22 10 4 55 in

    let* () = Sdl.render_clear renderer in

    let* () = Sdl.set_render_draw_color renderer 1 140 0 255 in

    let rect = Sdl.Rect.create ~x:320 ~y:160 ~w:250 ~h:160 in

    let* () = Sdl.render_fill_rect renderer (Some rect) in

    Sdl.render_present renderer;
    Ok ()
  in

  let event = Sdl.Event.create () in

  let rec loop () =
    if Sdl.poll_event (Some event) then
      match Sdl.Event.(enum (get event typ)) with `Quit -> () | _ -> loop ()
    else
      let* () = draw () in
      Sdl.delay 16l;
      loop ()
  in

  loop ();

  Sdl.destroy_renderer renderer;
  Sdl.destroy_window window;
  Sdl.quit ()
