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

(** A central location for settings related to xapi *)

module String_plain = String (* For when we don't want the Xstringext version *)
open Xapi_stdext_std.Xstringext

module D = Debug.Make (struct let name = "xapi_globs" end)

(* set this to true to enable XSM to out-of-pool SRs with matching UUID *)
let relax_xsm_sr_check = ref true

(* xapi process returns this code on exit when it wants to be restarted *)
let restart_return_code = 123

let _ =
  Db_globs.restart_fn :=
    fun () ->
      D.info "Executing Db_globs.restart_fn: exiting with code %d"
        restart_return_code ;
      exit restart_return_code

(* - this will usually be a singleton list.
   - during pool secret rotation it will contain multiple elements,
     but the tail will be dropped when it has completed.
   - the head is always the pool secret that should be sent in requests *)
let pool_secrets : SecretString.t list ref = ref []

let pool_secret () =
  match !pool_secrets with
  | [] ->
      failwith
        "the pool secrets either do not exist or have not been loaded yet"
  | x :: _ ->
      x

(* The maximum pool size is restricted to 3 hosts for the pool which does not have Pool_size feature *)
let restricted_pool_size = 3

let localhost_ref : [`host] Ref.t ref = ref Ref.null

(* client min/max version range *)
(* xencenter_min should be the lowest version of XenCenter we want the new server to work with. In the
 * (usual) case that we want to force the user to upgrade XenCenter when they upgrade the server,
 * xencenter_min should equal the current version of XenCenter.
 *
 * xencenter_max is not what you would guess after reading the previous paragraph, which would involve
 * predicting the future. Instead, it should always equal the current version of XenCenter. It must not
 * change without issuing a new version of XenCenter. This is used to make sure that even if the user is
 * not required to upgrade, we at least warn them.
 *
 * In most cases both numbers are the same as the API version. Change them to a hardcoded value if needed.
 * Please consult the XenCenter maintainers before changing these numbers, as XenCenter may need to
 * acquire an SDK aware of the versions specified here. *)
let xencenter_min_verstring =
  Printf.sprintf "%Ld.%Ld" Datamodel.api_version_major
    Datamodel.api_version_minor

let xencenter_max_verstring =
  Printf.sprintf "%Ld.%Ld" Datamodel.api_version_major
    Datamodel.api_version_minor

(* linux pack vsn key in host.software_version (used for a pool join restriction *)
let linux_pack_vsn_key = "xs:linux"

let packs_dir = ref (Filename.concat "/etc/xensource" "installed-repos")

let unix_domain_socket = Filename.concat "/var/lib/xcp" "xapi"

let unix_domain_socket_clientcert =
  Filename.concat "/var/lib/xcp" "xapi-clientcert"

let storage_unix_domain_socket = Filename.concat "/var/lib/xcp" "storage"

let local_database = Filename.concat "/var/lib/xcp" "local.db"

(* if a slave in emergency "cannot see master mode" then this flag is set *)
let slave_emergency_mode = ref false

(** Whenever in emergency mode we stash an error here so the user can determine what's wrong
    without trawling through logfiles *)
let emergency_mode_error =
  ref (Api_errors.Server_error (Api_errors.host_still_booting, []))

let log_config_file = ref (Filename.concat "/etc/xensource" "log.conf")

let remote_db_conf_fragment_path =
  ref (Filename.concat "/etc/xensource" "remote.db.conf")

let cpu_info_file = ref (Filename.concat "/etc/xensource" "boot_time_cpus")

let requires_reboot_file = "/var/run/nonpersistent/xapi/host-requires-reboot"

let ready_file = ref ""

let init_complete = ref ""

(* Keys used in both the software_version (string -> string map) and in the import/export code *)
let _hostname = "hostname"

let _date = "date"

let _product_version = "product_version"

let _product_version_text = "product_version_text"

let _product_version_text_short = "product_version_text_short"

let _platform_name = "platform_name"

let _platform_version = "platform_version"

let _xapi_version = "xapi"

let _product_brand = "product_brand"

let _build_number = "build_number"

let _git_id = "git_id"

let _api_major = "API_major"

let _api_minor = "API_minor"

let _api_vendor = "API_vendor"

let _api_vendor_implementation = "API_vendor_implementation"

let _xapi_major = "xapi_major"

let _xapi_minor = "xapi_minor"

let _export_vsn = "export_vsn"

let _dbv = "dbv"

let _db_schema = "db_schema"

(* When comparing two host versions, always treat a host that has platform_version defined as newer
 * than any host that does not have platform_version defined.
 * Substituting this default when a host does not have platform_version defined will be acceptable,
 * as long as a host never has to distinguish between two hosts of different versions which are both
 * older than itself. *)
let default_platform_version = "0.0.0"

(* Used to differentiate between
   Rio beta2 (0) [no inline checksums, end-of-tar checksum table],
   Rio GA (1) [inline checksums, end-of-tar checksum table]
   and Miami GA (2) [inline checksums, no end-of-tar checksum table] *)
let export_vsn = 2

(* Name of the XML metadata file for VM exports *)
(* This used to be in Xva.xml_filename *)
let ova_xml_filename = "ova.xml"

(** When exporting a VDI in TAR format, the VDI's data will be stored under
    this directory in the archive. *)
let vdi_tar_export_dir = "vdi"

let software_version () =
  (* In the case of XCP, all product_* fields will be blank. *)
  List.filter
    (fun (_, value) -> value <> "")
    [
      (_product_version, Xapi_version.product_version ())
    ; (_product_version_text, Xapi_version.product_version_text ())
    ; (_product_version_text_short, Xapi_version.product_version_text_short ())
    ; (_platform_name, Xapi_version.platform_name ())
    ; (_platform_version, Xapi_version.platform_version ())
    ; (_product_brand, Xapi_version.product_brand ())
    ; (_build_number, Xapi_version.build_number ())
    ; (_git_id, Xapi_version.git_id)
    ; (_hostname, Xapi_version.hostname)
    ; (_date, Xapi_version.date)
    ]

let pygrub_path = "/usr/bin/pygrub"

let eliloader_path = "/usr/bin/eliloader"

let supported_bootloaders =
  [("pygrub", pygrub_path); ("eliloader", eliloader_path)]

(* Deprecated: *)
let is_guest_installer_network = "is_guest_installer_network"

let is_host_internal_management_network = "is_host_internal_management_network"

(* Used to override the check which blocks VM start or migration if a VIF is on an internal
   network which is pinned to a particular host. *)
let assume_network_is_shared = "assume_network_is_shared"

let auto_scan = "auto-scan"

(* if set in SR.other_config, scan the SR in the background *)

let auto_scan_interval = "auto-scan-interval"

(* maybe set in Host.other_config *)

(* These ports are both served up by vncterm the ports used for the RFB and
   text consoles are p+5900 and p+9500 respectively where p is the port
   specified on the vncterm command line:
     -T, --text            provide telnet access too
     -v, --vnclisten       listen for VNC connection at a given address:port
   The init scripts in dom0 spawn vncterm with -T -v 127.0.0.1:0 *)
let host_console_vncport = 5900L

let host_console_textport = 9500L

let vhd_parent = "vhd-parent" (* set in VDIs backed by VHDs *)

let vbd_backend_key = "backend-kind" (* set in VBD other-config *)

let vbd_polling_duration_key = "polling-duration" (* set in VBD other-config *)

let vbd_polling_idle_threshold_key = "polling-idle-threshold"

(* set in VBD other-config *)

let vbd_backend_local_key = "backend-local" (* set in VBD other-config *)

let mac_seed = "mac_seed" (* set in a VM to generate MACs by hash chaining *)

let ( ** ) = Int64.mul

let grant_api_access = "grant_api_access"

(* From Miami GA onward we identify the tools SR with the following SR.other_config key. *)
(* In Dundee we introduced the SR.is_tools_sr field for this purpose, but left the *)
(* other-config key for backwards compat. *)
let tools_sr_tag = "xenserver_tools_sr"

let tools_sr_name () = Xapi_version.product_brand () ^ " Tools"

let tools_sr_description () = tools_sr_name () ^ " ISOs"

let tools_sr_dir = ref "/opt/xensource/packages/iso"

let tools_sr_pbd_device_config =
  [
    ("path", !tools_sr_dir)
  ; (* for ffs *)
    ("location", !tools_sr_dir)
  ; (* for legacy iso *)
    ("legacy_mode", "true")
  ]

let create_tools_sr = ref false

let allow_host_sched_gran_modification = ref false

let default_template_key = "default_template"

let base_template_name_key = "base_template_name"

(* Keys to explain the presence of dom0 block-attached VBDs: *)
let vbd_task_key = "task_id"

let related_to_key = "related_to"

let get_nbd_extents = "/opt/xensource/libexec/get_nbd_extents.py"

(* other-config keys to sync over when mirroring/remapping/importing a VDI *)
let vdi_other_config_sync_keys = ["config-drive"]

(* Set to true on the P2V server template and the tools SR *)
let xensource_internal = "xensource_internal"

(* temporary restore path for db *)
let db_temporary_restore_path = Filename.concat "/var/lib/xcp" "restore_db.db"

(* temporary path for opening a foreign metadata database *)
let foreign_metadata_db = Filename.concat "/var/lib/xcp" "foreign.db"

(* After this we start to delete completed tasks (never pending ones) *)
let max_tasks = 200

(* After this we start to invalidate older sessions *)
(* We must allow for more sessions than running tasks *)
let max_sessions = max_tasks * 2

(* For sessions with specified originator, their session limits are counted independently. *)
let max_sessions_per_originator = 500

(* For sessions with specifiied user name (non-root), their session limit are counted independently *)
let max_sessions_per_user_name = 500

(* Place where database XML backups are kept *)
let backup_db_xml = Filename.concat "/var/lib/xcp" "state-backup.xml"

(* Directory containing scripts which are executed when a node becomes master
   and when a node gives up the master role *)
let master_scripts_dir = ref (Filename.concat "/etc/xensource" "master.d")

(* Indicates whether we should allow clones of suspended VMs via VM.clone *)
let pool_allow_clone_suspended_vm = "allow_clone_suspended_vm"

(* Indicates whether we should allow run-script inside VM *)
let pool_allow_guest_agent_run_script = "allow_guest_agent_run_script"

let i18n_key = "i18n-key"

let i18n_original_value_prefix = "i18n-original-value-"

(* Primitive access control mechanism: CA-12313 *)
let _sm_session = "_sm_session"

(* Mark objects created by an import for CA-11743 on their 'other-config' field *)
let import_task = "import_task"

(* other-config key names where we hack install-time and last-boot-time, to work around the fact that these are not persisted on metrics fields in 4.1
   - see CA-7582 *)
let _install_time_key = "install_time"

let _start_time_key = "start_time"

(* Sync switches *)
(* WARNING WARNING - take great care setting these - it could lead to xapi failing miserably! *)

let sync_switch_off = "nosync"

(* Set the following keys to this value to disable the dbsync operation *)

(* dbsync_slave *)
let sync_local_vdi_activations = "sync_local_vdi_activations"

let sync_create_localhost = "sync_create_localhost"

let sync_set_cache_sr = "sync_set_cache_sr"

let sync_load_rrd = "sync_load_rrd"

let sync_host_display = "sync_host_display"

let sync_refresh_localhost_info = "sync_refresh_localhost_info"

let sync_record_host_memory_properties = "sync_record_host_memory_properties"

let sync_create_host_cpu = "sync_create_host_cpu"

let sync_create_domain_zero = "sync_create_domain_zero"

let sync_crashdump_resynchronise = "sync_crashdump_resynchronise"

let sync_pbds = "sync_pbds"

let sync_pif_params = "sync_pif_params"

let sync_bios_strings = "sync_bios_strings"

let sync_chipset_info = "sync_chipset_info"

let sync_pci_devices = "sync_pci_devices"

let sync_gpus = "sync_gpus"

(* Allow dbsync actions to be disabled via the redo log, since the database
   isn't of much use if xapi won't start. *)
let disable_dbsync_for = ref []

(* create_storage *)
let sync_create_pbds = "sync_create_pbds"

(* sync VLANs on slave with master *)
let sync_vlans = "sync_vlans"

(* Set on the Pool.other_config to signal that the pool is currently in a mixed-mode
   rolling upgrade state. *)
let rolling_upgrade_in_progress = "rolling_upgrade_in_progress"

(* Set on Pool.other_config to override the base HA timeout in a persistent fashion *)
let default_ha_timeout = "default_ha_timeout"

(* Executed during startup when the API/database is online but before storage or networks
   are fully initialised. *)
let startup_script_hook = ref "xapi-startup-script"

(* Executed when a rolling upgrade is detected starting or stopping *)
let rolling_upgrade_script_hook = ref "xapi-rolling-upgrade"

(* Sets IQN and restarts iSCSI daemon if required *)
let set_iSCSI_initiator_script =
  ref "/opt/xensource/libexec/set-iscsi-initiator"

(* Executed during startup when the host is authed with AD
 * or the host is joining or leaving AD *)
let domain_join_cli_cmd = ref "/opt/pbis/bin/domainjoin-cli"

(* sqlite3 database PBIS used to store domain information *)
let pbis_db_path = "/var/lib/pbis/db/registry.db"

(* When set to true indicates that the host has still booted so we're initialising everything
   from scratch e.g. shared storage, sampling boot free mem etc *)
let on_system_boot = ref false

(* Default backlog supplied to Unix.listen *)
let listen_backlog = 128

(* Xapi script hooks root *)
let xapi_hooks_root = ref "/etc/xapi.d"

let xapi_blob_location = Filename.concat "/var/lib/xcp" "blobs"

let last_blob_sync_time = "last_blob_sync_time"

(* Port on which to send network heartbeats *)
let xha_udp_port = 694 (* same as linux-ha *)

(* Port which xapi-clusterd uses to communicate *)
let xapi_clusterd_port = ref 8896

(* Local YUM repo port listened by a stunnel local client.
 * This stunnel client will proxy the access to the internal YUM repo on pool master.
 *)
let local_yum_repo_port = ref 8000

(* When a host is known to be shutting down or rebooting, we add it's reference in here.
   This can be used to force the Host_metrics.live flag to false. *)
let hosts_which_are_shutting_down : API.ref_host list ref = ref []

let hosts_which_are_shutting_down_m = Mutex.create ()

let xha_timeout = "timeout"

let message_limit = ref 10000

let xapi_message_script = ref "mail-alarm"

(* Emit a warning if more than this amount of clock skew detected *)
let max_clock_skew = 5. *. 60. (* 5 minutes *)

(* Optional directory containing XenAPI plugins *)
let xapi_plugins_root = ref "/etc/xapi.d/plugins"

(* Optional directory containing XenAPI extensions *)
let xapi_extensions_root = ref "/etc/xapi.d/extensions"

(** CA-18377: Providing lists of operations that were supported by the Miami release. *)

(** For now, we check against these lists when sending data across the wire that may  *)

(** be read by a Miami host, and remove any items that are not found on the lists.    *)

let host_operations_miami = [`evacuate; `provision]

(* Whether still support intel gvt-g vGPU *)
let gvt_g_supported = ref true

let rpu_allowed_vm_operations =
  [
    `assert_operation_valid
  ; `changing_memory_live
  ; `changing_shadow_memory_live
  ; `changing_VCPUs_live
  ; `clean_reboot
  ; `clean_shutdown
  ; `clone
  ; `copy
  ; `csvm
  ; `destroy
  ; `export
  ; `get_boot_record
  ; `hard_reboot
  ; `hard_shutdown
  ; `import
  ; `make_into_template
  ; `migrate_send
  ; `pause
  ; `pool_migrate
  ; `power_state_reset
  ; `provision
  ; `resume
  ; `resume_on
  ; `send_sysrq
  ; `send_trigger
  ; `start
  ; `start_on
  ; `suspend
  ; `unpause
  ; `update_allowed_operations
  ]

(* Until the Ely release, the vdi_operations enum had stayed unchanged
 * since 2009 or earlier, but then Ely and some subsequent releases
 * added new members to the enum. *)
let pre_ely_vdi_operations =
  [
    `clone
  ; `copy
  ; `resize
  ; `resize_online
  ; `snapshot
  ; `destroy
  ; `forget
  ; `update
  ; `force_unlock
  ; `generate_config
  ; `blocked
  ]

(* We might consider restricting this further. *)
let rpu_allowed_vdi_operations = pre_ely_vdi_operations

(* Viridian key name (goes in platform flags) *)
let viridian_key_name = "viridian"

(* Viridian key value (set in new templates, in built-in templates on upgrade and when Orlando PV drivers up-to-date first detected) *)
let default_viridian_key_value = "true"

let device_id_key_name = "device_id"

(* Host.other_config key to indicate the absence of local storage *)
let host_no_local_storage = "no_local_storage"

(* Pool.other_config key to enable creation of min/max rras in new VM rrds *)
let create_min_max_in_new_VM_RRDs = "create_min_max_in_new_VM_RRDs"

(* Pool.other_config key to enable pass-through of PIF carrier *)
let pass_through_pif_carrier_key = "pass_through_pif_carrier"

(* Don't pass through PIF carrier information by default *)
let pass_through_pif_carrier = ref false

let vgpu_type_id = "type_id"

let igd_passthru_key = "igd_passthrough"

let vgt_low_gm_sz = "vgt_low_gm_sz"

let vgt_high_gm_sz = "vgt_high_gm_sz"

let vgt_fence_sz = "vgt_fence_sz"

let mxgpu_vgpus_per_pgpu = "vgpus_per_pgpu"

let nvidia_vgpu_first_slot_in_guest = 11

let nvidia_host_driver_file = ref "/usr/lib64/libnvidia-vgpu.so"

let nvidia_compat_conf_dir = "/usr/share/nvidia/vgx"

let nvidia_compat_config_file_key = "config_file"

let wlb_timeout = "wlb_timeout"

let wlb_reports_timeout = "wlb_reports_timeout"

let default_wlb_timeout = 30.0

let default_wlb_reports_timeout = 600.0

let cert_expiration_days = ref (365 * 10)

(** {2 Settings relating to dynamic memory control} *)

(** A pool-wide configuration key that specifies for HVM guests a lower bound
    for the ratio k, where (memory-dynamic-min >= k * memory-static-max) *)
let memory_ratio_hvm = ("memory-ratio-hvm", "0.25")

(** A pool-wide configuration key that specifies for PV guests a lower bound
    for the ratio k, where (memory-dynamic-min >= k * memory-static-max) *)
let memory_ratio_pv = ("memory-ratio-pv", "0.25")

(** {2 Settings for the redo-log} *)

(** {3 Settings related to the connection to the block device I/O process} *)

(** The maximum allowed number of redo_log instances. *)
let redo_log_max_instances = 8

(** {3 Settings related to the metadata VDI which hosts the redo log} *)

(** Reason associated with the static VDI attach, to help identify the metadata VDI later (HA) *)
let ha_metadata_vdi_reason = "HA metadata VDI"

(** Reason associated with the static VDI attach, to help identify the metadata VDI later (generic) *)
let gen_metadata_vdi_reason = "general metadata VDI"

(** Pool.other_config key which, when set to the value "true", enables generation of METADATA_LUN_{HEALTHY_BROKEN} alerts *)
let redo_log_alert_key = "metadata_lun_alerts"

(* CP-825: Serialize execution of pool-enable-extauth and pool-disable-extauth *)

(** Mutex for the external authentication in pool *)
let serialize_pool_enable_disable_extauth = Mutex.create ()

(* CP-695: controls our asynchronous persistent initialization of the external authentication service during Xapi.server_init *)

(* Auth types *)
let auth_type_NONE = ""

let auth_type_AD = "AD"

let auth_type_PAM = "PAM"

let event_hook_auth_on_xapi_initialize_succeeded = ref false

(** {2 CPUID feature masking} *)

let cpu_info_vendor_key = "vendor"

let cpu_info_features_key = "features"

let cpu_info_features_pv_key = "features_pv"

let cpu_info_features_hvm_key = "features_hvm"

let cpu_info_features_pv_host_key = "features_pv_host"

let cpu_info_features_hvm_host_key = "features_hvm_host"

(** Metrics *)

let metrics_root = "/dev/shm/metrics"

let metrics_prefix_mem_host = "xcp-rrdd-mem_host"

let metrics_prefix_mem_vms = "xcp-rrdd-mem_vms"

let metrics_prefix_pvs_proxy = "pvsproxy-"

(** Path to trigger file for Network Reset. *)
let network_reset_trigger = "/tmp/network-reset"

let first_boot_dir = "/etc/firstboot.d/"

(** {2 Xenopsd metadata persistence} *)

let persist_xenopsd_md = "persist_xenopsd_md"

let persist_xenopsd_md_root = Filename.concat "/var/lib/xcp" "xenopsd_md"

(** {Host updates directory} *)
let host_update_dir = ref "/var/update"

let qemu_dm_ready_timeout = ref 300.

(* Time we allow for the hotplug scripts to run before we assume something bad
   has happened and abort *)
let hotplug_timeout = ref 300.

let pif_reconfigure_ip_timeout = ref 300.

(* CA-16878: 5 minutes, same as the local database flush *)
let pool_db_sync_interval = ref 300.

(* blob/message/rrd file syncing - sync once a day *)
let pool_data_sync_interval = ref 86400.

let domain_shutdown_total_timeout = ref 1200.

(* The actual reboot delay will be a random value between base and base + extra *)
let emergency_reboot_delay_base = ref 60.

let emergency_reboot_delay_extra = ref 120.

let ha_xapi_healthcheck_interval = ref 60

let ha_xapi_healthcheck_timeout = ref 120

(* > the number of attempts in xapi-health-check script *)

let ha_xapi_restart_attempts = ref 1

let ha_xapi_restart_timeout = ref 300

(* 180s is max start delay and 60s max shutdown delay in the initscript *)

(* Logrotate - poll the amount of data written out by the logger, and call
   logrotate when it exceeds the threshold *)
let logrotate_check_interval = ref 300.

let rrd_backup_interval = ref 86400.

(* CP-703: Periodic revalidation of externally-authenticated sessions *)
let session_revalidation_interval = ref 300. (* every 5 minutes *)

(* CP-820: other-config field in subjects should be periodically refreshed *)
let update_all_subjects_interval = ref 900. (* every 15 minutes *)

(* The default upper bound on the length of time to wait for a running VM to
   reach its current memory target. *)
let wait_memory_target_timeout = ref 256.

let snapshot_with_quiesce_timeout = ref 600.

(* Interval between host heartbeats *)
let host_heartbeat_interval = ref 30.

(* If we haven't heard a heartbeat from a host for this interval then the host is assumed dead *)
let host_assumed_dead_interval = ref 600.0

(* If a session has a last_active older than this we delete it *)
let inactive_session_timeout = ref 86400. (* 24 hrs in seconds *)

let pending_task_timeout = ref 86400. (* 24 hrs in seconds *)

let completed_task_timeout = ref 3900. (* 65 mins *)

(* Don't reboot a domain which crashes too quickly: *)
let minimum_time_between_bounces = ref 120. (* 2 minutes *)

(* If a domain is rebooted (from inside) in less than this time since it last
   started, then insert an artificial delay: *)
let minimum_time_between_reboot_with_no_added_delay = ref 60. (* 1 minute *)

let ha_monitor_interval = ref 20.

(* Unconditionally replan every once in a while just in case the overcommit
   protection is buggy and we don't notice *)
let ha_monitor_plan_interval = ref 1800.

let ha_monitor_startup_timeout = ref 1800.

let ha_default_timeout_base = ref 60.

let guest_liveness_timeout = ref 300.

(** The default time, in µs, in which tapdisk3 will keep polling the vbd ring buffer in expectation for extra requests from the guest *)
let default_vbd3_polling_duration = ref 1000

(** The default % of idle dom0 cpu above which tapdisk3 will keep polling the vbd ring buffer *)
let default_vbd3_polling_idle_threshold = ref 50

(** The minimal time gap between attempts to call plugin on a particular VM *)
let vm_call_plugin_interval = ref 10.

(** The maximum number of SR scans allowed concurrently *)
let max_active_sr_scans = ref 32

let nowatchdog = ref false

let log_getter = ref false

(* Path to the pool secret file. *)
let pool_secret_path = ref (Filename.concat "/etc/xensource" "ptoken")

(* Path to server ssl certificate *)
let server_cert_path = ref (Filename.concat "/etc/xensource" "xapi-ssl.pem")

(* The group id of server ssl certificate file *)
let server_cert_group_id = ref (-1)

(* Path to server certificate used for host-to-host TLS connections *)
let server_cert_internal_path =
  ref (Filename.concat "/etc/xensource" "xapi-pool-tls.pem")

let c_rehash = ref "c_rehash"

let trusted_certs_dir = ref "/etc/stunnel/certs"

let trusted_pool_certs_dir = ref "/etc/stunnel/certs-pool"

let stunnel_bundle_path = ref "/etc/stunnel/xapi-stunnel-ca-bundle.pem"

let pool_bundle_path = ref "/etc/stunnel/xapi-pool-ca-bundle.pem"

let stunnel_conf = ref "/etc/stunnel/xapi.conf"

let udhcpd_conf = ref (Filename.concat "/etc/xensource" "udhcpd.conf")

let udhcpd_skel = ref (Filename.concat "/etc/xensource" "udhcpd.skel")

let udhcpd_leases_db = ref "/var/lib/xcp/dhcp-leases.db"

let udhcpd_pidfile = ref "/var/run/udhcpd.pid"

let iscsi_initiator_config_file = ref "/etc/iscsi/initiatorname.iscsi"

let multipathing_config_file = ref "/var/run/nonpersistent/multipath_enabled"

let busybox = ref "busybox"

let xe_path = ref "xe"

let pbis_force_domain_leave_script = ref "pbis-force-domain-leave"

let sparse_dd = ref "sparse_dd"

let vhd_tool = ref "vhd-tool"

let fence = ref "fence"

let host_bugreport_upload = ref "host-bugreport-upload"

let set_hostname = ref "set-hostname"

let xe_syslog_reconfigure = ref "xe-syslog-reconfigure"

let logs_download = ref "logs-download"

let update_mh_info_script = ref "update-mh-info"

let upload_wrapper = ref "upload-wrapper"

let host_backup = ref "host-backup"

let host_restore = ref "host-restore"

let xe_toolstack_restart = ref "xe-toolstack-restart"

let xsh = ref "xsh"

let static_vdis = ref "static-vdis"

let sm_dir = ref "/opt/xensource/sm"

let web_dir = ref "/opt/xensource/www"

let hsts_max_age = ref (-1)

let website_https_only = ref true

let migration_https_only = ref true

let cluster_stack_root = ref "/usr/libexec/xapi/cluster-stack"

let cluster_stack_default = ref "xhad"

let xen_cmdline_path = ref "/opt/xensource/libexec/xen-cmdline"

let post_install_scripts_dir =
  ref "/opt/xensource/packages/post-install-scripts"

let gpg_homedir = ref "/opt/xensource/gpg"

let update_issue_script = ref "update-issue"

let kill_process_script = ref "killall"

let nbd_firewall_config_script =
  ref "/opt/xensource/libexec/nbd-firewall-config.sh"

let firewall_port_config_script = ref "/etc/xapi.d/plugins/firewall-port"

let nbd_client_manager_script =
  ref "/opt/xensource/libexec/nbd_client_manager.py"

let varstore_rm = ref "/usr/bin/varstore-rm"

let varstore_dir = ref "/var/lib/varstored"

let default_auth_dir = ref "/usr/share/varstored"

let override_uefi_certs = ref false

let disable_logging_for = ref []

let nvidia_whitelist = ref "/usr/share/nvidia/vgpu/vgpuConfig.xml"

let nvidia_sriov_manage_script = ref "/usr/lib/nvidia/sriov-manage"

let igd_passthru_vendor_whitelist = ref []

let gvt_g_whitelist = ref "/etc/gvt-g-whitelist"

let mxgpu_whitelist = ref "/etc/mxgpu-whitelist"

let xen_livepatch_list = ref "/usr/sbin/xen-livepatch list"

let kpatch_list = ref "/usr/sbin/kpatch list"

let modprobe_path = ref "/usr/sbin/modprobe"

let usb_path = "usb_path"

let local_pool_repo_dir = ref "/var/lib/yum-mirror"

(* The bfs-interfaces script returns boot from SAN NICs.
 * All ISCSI Boot Firmware Table (ibft) NICs should be marked
 * with PIF.managed = false and all FCoE boot from SAN * NICs
 * should be set with disallow-unplug=true, during a PIF.scan. *)
let non_managed_pifs = ref "/opt/xensource/libexec/bfs-interfaces"

let fcoe_driver = ref "/opt/xensource/libexec/fcoe_driver"

let list_domains = ref "/usr/bin/list_domains"

let systemctl = ref "/usr/bin/systemctl"

let xen_cmdline_script = ref "/opt/xensource/libexec/xen-cmdline"

let alert_certificate_check = ref "alert-certificate-check"

let sr_health_check_task_label = "SR Recovering"

let domain_zero_domain_type = `pv

let gen_pool_secret_script = ref "/usr/bin/pool_secret_wrapper"

let repository_domain_name_allowlist = ref []

let yum_cmd = ref "/usr/bin/yum"

let kpatch_cmd = ref "/usr/sbin/kpatch"

let xen_livepatch_cmd = ref "/usr/sbin/xen-livepatch"

let xl_cmd = ref "/usr/sbin/xl"

let yum_repos_config_dir = ref "/etc/yum.repos.d"

let remote_repository_prefix = ref "remote"

let local_repository_prefix = ref "local"

let yum_config_manager_cmd = ref "/usr/bin/yum-config-manager"

let reposync_cmd = ref "/usr/bin/reposync"

let createrepo_cmd = ref "/usr/bin/createrepo_c"

let modifyrepo_cmd = ref "/usr/bin/modifyrepo_c"

let repoquery_cmd = ref "/usr/bin/repoquery"

let rpm_cmd = ref "/usr/bin/rpm"

let rpm_gpgkey_dir = ref "/etc/pki/rpm-gpg"

let repository_gpgkey_name = ref ""

let repository_gpgcheck = ref true

let ignore_vtpm_unimplemented = ref false

let evacuation_batch_size = ref 10

type xapi_globs_spec_ty = Float of float ref | Int of int ref

let extauth_ad_backend = ref "winbind"

let net_cmd = ref "/usr/bin/net"

let wb_cmd = ref "/usr/bin/wbinfo"

let winbind_debug_level = ref 2

let winbind_cache_time = ref 60

let winbind_machine_pwd_timeout = ref (2. *. 7. *. 24. *. 3600.)

let winbind_update_closest_kdc_interval = ref (3600. *. 22.)
(* every 22 hours *)

let winbind_kerberos_encryption_type = ref Kerberos_encryption_types.Winbind.All

let winbind_allow_kerberos_auth_fallback = ref false

let winbind_keep_configuration = ref false

let winbind_ldap_query_subject_timeout = ref 20.

let tdb_tool = ref "/usr/bin/tdbtool"

let sqlite3 = ref "/usr/bin/sqlite3"

let samba_dir = "/var/lib/samba"

let header_read_timeout_tcp = ref 10.
(* Timeout in seconds for every read while reading HTTP headers (on TCP only) *)

let header_total_timeout_tcp = ref 60.
(* Timeout in seconds to receive all HTTP headers (on TCP only) *)

let max_header_length_tcp = ref 1024
(* Maximum accepted size of HTTP headers in bytes (on TCP only) *)

let conn_limit_tcp = ref 800

let conn_limit_unix = ref 1024

let conn_limit_clientcert = ref 800

let trace_log_dir = ref "/var/log/dt/zipkinv2/json"

let export_interval = ref 30.

let max_spans = ref 1000

let max_traces = ref 10000

let prefer_nbd_attach = ref false

(** 1 MiB *)
let max_observer_file_size = ref (1 lsl 20)

let xapi_globs_spec =
  [
    ( "master_connection_reset_timeout"
    , Float Db_globs.master_connection_reset_timeout
    )
  ; ( "master_connection_retry_timeout"
    , Float Db_globs.master_connection_retry_timeout
    )
  ; ( "master_connection_default_timeout"
    , Float Db_globs.master_connection_default_timeout
    )
  ; ("qemu_dm_ready_timeout", Float qemu_dm_ready_timeout)
  ; ("hotplug_timeout", Float hotplug_timeout)
  ; ("pif_reconfigure_ip_timeout", Float pif_reconfigure_ip_timeout)
  ; ("pool_db_sync_interval", Float pool_db_sync_interval)
  ; ("pool_data_sync_interval", Float pool_data_sync_interval)
  ; ("domain_shutdown_total_timeout", Float domain_shutdown_total_timeout)
  ; ("emergency_reboot_delay_base", Float emergency_reboot_delay_base)
  ; ("emergency_reboot_delay_extra", Float emergency_reboot_delay_extra)
  ; ("ha_xapi_healthcheck_interval", Int ha_xapi_healthcheck_interval)
  ; ("ha_xapi_healthcheck_timeout", Int ha_xapi_healthcheck_timeout)
  ; ("ha_xapi_restart_attempts", Int ha_xapi_restart_attempts)
  ; ("ha_xapi_restart_timeout", Int ha_xapi_restart_timeout)
  ; ("logrotate_check_interval", Float logrotate_check_interval)
  ; ("rrd_backup_interval", Float rrd_backup_interval)
  ; ("session_revalidation_interval", Float session_revalidation_interval)
  ; ("update_all_subjects_interval", Float update_all_subjects_interval)
  ; ("wait_memory_target_timeout", Float wait_memory_target_timeout)
  ; ("snapshot_with_quiesce_timeout", Float snapshot_with_quiesce_timeout)
  ; ("host_heartbeat_interval", Float host_heartbeat_interval)
  ; ("host_assumed_dead_interval", Float host_assumed_dead_interval)
  ; ("fuse_time", Float Constants.fuse_time)
  ; ("db_restore_fuse_time", Float Constants.db_restore_fuse_time)
  ; ("inactive_session_timeout", Float inactive_session_timeout)
  ; ("pending_task_timeout", Float pending_task_timeout)
  ; ("completed_task_timeout", Float completed_task_timeout)
  ; ("minimum_time_between_bounces", Float minimum_time_between_bounces)
  ; ( "minimum_time_between_reboot_with_no_added_delay"
    , Float minimum_time_between_reboot_with_no_added_delay
    )
  ; ("ha_monitor_interval", Float ha_monitor_interval)
  ; ("ha_monitor_plan_interval", Float ha_monitor_plan_interval)
  ; ("ha_monitor_startup_timeout", Float ha_monitor_startup_timeout)
  ; ("ha_default_timeout_base", Float ha_default_timeout_base)
  ; ("guest_liveness_timeout", Float guest_liveness_timeout)
  ; ( "permanent_master_failure_retry_interval"
    , Float Db_globs.permanent_master_failure_retry_interval
    )
  ; ( "redo_log_max_block_time_empty"
    , Float Db_globs.redo_log_max_block_time_empty
    )
  ; ("redo_log_max_block_time_read", Float Db_globs.redo_log_max_block_time_read)
  ; ( "redo_log_max_block_time_writedelta"
    , Float Db_globs.redo_log_max_block_time_writedelta
    )
  ; ( "redo_log_max_block_time_writedb"
    , Float Db_globs.redo_log_max_block_time_writedb
    )
  ; ("redo_log_max_startup_time", Float Db_globs.redo_log_max_startup_time)
  ; ("redo_log_connect_delay", Float Db_globs.redo_log_connect_delay)
  ; ("default-vbd3-polling-duration", Int default_vbd3_polling_duration)
  ; ( "default-vbd3-polling-idle-threshold"
    , Int default_vbd3_polling_idle_threshold
    )
  ; ("vm_call_plugin_interval", Float vm_call_plugin_interval)
  ; ("xapi_clusterd_port", Int xapi_clusterd_port)
  ; ("max_active_sr_scans", Int max_active_sr_scans)
  ; ("winbind_debug_level", Int winbind_debug_level)
  ; ("winbind_cache_time", Int winbind_cache_time)
  ; ("winbind_machine_pwd_timeout", Float winbind_machine_pwd_timeout)
  ; ( "winbind_update_closest_kdc_interval"
    , Float winbind_update_closest_kdc_interval
    )
  ; ("header_read_timeout_tcp", Float header_read_timeout_tcp)
  ; ("header_total_timeout_tcp", Float header_total_timeout_tcp)
  ; ("max_header_length_tcp", Int max_header_length_tcp)
  ; ("conn_limit_tcp", Int conn_limit_tcp)
  ; ("conn_limit_unix", Int conn_limit_unix)
  ; ("conn_limit_clientcert", Int conn_limit_clientcert)
  ; ("export_interval", Float export_interval)
  ; ("max_spans", Int max_spans)
  ; ("max_traces", Int max_traces)
  ; ("max_observer_file_size", Int max_observer_file_size)
  ]

let options_of_xapi_globs_spec =
  List.map
    (fun (name, ty) ->
      ( name
      , (match ty with Float x -> Arg.Set_float x | Int x -> Arg.Set_int x)
      , (fun () ->
          match ty with
          | Float x ->
              string_of_float !x
          | Int x ->
              string_of_int !x
        )
      , Printf.sprintf "Set the value of '%s'" name
      )
    )
    xapi_globs_spec

let xenopsd_queues =
  ref
    [
      "org.xen.xapi.xenops.classic"
    ; "org.xen.xapi.xenops.simulator"
    ; "org.xen.xapi.xenops.xenlight"
    ]

let default_xenopsd = ref "org.xen.xapi.xenops.xenlight"

let gpumon_stop_timeout = ref 10.0

let reboot_required_hfxs = ref "/run/reboot-required.hfxs"

(* Fingerprint of default patch key *)
let citrix_patch_key =
  "NERDNTUzMDMwRUMwNDFFNDI4N0M4OEVCRUFEMzlGOTJEOEE5REUyNg=="

let trusted_patch_key = ref citrix_patch_key

let gen_list_option name desc of_string string_of opt =
  let parse s =
    opt := [] ;
    try
      String.split_f String.isspace s
      |> List.iter (fun x -> opt := of_string x :: !opt)
    with e ->
      D.error "Unable to parse %s=%s (expected space-separated list) error: %s"
        name s (Printexc.to_string e)
  and get () =
    List.map string_of !opt |> String.concat "; " |> Printf.sprintf "[ %s ]"
  in
  (name, Arg.String parse, get, desc)

let sm_plugins = ref []

let accept_sm_plugin name =
  List.(
    fold_left ( || ) false
      (map
         (function
           | `All ->
               true
           | `Sm x ->
               String.lowercase_ascii x = String.lowercase_ascii name
           )
         !sm_plugins
      )
  )

let nvidia_multi_vgpu_enabled_driver_versions =
  ref ["430.42"; "430.62"; "440.00+"]

let nvidia_default_host_driver_version = "0.0"

type nvidia_t4_sriov = Nvidia_T4_SRIOV | Nvidia_LEGACY | Nvidia_DEFAULT

let nvidia_t4_sriov = ref Nvidia_DEFAULT

(** CP-41126. true - we are detaching the NVML library in gpumon; false -
    we stop gpumon. *)
let nvidia_gpumon_detach = ref false

let failed_login_alert_freq = ref 3600

let other_options =
  [
    gen_list_option "sm-plugins"
      "space-separated list of storage plugins to allow."
      (fun x -> if x = "*" then `All else `Sm x)
      (fun x -> match x with `All -> "*" | `Sm x -> x)
      sm_plugins
  ; ( "hotfix-fingerprint"
    , Arg.Set_string trusted_patch_key
    , (fun () -> !trusted_patch_key)
    , "Fingerprint of the key used for signed hotfixes"
    )
  ; ( "logconfig"
    , Arg.Set_string log_config_file
    , (fun () -> !log_config_file)
    , "Log config file to use"
    )
  ; ( "writereadyfile"
    , Arg.Set_string ready_file
    , (fun () -> !ready_file)
    , "touch specified file when xapi is ready to accept requests"
    )
  ; ( "writeinitcomplete"
    , Arg.Set_string init_complete
    , (fun () -> !init_complete)
    , "touch specified file when xapi init process is complete"
    )
  ; ( "nowatchdog"
    , Arg.Set nowatchdog
    , (fun () -> string_of_bool !nowatchdog)
    , "turn watchdog off, avoiding initial fork"
    )
  ; ( "log-getter"
    , Arg.Set log_getter
    , (fun () -> string_of_bool !log_getter)
    , "Enable/Disable logging for getters"
    )
  ; ( "onsystemboot"
    , Arg.Set on_system_boot
    , (fun () -> string_of_bool !on_system_boot)
    , "indicates that this server start is the first since the host rebooted"
    )
  ; ( "relax-xsm-sr-check"
    , Arg.Set relax_xsm_sr_check
    , (fun () -> string_of_bool !relax_xsm_sr_check)
    , "allow storage migration when SRs have been mirrored out-of-band (and \
       have matching SR uuids)"
    )
  ; gen_list_option "disable-logging-for"
      "space-separated list of modules to suppress logging from"
      (fun s -> s)
      (fun s -> s)
      disable_logging_for
  ; gen_list_option "disable-dbsync-for"
      "space-separated list of database synchronisation actions to skip"
      (fun s -> s)
      (fun s -> s)
      disable_dbsync_for
  ; ( "xenopsd-queues"
    , Arg.String (fun x -> xenopsd_queues := String.split ',' x)
    , (fun () -> String.concat "," !xenopsd_queues)
    , "list of xenopsd instances to manage"
    )
  ; ( "xenopsd-default"
    , Arg.Set_string default_xenopsd
    , (fun () -> !default_xenopsd)
    , "default xenopsd to use"
    )
  ; ( "nvidia-whitelist"
    , Arg.Set_string nvidia_whitelist
    , (fun () -> !nvidia_whitelist)
    , "path to the NVidia vGPU whitelist file"
    )
  ; gen_list_option "igd-passthru-vendor-whitelist"
      "list of PCI vendor IDs for integrated graphics passthrough \
       (space-separated)"
      (fun s ->
        D.debug "Whitelisting PCI vendor %s for passthrough" s ;
        Scanf.sscanf s "%4Lx" (fun _ -> s)
      ) (* Scanf verifies format *)
      (fun s -> s)
      igd_passthru_vendor_whitelist
  ; ( "gvt-g-whitelist"
    , Arg.Set_string gvt_g_whitelist
    , (fun () -> !gvt_g_whitelist)
    , "path to the GVT-g whitelist file"
    )
  ; ( "gvt-g-supported"
    , Arg.Set gvt_g_supported
    , (fun () -> string_of_bool !gvt_g_supported)
    , "indicates that this server still support intel gvt_g vGPU"
    )
  ; ( "mxgpu-whitelist"
    , Arg.Set_string mxgpu_whitelist
    , (fun () -> !mxgpu_whitelist)
    , "path to the AMD whitelist file"
    )
  ; ( "pass-through-pif-carrier"
    , Arg.Set pass_through_pif_carrier
    , (fun () -> string_of_bool !pass_through_pif_carrier)
    , "reflect physical interface carrier information to VMs by default"
    )
  ; ( "cluster-stack-default"
    , Arg.Set_string cluster_stack_default
    , (fun () -> !cluster_stack_default)
    , "Default cluster stack (HA)"
    )
  ; ( "gpumon_stop_timeout"
    , Arg.Set_float gpumon_stop_timeout
    , (fun () -> string_of_float !gpumon_stop_timeout)
    , "Time to wait after attempting to stop gpumon when launching a \
       vGPU-enabled VM."
    )
  ; ( "reboot_required_hfxs"
    , Arg.Set_string reboot_required_hfxs
    , (fun () -> !reboot_required_hfxs)
    , "File to query hotfix uuids which require reboot"
    )
  ; ( "xen_livepatch_list"
    , Arg.Set_string xen_livepatch_list
    , (fun () -> !xen_livepatch_list)
    , "Command to query current xen livepatch list"
    )
  ; ( "kpatch_list"
    , Arg.Set_string kpatch_list
    , (fun () -> !kpatch_list)
    , "Command to query current kernel patch list"
    )
  ; ( "modprobe_path"
    , Arg.Set_string modprobe_path
    , (fun () -> !modprobe_path)
    , "Location of the modprobe(8) command: should match $(which modprobe)"
    )
  ; ( "db_idempotent_map"
    , Arg.Set Db_globs.idempotent_map
    , (fun () -> string_of_bool !Db_globs.idempotent_map)
    , "True if the add_to_<map> API calls should be idempotent"
    )
  ; ( "nvidia_multi_vgpu_enabled_driver_versions"
    , Arg.String
        (fun x ->
          nvidia_multi_vgpu_enabled_driver_versions := String.split ',' x
        )
    , (fun () -> String.concat "," !nvidia_multi_vgpu_enabled_driver_versions)
    , "list of nvidia host driver versions with multiple vGPU supported.\n\
      \  if a version end with +, it means any driver version greater or equal \
       than that version"
    )
  ; ( "nvidia_t4_sriov"
    , Arg.String
        (function
        | "true" | "on" | "1" ->
            nvidia_t4_sriov := Nvidia_T4_SRIOV
        | "false" | "off" | "0" ->
            nvidia_t4_sriov := Nvidia_LEGACY
        | "default" | "xml" | _ ->
            nvidia_t4_sriov := Nvidia_DEFAULT
        )
    , (fun () ->
        match !nvidia_t4_sriov with
        | Nvidia_DEFAULT ->
            "default - Infer NVidia GPU addressing mode from vgpuConfig.xml"
        | Nvidia_LEGACY ->
            "false - Use legacy mode for NVidia GPU addressing"
        | Nvidia_T4_SRIOV ->
            "true - Use SR-IOV for NVidia T4 GPUs, legacy otherwise"
      )
    , "Use of SR-IOV for Nvidia GPUs; 'true', 'false', 'default'."
    )
  ; ( "create-tools-sr"
    , Arg.Set create_tools_sr
    , (fun () -> string_of_bool !create_tools_sr)
    , "Indicates whether to create an SR for Tools ISOs"
    )
  ; ( "allow-host-sched-gran-modification"
    , Arg.Set allow_host_sched_gran_modification
    , (fun () -> string_of_bool !allow_host_sched_gran_modification)
    , "Allows to modify the host's scheduler granularity"
    )
  ; ( "extauth_ad_backend"
    , Arg.Set_string extauth_ad_backend
    , (fun () -> !extauth_ad_backend)
    , "Which AD backend used to talk to DC"
    )
  ; ( "winbind_kerberos_encryption_type"
    , Arg.String
        (fun s ->
          Option.iter
            (fun k -> winbind_kerberos_encryption_type := k)
            (Kerberos_encryption_types.Winbind.of_string s)
        )
    , (fun () ->
        Kerberos_encryption_types.Winbind.to_string
          !winbind_kerberos_encryption_type
      )
    , "Encryption types to use when operating as Kerberos client \
       [strong|legacy|all]"
    )
  ; ( "winbind_allow_kerberos_auth_fallback"
    , Arg.Set winbind_allow_kerberos_auth_fallback
    , (fun () -> string_of_bool !winbind_allow_kerberos_auth_fallback)
    , "Whether to allow fallback to other auth on kerberos failure"
    )
  ; ( "winbind_keep_configuration"
    , Arg.Set winbind_keep_configuration
    , (fun () -> string_of_bool !winbind_keep_configuration)
    , "Whether to clear winbind configuration when join domain failed or leave \
       domain"
    )
  ; ( "winbind_ldap_query_subject_timeout"
    , Arg.Set_float winbind_ldap_query_subject_timeout
    , (fun () -> string_of_float !winbind_ldap_query_subject_timeout)
    , "Timeout to perform ldap query for subject information"
    )
  ; ( "hsts_max_age"
    , Arg.Set_int hsts_max_age
    , (fun () -> string_of_int !hsts_max_age)
    , "number of seconds after the reception of the STS header field, during \
       which the UA as a known HSTS Host (default = -1 means HSTS is disabled)"
    )
  ; ( "website-https-only"
    , Arg.Set website_https_only
    , (fun () -> string_of_bool !website_https_only)
    , "Allow access to the internal website using HTTPS only (no HTTP)"
    )
  ; ( "migration-https-only"
    , Arg.Set migration_https_only
    , (fun () -> string_of_bool !migration_https_only)
    , "Exclusively use HTTPS for VM migration"
    )
  ; gen_list_option "repository-domain-name-allowlist"
      "space-separated list of allowed domain name in base URL in repository."
      (fun s -> s)
      (fun s -> s)
      repository_domain_name_allowlist
  ; ( "repository-gpgcheck"
    , Arg.Set repository_gpgcheck
    , (fun () -> string_of_bool !repository_gpgcheck)
    , "turn gpgcheck on/off"
    )
  ; ( "repository-gpgkey-name"
    , Arg.Set_string repository_gpgkey_name
    , (fun () -> !repository_gpgkey_name)
    , "The default name of gpg key file used by YUM and RPM to verify metadata \
       and packages in repository"
    )
  ; ( "failed-login-alert-freq"
    , Arg.Set_int failed_login_alert_freq
    , (fun () -> string_of_int !failed_login_alert_freq)
    , "Frequency at which we alert any failed logins (in seconds; \
       default=3600s)"
    )
  ; ( "cert-expiration-days"
    , Arg.Set_int cert_expiration_days
    , (fun () -> string_of_int !cert_expiration_days)
    , "Number of days a refreshed certificate will be valid; it defaults to 10 \
       years."
    )
  ; ( "messages-limit"
    , Arg.Set_int message_limit
    , (fun () -> string_of_int !message_limit)
    , "Maximum number of messages kept before deleting oldest ones."
    )
  ; ( "evacuation-batch-size"
    , Arg.Set_int evacuation_batch_size
    , (fun () -> string_of_int !evacuation_batch_size)
    , "The number of VMs evacauted from a host in parallel."
    )
  ; ( "ignore-vtpm-unimplemented"
    , Arg.Set ignore_vtpm_unimplemented
    , (fun () -> string_of_bool !ignore_vtpm_unimplemented)
    , "Do not raise errors on use-cases where VTPM codepaths are not finished."
    )
  ; ( "override-uefi-certs"
    , Arg.Set override_uefi_certs
    , (fun () -> string_of_bool !override_uefi_certs)
    , "Enable (true) or Disable (false) overriding location for varstored UEFI \
       certificates"
    )
  ; ( "server-cert-group-id"
    , Arg.Set_int server_cert_group_id
    , (fun () -> string_of_int !server_cert_group_id)
    , "The group id of server ssl certificate file."
    )
  ; ( "export-interval"
    , Arg.Set_float export_interval
    , (fun () -> string_of_float !export_interval)
    , "The interval for exports in Tracing"
    )
  ; ( "max-spans"
    , Arg.Set_int max_spans
    , (fun () -> string_of_int !max_spans)
    , "The maximum amount of spans that can be in a trace in Tracing"
    )
  ; ( "max-traces"
    , Arg.Set_int max_traces
    , (fun () -> string_of_int !max_traces)
    , "The maximum number of active traces going on in Tracing"
    )
  ; ( "prefer-nbd-attach"
    , Arg.Set prefer_nbd_attach
    , (fun () -> string_of_bool !prefer_nbd_attach)
    , "Use NBD to attach disks to the control domain."
    )
  ; ( "observer-max-file-size"
    , Arg.Set_int max_observer_file_size
    , (fun () -> string_of_int !max_observer_file_size)
    , "The maximum size of log files for saving spans"
    )
  ; ( "nvidia-gpumon-detach"
    , Arg.Set nvidia_gpumon_detach
    , (fun () -> string_of_bool !nvidia_gpumon_detach)
    , "On VM start, detach the NVML library rather than stopping gpumon"
    )
  ]

(* The options can be set with the variable xapiflags in /etc/sysconfig/xapi.
   e.g. xapiflags=-nowatchdog *)

let all_options = options_of_xapi_globs_spec @ other_options

(* VIRTUAL HARDWARE PLATFORM VERSIONS *)

let has_vendor_device = 2L

(* This set is used as an indicator to show the virtual hardware
   platform versions the current host offers to its guests *)
let host_virtual_hardware_platform_versions =
  [
    (* Zero is the implicit version offered by hosts older than this
       	   versioning concept, and the version implicitly required by old
       	   guests that do not specify a version. *)
    0L
  ; (* Version one is the version in which this versioning concept was
       	   introduced. This Virtual Hardware Platform might not differ
       	   significantly from the immediately preceding version zero, but
       	   it seems prudent to introduce a way to differentiate it from
       	   the whole history of older host versions. *)
    1L
  ; (* Version two which is "has_vendor_device" will be the first virtual
       		hardware platform version to offer the option of an emulated PCI
       		device used to trigger a guest to install or upgrade its PV tools
       		(originally introduced to exploit the Windows Update system). *)
    has_vendor_device
  ]

module Resources = struct
  let essential_executables =
    [
      ("busybox", busybox, "Swiss army knife executable - used as DHCP server")
    ; ( "pbis-force-domain-leave-script"
      , pbis_force_domain_leave_script
      , "Executed when PBIS domain-leave fails"
      )
    ; ( "redo-log-block-device-io"
      , Db_globs.redo_log_block_device_io
      , "Used by the redo log for block device I/O"
      )
    ; ("sparse_dd", sparse_dd, "Path to sparse_dd")
    ; ("vhd-tool", vhd_tool, "Path to vhd-tool")
    ; ("fence", fence, "Path to fence binary, used for HA host fencing")
    ; ( "host-bugreport-upload"
      , host_bugreport_upload
      , "Path to host-bugreport-upload"
      )
    ; ("set-hostname", set_hostname, "Path to set-hostname")
    ; ( "xe-syslog-reconfigure"
      , xe_syslog_reconfigure
      , "Path to xe-syslog-reconfigure"
      )
    ; ( "logs-download"
      , logs_download
      , "Used by /get_host_logs_download HTTP handler"
      )
    ; ( "update-mh-info"
      , update_mh_info_script
      , "Executed when changing the management interface"
      )
    ; ("upload-wrapper", upload_wrapper, "Used by Host_crashdump.upload")
    ; ("host-backup", host_backup, "Path to host-backup")
    ; ("host-restore", host_restore, "Path to host-restore")
    ; ("xe", xe_path, "Path to xe CLI binary")
    ; ( "xe-toolstack-restart"
      , xe_toolstack_restart
      , "Path to xe-toolstack-restart script"
      )
    ; ("xsh", xsh, "Path to xsh binary")
    ; ("static-vdis", static_vdis, "Path to static-vdis script")
    ; ("xen-cmdline-script", xen_cmdline_script, "Path to xen-cmdline script")
    ; ( "fcoe-driver"
      , fcoe_driver
      , "Execute during PIF unplug to get the lun devices related with the \
         ether interface of the PIF"
      )
    ; ("list_domains", list_domains, "Path to the list_domains command")
    ; ("systemctl", systemctl, "Control the systemd system and service manager")
    ; ( "alert-certificate-check"
      , alert_certificate_check
      , "Path to alert-certificate-check, which generates alerts on \
         about-to-expire server certificates."
      )
    ; ( "gencert"
      , Constants.gencert
      , "command to generate SSL certificates to be used by XAPI"
      )
    ; ( "openssl_path"
      , Constants.openssl_path
      , "Path for openssl command to generate RSA keys"
      )
    ; ( "set-iscsi-initiator"
      , set_iSCSI_initiator_script
      , "Path to set-iscsi-initiator script"
      )
    ; ("yum-cmd", yum_cmd, "Path to yum command")
    ; ("reposync-cmd", reposync_cmd, "Path to reposync command")
    ; ("createrepo-cmd", createrepo_cmd, "Path to createrepo command")
    ; ("modifyrepo-cmd", modifyrepo_cmd, "Path to modifyrepo command")
    ; ("rpm-cmd", rpm_cmd, "Path to rpm command")
    ; ( "yum-config-manager-cmd"
      , yum_config_manager_cmd
      , "Path to yum-config-manager command"
      )
    ; ("c_rehash", c_rehash, "Path to Regenerate CA store")
    ]

  let nonessential_executables =
    [
      ("startup-script-hook", startup_script_hook, "Executed during startup")
    ; ( "rolling-upgrade-script-hook"
      , rolling_upgrade_script_hook
      , "Executed when a rolling upgrade is detected starting or stopping"
      )
    ; ( "xapi-message-script"
      , xapi_message_script
      , "Executed when messages are generated if email feature is disabled"
      )
    ; ( "non-managed-pifs"
      , non_managed_pifs
      , "Executed during PIF.scan to find out which NICs should not be managed \
         by xapi"
      )
    ; ( "domain_join_cli_cmd"
      , domain_join_cli_cmd
      , "Command to manage pbis related service"
      )
    ; ( "update-issue"
      , update_issue_script
      , "Running update-service when configuring the management interface"
      )
    ; ("killall", kill_process_script, "Executed to kill process")
    ; ( "nbd-firewall-config"
      , nbd_firewall_config_script
      , "Executed after NBD-related networking changes to configure the \
         firewall for NBD"
      )
    ; ( "firewall-port-config"
      , firewall_port_config_script
      , "Executed when starting/stopping xapi-clusterd to configure firewall \
         port"
      )
    ; ( "nbd_client_manager"
      , nbd_client_manager_script
      , "Executed to safely connect to and disconnect from NBD devices using \
         nbd-client"
      )
    ; ( "varstore-rm"
      , varstore_rm
      , "Executed to clear certain UEFI variables during clone"
      )
    ; ("varstore_dir", varstore_dir, "Path to local varstored directory")
    ; ( "nvidia-sriov-manage"
      , nvidia_sriov_manage_script
      , "Path to NVIDIA sriov-manage script"
      )
    ; ( "gen_pool_secret_script"
      , gen_pool_secret_script
      , "Generates new pool secrets"
      )
    ; ( "samba administration tool"
      , net_cmd
      , "Executed to manage external auth with AD like join and leave domain"
      )
    ; ( "Samba TDB (Trivial Database) management tool"
      , tdb_tool
      , "Executed to manage Samba Database"
      )
    ; ("winbind query tool", wb_cmd, "Query information from winbind daemon")
    ; ( "SQLite database  management tool"
      , sqlite3
      , "Executed to manage SQlite Database, like PBIS database"
      )
    ]

  let essential_files =
    [
      ("pool_config_file", Constants.pool_config_file, "Pool configuration file")
    ; ("db-config-file", Db_globs.db_conf_path, "Database configuration file")
    ; ("udhcpd-skel", udhcpd_skel, "Skeleton config for udhcp")
    ]

  let nonessential_files =
    [
      ("pool_secret_path", pool_secret_path, "Pool configuration file")
    ; ("udhcpd-conf", udhcpd_conf, "Optional configuration file for udchp")
    ; ( "remote-db-conf-file"
      , remote_db_conf_fragment_path
      , "Where to store information about remote databases"
      )
    ; ("logconfig", log_config_file, "Configure the logging policy")
    ; ("cpu-info-file", cpu_info_file, "Where to cache boot-time CPU info")
    ; ("server-cert-path", server_cert_path, "Path to server ssl certificate")
    ; ( "server-cert-internal-path"
      , server_cert_internal_path
      , "Path to server certificate used for host-to-host TLS connections"
      )
    ; ( "stunnel-bundle-path"
      , stunnel_bundle_path
      , "Path to stunnel trust bundle"
      )
    ; ("pool-bundle-path", pool_bundle_path, "Path to pool trust bundle")
    ; ( "iscsi_initiatorname"
      , iscsi_initiator_config_file
      , "Path to the initiatorname.iscsi file"
      )
    ]

  let essential_dirs =
    [
      ("sm-dir", sm_dir, "Directory containing SM plugins")
    ; ("web-dir", web_dir, "Directory to export fileserver")
    ; ( "cluster-stack-root"
      , cluster_stack_root
      , "Directory containing collections of HA tools and scripts"
      )
    ; ("xen-cmdline", xen_cmdline_path, "Path to xen-cmdline binary")
    ; ("gpg-homedir", gpg_homedir, "Passed as --homedir to gpg commands")
    ; ( "post-install-scripts-dir"
      , post_install_scripts_dir
      , "Directory containing trusted guest provisioning scripts"
      )
    ]

  let nonessential_dirs =
    [
      ( "master-scripts-dir"
      , master_scripts_dir
      , "Scripts to execute when transitioning pool role"
      )
    ; ("packs-dir", packs_dir, "Directory containing supplemental pack data")
    ; ("xapi-hooks-root", xapi_hooks_root, "Root directory for xapi hooks")
    ; ( "xapi-plugins-root"
      , xapi_plugins_root
      , "Optional directory containing XenAPI plugins"
      )
    ; ( "xapi-extensions-root"
      , xapi_extensions_root
      , "Optional directory containing XenAPI extensions"
      )
    ; ( "static-vdis-root"
      , Db_globs.static_vdis_dir
      , "Optional directory for configuring static VDIs"
      )
    ; ("tools-sr-dir", tools_sr_dir, "Directory containing tools ISO")
    ; ( "trusted-pool-certs-dir"
      , trusted_pool_certs_dir
      , "Directory containing certs of trusted hosts"
      )
    ; ( "trusted-certs-dir"
      , trusted_certs_dir
      , "Directory containing certs of other trusted entities"
      )
    ; ( "trace-log-dir"
      , trace_log_dir
      , "Directory for storing traces exported to logs"
      )
    ]

  let xcp_resources =
    let make_resource perms essential (name, path, description) =
      {Xcp_service.essential; name; description; path; perms}
    in
    let open Unix in
    List.fold_left List.rev_append []
      [
        List.map (make_resource [X_OK] true) essential_executables
      ; List.map (make_resource [X_OK] false) nonessential_executables
      ; List.map (make_resource [R_OK; W_OK] true) essential_files
      ; List.map (make_resource [R_OK; W_OK] false) nonessential_files
      ; List.map (make_resource [R_OK; W_OK] true) essential_dirs
      ; List.map (make_resource [R_OK; W_OK] false) nonessential_dirs
      ]
end
