module H = Hdr_histogram

open Runtime_events

let monitored_pid = ref None
let current_event = ref None

let hist =
  H.init ~lowest_discernible_value:10 ~highest_trackable_value:10_000_000_000
         ~significant_figures:3

let print_percentiles () =
  let percentiles = [| 50.0; 75.0; 90.0; 99.0; 99.9; 99.99; 99.999; 100.0 |] in

  Printf.eprintf "\n";
  Printf.eprintf "#[Mean (ns):\t%d,\t Stddev (ns):\t%d]\n"
    (int_of_float (H.mean hist)) (int_of_float (H.stddev hist));
  Printf.eprintf "#[Min (ns):\t%d,\t max (ns):\t%d]\n"
    (H.min hist) (H.max hist);

  Printf.eprintf "\n";
  Printf.eprintf "percentile \t latency (ns)\n";
  Fun.flip Array.iter percentiles (fun p ->
    Printf.eprintf "%f \t %d\n" p (H.value_at_percentile hist p))

let lifecycle _domain_id _ts lifecycle_event data =
    match lifecycle_event with
    | EV_RING_START ->
        begin match data with
        | Some pid ->
            assert (pid = Option.get !monitored_pid);
            Printf.eprintf "[pid=%d] Ring started\n" pid
        | None -> assert false
        end
    | EV_RING_STOP ->
        Printf.eprintf "[pid=%d] Ring ended\n" (Option.get !monitored_pid);
        print_percentiles ();
        H.close hist;
        exit 0
    | _ -> ()

let runtime_begin _domain_id ts phase =
  match !current_event with
  | None -> current_event := Some (phase, Timestamp.to_int64 ts)
  | _ -> ()

let runtime_end _domain_id ts phase =
  match !current_event with
  | Some (saved_phase, saved_ts) when (saved_phase = phase) ->
      current_event := None;
      let latency =
        Int64.to_int (Int64.sub (Timestamp.to_int64 ts) saved_ts)
      in
      assert (H.record_value hist latency)
  | _ -> ()

let lost_events _domain_id num =
  Printf.eprintf "[pid=%d] Lost %d events\n" (Option.get !monitored_pid) num

let () =
  let cmd = Sys.argv.(1) in
  let cmd_list = String.split_on_char ' ' cmd in
  let pid =
    Unix.(create_process_env (List.hd cmd_list)
      (Array.of_list (List.tl cmd_list))
      [| "OCAML_RUNTIME_EVENTS_START=1"; "OCAML_RUNTIME_EVENTS_PRESERVE=1" |]
      stdin stdout stderr)
  in
  monitored_pid := Some pid;
  Printf.eprintf "[pid=%d] Command started\n" pid;
  let cwd = Unix.getcwd () in

  Unix.sleepf 0.1;
  let cursor = create_cursor (Some (cwd, pid)) in
  let callbacks =
    Callbacks.create ~runtime_begin ~runtime_end ~lifecycle ~lost_events ()
  in
  let rec loop () =
    ignore @@ read_poll cursor callbacks None;
    loop ()
  in
  loop ()
