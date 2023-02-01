
let handle_client sock _stdout =
  while true do
    let b = Cstruct.create 512 in
    let _senderSock, size = Eio.Net.recv sock b in
    Eio.traceln "Client: received %S" (Cstruct.to_string b ~len:size);
  done

let main ~net ~stdout =
  let bindaddr = `Udp (Eio.Net.Ipaddr.V4.loopback, 53) in
  Eio.Switch.run @@ fun sw ->
  let sock = Eio.Net.datagram_socket ~sw net bindaddr in
  handle_client sock stdout;;

let () = Eio_main.run @@ fun env ->
  main ~net:(Eio.Stdenv.net env) ~stdout:(Eio.Stdenv.stdout env)
