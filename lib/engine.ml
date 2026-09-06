let run () =
  match Window.create ~title:"test" ~width:1920 ~height:1080 with
  | Ok window -> Tsdl.Sdl.delay 1000l
  | _ -> ()
