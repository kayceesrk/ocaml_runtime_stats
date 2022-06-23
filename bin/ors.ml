module H = Hdr_histogram

open Runtime_events

let monitored_pid = ref None
let current_event = Hashtbl.create 13

let hist =
  H.init ~lowest_discernible_value:10 ~highest_trackable_value:10_000_000_000
         ~significant_figures:3

let print_percentiles () =
  let ms ns = ns /. 1000000. in
  Printf.eprintf "\n";
  Printf.eprintf "#[Mean (ms):\t%.2f,\t Stddev (ms):\t%.2f]\n"
    (H.mean hist |> ms) (H.stddev hist |> ms);
  Printf.eprintf "#[Min (ms):\t%.2f,\t max (ms):\t%.2f]\n"
    (float_of_int (H.min hist) |> ms) (float_of_int (H.max hist) |> ms);

  Printf.eprintf "\n";
  let percentiles = [| 50.0; 75.0; 90.0; 99.0; 99.9; 99.99; 99.999; 100.0 |] in
  Printf.eprintf "percentile \t latency (ms)\n";
  Fun.flip Array.iter percentiles (fun p -> Printf.eprintf "%.4f \t %.2f\n" p
    (float_of_int (H.value_at_percentile hist p) |> ms))

let lifecycle _domain_id _ts lifecycle_event data =
    match lifecycle_event with
    | EV_RING_START ->
        begin match data with
        | Some pid ->
            assert (pid = Option.get !monitored_pid);
            Printf.eprintf "[pid=%d] Ring started\n%!" pid
        | None -> assert false
        end
    | EV_RING_STOP ->
        let pid = Option.get !monitored_pid in
        Printf.eprintf "[pid=%d] Ring ended\n%!" pid;
        print_percentiles ();
        ignore @@ Unix.waitpid [] pid;
        Unix.unlink (string_of_int pid ^ ".events");
        H.close hist;
        exit 0
    | _ -> ()

let runtime_begin domain_id ts phase =
  match Hashtbl.find_opt current_event domain_id with
  | None -> Hashtbl.add current_event domain_id (phase, Timestamp.to_int64 ts)
  | _ -> ()

let runtime_end domain_id ts phase =
  match Hashtbl.find_opt current_event domain_id with
  | Some (saved_phase, saved_ts) when (saved_phase = phase) ->
      Hashtbl.remove current_event domain_id;
      let latency =
        Int64.to_int (Int64.sub (Timestamp.to_int64 ts) saved_ts)
      in
      assert (H.record_value hist latency)
  | _ -> ()

let lost_events _domain_id num =
  Printf.eprintf "[pid=%d] Lost %d events\n%!" (Option.get !monitored_pid) num

let () =
  let cmd = Sys.argv.(1) in
  let cmd_list = String.split_on_char ' ' cmd in
  let systemenv = Unix.environment () in
  let pid =
    Unix.(create_process_env (List.hd cmd_list) (Array.of_list cmd_list)
      (Array.append [| "OCAML_RUNTIME_EVENTS_START=1";
                       "OCAML_RUNTIME_EVENTS_PRESERVE=1" |] systemenv)
      stdin stdout stderr)
  in
  monitored_pid := Some pid;
  Printf.eprintf "[pid=%d] Command started\n%!" pid;
  let cwd = Unix.getcwd () in

  Unix.sleepf 0.1;
  let cursor = create_cursor (Some (cwd, pid)) in
  let callbacks =
    Callbacks.create ~runtime_begin ~runtime_end ~lifecycle ~lost_events ()
  in
  let rec loop () =
    let n = read_poll cursor callbacks None in
    if n = 0 then Domain.cpu_relax ();
    loop ()
  in
  loop ()
