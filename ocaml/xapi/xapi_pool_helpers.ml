(*
 * Copyright (C) 2006-2009 Citrix Systems Inc.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; version 2.1 only. with the special
 * exception on linking described in file LICENSE.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *)

module D = Debug.Make (struct let name = "xapi_pool_helpers" end)

open D
open Client
open Record_util

let finally = Xapi_stdext_pervasives.Pervasiveext.finally

(* psr is not included as a pool op because it can be considered in progress
   in between api calls (i.e. wrapping it inside with_pool_operation won't work) *)

(* these ops will:
 * a) throw an error if any other blocked op is in progress
 * b) wait if only a wait op is in progress
 *)
let blocking_ops =
  [
    (`ha_enable, Api_errors.ha_enable_in_progress)
  ; (`ha_disable, Api_errors.ha_disable_in_progress)
  ; (`cluster_create, Api_errors.cluster_create_in_progress)
  ; (`designate_new_master, Api_errors.designate_new_master_in_progress)
  ; (`tls_verification_enable, Api_errors.tls_verification_enable_in_progress)
  ; (`configure_repositories, Api_errors.configure_repositories_in_progress)
  ; (`sync_updates, Api_errors.sync_updates_in_progress)
  ; (`get_updates, Api_errors.get_updates_in_progress)
  ; (`apply_updates, Api_errors.apply_updates_in_progress)
  ]

(* generally these ops will happen internally. example: rather than blocking
 * `ha_enable if a `copy_primary_host_certs is in progress, we should wait.
 *
 * waiting is symmetric: if `ha_enable is in progress, and we want to perform
 * `copy_primary_host_certs, then we wait in this case too *)
let wait_ops =
  [
    `cert_refresh
  ; `exchange_certificates_on_join
  ; `exchange_ca_certificates_on_join
  ; `copy_primary_host_certs
  ]

let all_operations = blocking_ops |> List.map fst |> List.append wait_ops

(* see [Helpers.retry]. this error code causes a 'wait' *)
let wait_error = Api_errors.other_operation_in_progress

(** Returns a table of operations -> API error options (None if the operation would be ok) *)
let valid_operations ~__context record (pool : API.ref_pool) =
  let ref = Ref.string_of pool in
  let current_ops = List.map snd record.Db_actions.pool_current_operations in
  let table = Hashtbl.create 10 in
  all_operations |> List.iter (fun x -> Hashtbl.replace table x None) ;
  let set_errors (code : string) (params : string list)
      (ops : API.pool_allowed_operations_set) =
    List.iter
      (fun op ->
        if Hashtbl.find table op = None then
          Hashtbl.replace table op (Some (code, params))
      )
      ops
  in
  if current_ops <> [] then (
    List.iter
      (fun (blocking_op, err) ->
        if List.mem blocking_op current_ops then (
          set_errors err [] (blocking_ops |> List.map fst) ;
          set_errors Api_errors.other_operation_in_progress
            [Datamodel_common._pool; ref]
            wait_ops
        )
      )
      blocking_ops ;
    List.iter
      (fun wait_op ->
        if List.mem wait_op current_ops then
          set_errors wait_error [Datamodel_common._pool; ref] all_operations
      )
      wait_ops
  ) ;
  (* HA disable cannot run if HA is already disabled on a pool *)
  (* HA enable cannot run if HA is already enabled on a pool *)
  let ha_enabled =
    Db.Pool.get_ha_enabled ~__context ~self:(Helpers.get_pool ~__context)
  in
  let current_stack =
    Db.Pool.get_ha_cluster_stack ~__context ~self:(Helpers.get_pool ~__context)
  in
  if ha_enabled then (
    set_errors Api_errors.ha_is_enabled [] [`ha_enable] ;
    (* TLS verification is not allowed to run if HA is enabled *)
    set_errors Api_errors.ha_is_enabled [] [`tls_verification_enable]
  ) else
    set_errors Api_errors.ha_not_enabled [] [`ha_disable] ;
  (* cluster create cannot run during a rolling pool upgrade *)
  if Helpers.rolling_upgrade_in_progress ~__context then (
    set_errors Api_errors.not_supported_during_upgrade [] [`cluster_create] ;
    set_errors Api_errors.not_supported_during_upgrade []
      [`tls_verification_enable]
  ) ;
  (* cluster create cannot run if a cluster already exists on the pool *)
  ( match Db.Cluster.get_all ~__context with
  | [_] ->
      set_errors Api_errors.cluster_already_exists [] [`cluster_create]
  (* indicates a bug or a need to update this code (if we ever support multiple clusters in the pool *)
  | _ :: _ ->
      failwith "Multiple clusters exist in the pool"
  (* cluster create cannot run if ha is already enabled *)
  | [] ->
      if ha_enabled then
        set_errors Api_errors.incompatible_cluster_stack_active [current_stack]
          [`cluster_create]
  ) ;
  table

let throw_error table op =
  if not (Hashtbl.mem table op) then
    raise
      (Api_errors.Server_error
         ( Api_errors.internal_error
         , [
             Printf.sprintf
               "xapi_pool_helpers.assert_operation_valid unknown operation: %s"
               (pool_operation_to_string op)
           ]
         )
      ) ;
  match Hashtbl.find table op with
  | Some (code, params) ->
      raise (Api_errors.Server_error (code, params))
  | None ->
      ()

let assert_operation_valid ~__context ~self ~(op : API.pool_allowed_operations)
    =
  (* no pool operations allowed during a pending PSR *)
  if Db.Pool.get_is_psr_pending ~__context ~self:(Helpers.get_pool ~__context)
  then
    raise Api_errors.(Server_error (pool_secret_rotation_pending, [])) ;
  let all = Db.Pool.get_record_internal ~__context ~self in
  let table = valid_operations ~__context all self in
  throw_error table op

let update_allowed_operations ~__context ~self : unit =
  let all = Db.Pool.get_record_internal ~__context ~self in
  let valid = valid_operations ~__context all self in
  let keys =
    Hashtbl.fold (fun k v acc -> if v = None then k :: acc else acc) valid []
  in
  Db.Pool.set_allowed_operations ~__context ~self ~value:keys

(** Add to the Pool's current operations, call a function and then remove from the
    current operations. Ensure the allowed_operations are kept up to date. *)
let with_pool_operation ~__context ~self ~doc ~op f =
  let task_id = Ref.string_of (Context.get_task_id __context) in
  Helpers.retry_with_global_lock ~__context ~doc (fun () ->
      assert_operation_valid ~__context ~self ~op ;
      Db.Pool.add_to_current_operations ~__context ~self ~key:task_id ~value:op
  ) ;
  update_allowed_operations ~__context ~self ;
  (* Then do the action with the lock released *)
  finally f (* Make sure to clean up at the end *) (fun () ->
      try
        Db.Pool.remove_from_current_operations ~__context ~self ~key:task_id ;
        update_allowed_operations ~__context ~self ;
        Helpers.Early_wakeup.broadcast
          (Datamodel_common._pool, Ref.string_of self)
      with _ -> ()
  )

let is_pool_op_in_progress op ~__context =
  let pool = Helpers.get_pool ~__context in
  let current_ops = Db.Pool.get_current_operations ~__context ~self:pool in
  List.exists (fun (_, op') -> op = op') current_ops

let ha_enable_in_progress = is_pool_op_in_progress `ha_enable

let ha_disable_in_progress = is_pool_op_in_progress `ha_disable

let assert_no_pool_ops ~__context =
  let pool = Helpers.get_pool ~__context in
  match Db.Pool.get_current_operations ~__context ~self:pool with
  | [] ->
      ()
  | ops ->
      let err =
        ops
        |> List.map snd
        |> List.map Record_util.pool_operation_to_string
        |> String.concat "; "
        |> Printf.sprintf "pool operations in progress: [ %s ]"
      in
      raise Api_errors.(Server_error (internal_error, [err]))

let get_master_slaves_list_with_fn ~__context fn =
  let _unsorted_hosts = Db.Host.get_all ~__context in
  let master = Helpers.get_master ~__context in
  let slaves = List.filter (fun h -> h <> master) _unsorted_hosts in
  (* anything not a master *)
  debug "MASTER=%s, SLAVES=%s"
    (Db.Host.get_name_label ~__context ~self:master)
    (List.fold_left
       (fun str h -> str ^ "," ^ Db.Host.get_name_label ~__context ~self:h)
       "" slaves
    ) ;
  fn master slaves

(* returns the list of hosts in the pool, with the master being the first element of the list *)
let get_master_slaves_list ~__context =
  get_master_slaves_list_with_fn ~__context (fun master slaves ->
      master :: slaves
  )

(* returns the list of slaves in the pool *)
let get_slaves_list ~__context =
  get_master_slaves_list_with_fn ~__context (fun _ slaves -> slaves)

let call_fn_on_hosts ~__context hosts f =
  Helpers.call_api_functions ~__context (fun rpc session_id ->
      let errs =
        List.filter_map
          (fun host ->
            try f ~rpc ~session_id ~host ; None with x -> Some (host, x)
          )
          hosts
      in
      List.iter
        (fun (host, exn) ->
          warn {|Exception raised while performing operation on host "%s": %s|}
            (Ref.string_of host)
            (ExnHelper.string_of_exn exn)
        )
        errs ;
      match errs with [] -> () | (_, first_exn) :: _ -> raise first_exn
  )

let call_fn_on_master_then_slaves ~__context f =
  let hosts = get_master_slaves_list ~__context in
  call_fn_on_hosts ~__context hosts f

(* Note: fn exposed in .mli *)

(** Call the function on the slaves first. When those calls have all
 *  returned, call the function on the master. *)
let call_fn_on_slaves_then_master ~__context f =
  (* Get list with master as LAST element: important for ssl_legacy calls *)
  let hosts = List.rev (get_master_slaves_list ~__context) in
  call_fn_on_hosts ~__context hosts f

let apply_guest_agent_config ~__context =
  let f ~rpc ~session_id ~host =
    try Client.Host.apply_guest_agent_config ~rpc ~session_id ~host
    with e ->
      error "Failed to apply guest agent config to host %s: %s"
        (Db.Host.get_uuid ~__context ~self:host)
        (Printexc.to_string e)
  in
  call_fn_on_slaves_then_master ~__context f
