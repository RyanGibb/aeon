
let convert_eio_to_ipaddr (addr : Eio.Net.Sockaddr.datagram) =
  match addr with
  | `Udp (ip, p) ->
    let src = (ip :> string) in
    let src = Eio.Net.Ipaddr.fold
      ~v4:(fun _v4 -> Ipaddr.V4 (Result.get_ok @@ Ipaddr.V4.of_octets src))
      ~v6:(fun _v6 -> Ipaddr.V6 (Result.get_ok @@ Ipaddr.V6.of_octets src))
      ip
    in
    src, p

let listen ~clock ~mono_clock ~log sock server =
  let buf = Cstruct.create 512 in
  while true do
    let addr, _size = Eio.Net.recv sock buf in
    log `Rx addr buf;
    (* todo handle these *)
    let _t, answers, _notify, _n, _key =
      let now = Ptime.of_float_s @@ Eio.Time.now clock |> Option.get in
      let ts = Mtime.to_uint64_ns @@ Eio.Time.Mono.now mono_clock in
      let src, port = convert_eio_to_ipaddr addr in
      Dns_server.Primary.handle_buf !server now ts `Udp src port buf
    in
    List.iter (fun b -> log `Tx addr b; Eio.Net.send sock addr b) answers
  done

let main ~net ~random ~clock ~mono_clock ~zonefile ~log =
  Eio.Switch.run @@ fun sw ->
  let _zones, trie = Dns_zone.decode_zones [ ("freumh.org", zonefile) ] in
  let rng ?_g length =
    let buf = Cstruct.create length in
    Eio.Flow.read_exact random buf;
    buf
  in
  let server = ref @@ Dns_server.Primary.create ~rng trie in
  (* We listen on in6addr_any to bind to all interfaces. If we also listen on
     INADDR_ANY, this collides with EADDRINUSE. However we can recieve IPv4 traffic
     too via IPv4-mapped IPv6 addresses [0]. It might be useful to look at using
     happy-eyeballs to choose between IPv4 and IPv6, however this may have
     peformance implications [2]. Better might be to explicitly listen per
     interface on IPv4 and/or Ipv6, which would allow the user granular control.
     BSD's also disable IPv4-mapped IPv6 address be default, so this would enable
     better portability.
     [0] https://www.rfc-editor.org/rfc/rfc3493#section-3.7
     [1] https://labs.apnic.net/presentations/store/2015-10-04-dns-dual-stack.pdf *)
  let sock = Eio.Net.datagram_socket ~sw net (`Udp (Eio.Net.Ipaddr.V6.any, 53)) in
  listen ~clock ~mono_clock ~log sock server

let run log = Eio_main.run @@ fun env ->
  let zonefile =
    let ( / ) = Eio.Path.( / ) in
    Eio.Path.load ((Eio.Stdenv.fs env) / Sys.argv.(1)) in
  main
    ~net:(Eio.Stdenv.net env)
    ~random:(Eio.Stdenv.secure_random env)
    ~clock:(Eio.Stdenv.clock env)
    ~mono_clock:(Eio.Stdenv.mono_clock env)
    ~zonefile
    ~log

let log_packet direction addr buf =
    (match direction with
    | `Rx -> Format.fprintf Format.std_formatter "<-"
    | `Tx -> Format.fprintf Format.std_formatter "->");
    Format.print_space ();
    Eio.Net.Sockaddr.pp Format.std_formatter addr;
    Format.print_space ();
    match Dns.Packet.decode buf with
    | Error _ -> Format.fprintf Format.std_formatter "error";
    | Ok packet -> Dns.Packet.pp Format.std_formatter packet;
    Format.print_space (); Format.print_space ();
    Format.print_flush ()

let () = run log_packet
