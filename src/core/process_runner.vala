/* src/core/process_runner.vala
 * Subprocess execution manager with process group isolation (PGID),
 * guaranteed safe termination (SIGTERM -> SIGKILL), and asynchronous stream capture.
 */

namespace Daemonette {

    public class ProcessRunner : Object {
        private ServiceManager service_manager;
        private Gee.HashMap<string, ActiveProcess> active_processes;
        private Gee.HashMap<string, LogRingBuffer> log_buffers;

        public signal void output_received (string service_id, string line, bool is_stderr);
        public signal void status_changed (string service_id, ServiceStatus new_status);
        public signal void service_crashed (ServiceDefinition service, int exit_code, int term_signal);

        private class ActiveProcess : Object {
            public string service_id;
            public GLib.Subprocess subprocess;
            public int pid;
            public int pgid;
            public bool stopping_manually;
            public uint kill_timeout_id;
            public GLib.Cancellable cancellable;

            public ActiveProcess (string service_id, GLib.Subprocess subp, int pid, int pgid) {
                this.service_id = service_id;
                this.subprocess = subp;
                this.pid = pid;
                this.pgid = pgid;
                this.stopping_manually = false;
                this.kill_timeout_id = 0;
                this.cancellable = new GLib.Cancellable ();
            }
        }

        public ProcessRunner (ServiceManager service_manager) {
            this.service_manager = service_manager;
            this.active_processes = new Gee.HashMap<string, ActiveProcess> ();
            this.log_buffers = new Gee.HashMap<string, LogRingBuffer> ();

            this.service_manager.services_reloaded.connect (() => {
                sync_docker_services_status ();
            });
        }

        public LogRingBuffer get_log_buffer (string service_id) {
            if (!log_buffers.has_key (service_id)) {
                int max_lines = service_manager.settings.max_log_lines;
                log_buffers.set (service_id, new LogRingBuffer (max_lines));
            }
            return log_buffers.get (service_id);
        }

        public bool is_running (string service_id) {
            if (active_processes.has_key (service_id)) {
                return true;
            }
            var s = service_manager.get_service (service_id);
            if (s != null && (s.service_type == ServiceType.COMPOSE || s.service_type == ServiceType.DOCKER)) {
                return s.status == ServiceStatus.RUNNING || s.status == ServiceStatus.STARTING;
            }
            return false;
        }

        public int get_pid (string service_id) {
            if (active_processes.has_key (service_id)) {
                return active_processes.get (service_id).pid;
            }
            return 0;
        }

        public int get_pgid (string service_id) {
            if (active_processes.has_key (service_id)) {
                return active_processes.get (service_id).pgid;
            }
            return 0;
        }

        /**
         * Starts a service with its default command or a specific variant.
         */
        public bool start_service (ServiceDefinition service, string? variant_id = null) {
            if (is_running (service.id)) {
                GLib.warning ("Service '%s' is already running.", service.name);
                return false;
            }

            if (service.service_type == ServiceType.COMPOSE || service.service_type == ServiceType.DOCKER) {
                return start_docker_service (service, variant_id);
            }

            service.status = ServiceStatus.STARTING;
            status_changed (service.id, service.status);

            // 1. Determine effective command, URL, and use_shell setting
            string effective_command = service.command;
            bool effective_use_shell = service.use_shell;

            ServiceVariant? variant = resolve_variant (service, variant_id);
            if (variant != null) {
                effective_command = variant.command;
                effective_use_shell = variant.use_shell;
            }

            // 2. Resolve cascading environment variables
            string[] envp = build_effective_environment (service, variant);

            // 3. Prepare execution arguments
            string[]? argv = resolve_command_argv (effective_command, effective_use_shell, service.name);
            if (argv == null) {
                service.status = ServiceStatus.FAILED;
                status_changed (service.id, service.status);
                return false;
            }

            // 4. Configure SubprocessLauncher with independent process group
            var launcher = create_subprocess_launcher (service.working_directory, envp);

            // 5. Spawn subprocess
            GLib.Subprocess subp;
            try {
                subp = launcher.spawnv (argv);
            } catch (GLib.Error e) {
                GLib.warning ("Failed to spawn process for '%s': %s", service.name, e.message);
                service.status = ServiceStatus.FAILED;
                status_changed (service.id, service.status);
                return false;
            }

            int pid = int.parse (subp.get_identifier ());
            int pgid = pid; // Child process became process group leader via setpgid(0, 0)

            var active = new ActiveProcess (service.id, subp, pid, pgid);
            active_processes.set (service.id, active);

            // Update model
            service.status = ServiceStatus.RUNNING;
            service.active_variant_id = variant_id;
            service.metrics.reset ();
            service.metrics.pid = pid;
            service.metrics.pgid = pgid;
            service.metrics.started_at = new GLib.DateTime.now_local ();
            status_changed (service.id, service.status);

            var buffer = get_log_buffer (service.id);
            string variant_tag = "";
            if (variant != null) {
                string v_icon = (variant.icon != null && variant.icon.strip () != "") ? variant.icon.strip () : "⚡";
                variant_tag = " | %s %s".printf (v_icon, variant.name);
            }
            string header_info = "--- [Started: %s | PID: %d | PGID: %d%s] ---".printf (
                service.name,
                pid,
                pgid,
                variant_tag
            );
            buffer.append (header_info, false);
            output_received (service.id, header_info, false);

            // 6. Connect asynchronous readers for stdout and stderr
            attach_stream_readers (service.id, subp, buffer, active.cancellable);

            // 7. Await process exit asynchronously
            wait_for_exit.begin (service, subp, active);

            return true;
        }

        public ServiceVariant? resolve_variant (ServiceDefinition service, string? variant_id) {
            if (variant_id == null || variant_id.strip () == "") {
                return null;
            }
            return service.find_variant (variant_id);
        }

        private static string? cached_user_shell_path = null;
        private static bool shell_path_probed = false;

        public static string resolve_user_shell () {
            unowned string? user_shell = GLib.Environment.get_variable ("SHELL");
            if (user_shell != null && user_shell.strip () != "" && GLib.FileUtils.test (user_shell, GLib.FileTest.IS_EXECUTABLE)) {
                return user_shell;
            }
            if (GLib.FileUtils.test ("/bin/bash", GLib.FileTest.IS_EXECUTABLE)) {
                return "/bin/bash";
            }
            return "/bin/sh";
        }

        public static string get_cached_user_shell_path () {
            if (shell_path_probed) {
                return cached_user_shell_path ?? "";
            }
            shell_path_probed = true;
            cached_user_shell_path = probe_user_shell_path ();
            return cached_user_shell_path ?? "";
        }

        private static string? probe_user_shell_path () {
            string shell = resolve_user_shell ();

            // Delimiters to isolate PATH from potential shell startup messages or MOTD
            string start_marker = "___DAEMONETTE_PATH_START___";
            string end_marker = "___DAEMONETTE_PATH_END___";
            string probe_cmd = "printf \"%s%s%s\" \"" + start_marker + "\" \"$PATH\" \"" + end_marker + "\"";

            string[] argv = { shell, "-i", "-c", probe_cmd };

            var cancellable = new GLib.Cancellable ();
            new GLib.Thread<void*> ("shell-probe-watchdog", () => {
                GLib.Thread.usleep (1500000); // 1.5 seconds safety timeout
                cancellable.cancel ();
                return null;
            });

            string? probed_path = null;
            try {
                var subp = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string stdout_buf;
                subp.communicate_utf8 (null, cancellable, out stdout_buf, null);

                if (stdout_buf != null && stdout_buf.contains (start_marker)) {
                    int s_idx = stdout_buf.index_of (start_marker) + start_marker.length;
                    int e_idx = stdout_buf.index_of (end_marker, s_idx);
                    if (e_idx > s_idx) {
                        probed_path = stdout_buf.substring (s_idx, e_idx - s_idx).strip ();
                    }
                }
            } catch (GLib.Error e) {
                // If interactive probe timed out or failed, fallback logic applies
            }

            string fallback = fallback_user_paths ();
            if (probed_path != null && probed_path != "") {
                return merge_paths ({ probed_path, fallback });
            }
            return fallback;
        }

        private static string fallback_user_paths () {
            string home = GLib.Environment.get_home_dir ();
            var paths = new Gee.ArrayList<string> ();

            string[] candidates = {
                GLib.Path.build_filename (home, ".local", "bin"),
                GLib.Path.build_filename (home, ".cargo", "bin"),
                GLib.Path.build_filename (home, ".bun", "bin"),
                GLib.Path.build_filename (home, ".local", "share", "pnpm"),
                "/usr/local/bin",
                "/usr/local/go/bin"
            };

            foreach (var c in candidates) {
                if (GLib.FileUtils.test (c, GLib.FileTest.IS_DIR)) {
                    paths.add (c);
                }
            }

            // Also check for Node versions under NVM
            string nvm_versions_dir = GLib.Path.build_filename (home, ".nvm", "versions", "node");
            if (GLib.FileUtils.test (nvm_versions_dir, GLib.FileTest.IS_DIR)) {
                try {
                    var dir = GLib.Dir.open (nvm_versions_dir);
                    string? entry = null;
                    while ((entry = dir.read_name ()) != null) {
                        string bin_path = GLib.Path.build_filename (nvm_versions_dir, entry, "bin");
                        if (GLib.FileUtils.test (bin_path, GLib.FileTest.IS_DIR)) {
                            paths.add (bin_path);
                        }
                    }
                } catch (GLib.Error e) {
                    // Ignore directory read error
                }
            }

            return merge_paths (paths.to_array ());
        }

        public static string merge_paths (string[] path_segments) {
            var seen = new Gee.HashSet<string> ();
            var result = new Gee.ArrayList<string> ();

            foreach (var segment in path_segments) {
                if (segment == null || segment.strip () == "") {
                    continue;
                }
                string[] parts = segment.split (":");
                foreach (var part in parts) {
                    string clean = part.strip ();
                    if (clean != "" && !seen.contains (clean)) {
                        seen.add (clean);
                        result.add (clean);
                    }
                }
            }

            return string.joinv (":", result.to_array ());
        }

        public string[] build_effective_environment (ServiceDefinition service, ServiceVariant? variant = null) {
            string[] envp = GLib.Environ.get ();

            // 1. Comprehensive developer PATH resolution
            string base_path = GLib.Environ.get_variable (envp, "PATH") ?? "";
            string shell_path = get_cached_user_shell_path ();

            var path_segments = new Gee.ArrayList<string> ();

            // Project-local binaries have highest execution priority
            if (service.working_directory.strip () != "") {
                string node_modules_bin = GLib.Path.build_filename (service.working_directory, "node_modules", ".bin");
                if (GLib.FileUtils.test (node_modules_bin, GLib.FileTest.IS_DIR)) {
                    path_segments.add (node_modules_bin);
                }

                string dot_venv_bin = GLib.Path.build_filename (service.working_directory, ".venv", "bin");
                if (GLib.FileUtils.test (dot_venv_bin, GLib.FileTest.IS_DIR)) {
                    path_segments.add (dot_venv_bin);
                } else {
                    string venv_bin = GLib.Path.build_filename (service.working_directory, "venv", "bin");
                    if (GLib.FileUtils.test (venv_bin, GLib.FileTest.IS_DIR)) {
                        path_segments.add (venv_bin);
                    }
                }
            }

            if (shell_path != "") {
                path_segments.add (shell_path);
            }
            if (base_path != "") {
                path_segments.add (base_path);
            }

            string effective_path = merge_paths (path_segments.to_array ());
            envp = GLib.Environ.set_variable ((owned) envp, "PATH", effective_path, true);

            // Ensure SHELL is defined in environment
            string shell = resolve_user_shell ();
            envp = GLib.Environ.set_variable ((owned) envp, "SHELL", shell, false);

            if (service.load_dotenv && service.working_directory.strip () != "") {
                var dotenv_vars = service_manager.parse_dotenv (service.working_directory);
                foreach (var entry in dotenv_vars.entries) {
                    envp = GLib.Environ.set_variable ((owned) envp, entry.key, entry.value, true);
                }
            }

            foreach (var entry in service.environment.entries) {
                envp = GLib.Environ.set_variable ((owned) envp, entry.key, entry.value, true);
            }

            if (variant != null) {
                foreach (var entry in variant.environment.entries) {
                    envp = GLib.Environ.set_variable ((owned) envp, entry.key, entry.value, true);
                }
            }

            return envp;
        }

        public string[]? resolve_command_argv (string command, bool use_shell, string service_name) {
            if (use_shell) {
                string shell = resolve_user_shell ();
                return new string[] { shell, "-c", command };
            }

            try {
                string[] argv;
                GLib.Shell.parse_argv (command, out argv);
                return argv;
            } catch (GLib.ShellError e) {
                GLib.warning ("Command syntax error for '%s': %s", service_name, e.message);
                return null;
            }
        }

        private GLib.SubprocessLauncher create_subprocess_launcher (string working_directory, string[] envp) {
            var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);

            if (working_directory.strip () != "") {
                launcher.set_cwd (working_directory);
            }

            launcher.set_environ (envp);
            launcher.set_child_setup (() => {
                Posix.setpgid (0, 0);
            });

            return launcher;
        }

        private void attach_stream_readers (string service_id, GLib.Subprocess subp, LogRingBuffer buffer, GLib.Cancellable cancellable) {
            var stdout_pipe = subp.get_stdout_pipe ();
            if (stdout_pipe != null) {
                read_stream_lines.begin (service_id, stdout_pipe, false, buffer, cancellable);
            }

            var stderr_pipe = subp.get_stderr_pipe ();
            if (stderr_pipe != null) {
                read_stream_lines.begin (service_id, stderr_pipe, true, buffer, cancellable);
            }
        }

        private async void wait_for_exit (ServiceDefinition service, GLib.Subprocess subp, ActiveProcess active) {
            try {
                yield subp.wait_async (active.cancellable);
            } catch (GLib.Error e) {
                // Controlled cancellation handling
            }
            on_process_exited (service, subp, active);
        }

        private async void read_stream_lines (string service_id, GLib.InputStream input_stream, bool is_stderr, LogRingBuffer buffer, GLib.Cancellable cancellable) {
            var dis = new GLib.DataInputStream (input_stream);
            try {
                while (true) {
                    size_t length = 0;
                    string? line = yield dis.read_line_utf8_async (GLib.Priority.DEFAULT, cancellable, out length);
                    if (line == null) {
                        break; // EOF
                    }
                    buffer.append (line, is_stderr);
                    output_received (service_id, line, is_stderr);
                }
            } catch (GLib.IOError.CANCELLED e) {
                // Intentional cancellation
            } catch (GLib.Error e) {
                // Stream closed
            }
        }

        /**
         * Gracefully terminates a service: sends SIGTERM to the process group,
         * followed by SIGKILL if it does not exit within the grace timeout.
         */
        public void stop_service (string service_id) {
            var service = service_manager.get_service (service_id);
            if (service != null && (service.service_type == ServiceType.COMPOSE || service.service_type == ServiceType.DOCKER)) {
                stop_docker_service (service);
                return;
            }

            if (!active_processes.has_key (service_id)) {
                return;
            }

            var active = active_processes.get (service_id);
            active.stopping_manually = true;

            if (service != null) {
                service.status = ServiceStatus.STOPPING;
                status_changed (service_id, service.status);
            }

            // 1. Send SIGTERM to the entire process group
            Posix.killpg (active.pgid, Posix.Signal.TERM);

            // 2. Grace period timer (3.5 seconds) to enforce SIGKILL if unresponsive
            active.kill_timeout_id = GLib.Timeout.add (3500, () => {
                if (active_processes.has_key (service_id)) {
                    GLib.message ("Service '%s' (PGID %d) did not respond to SIGTERM; sending SIGKILL...", service_id, active.pgid);
                    Posix.killpg (active.pgid, Posix.Signal.KILL);
                }
                active.kill_timeout_id = 0;
                return GLib.Source.REMOVE;
            });
        }

        public void restart_service (ServiceDefinition service, string? variant_id = null) {
            if (!is_running (service.id)) {
                start_service (service, variant_id);
                return;
            }

            schedule_service_restart_after_stop (service, variant_id);
            stop_service (service.id);
        }

        private void schedule_service_restart_after_stop (ServiceDefinition service, string? variant_id) {
            ulong handler_id = 0;
            handler_id = status_changed.connect ((s_id, status) => {
                if (s_id != service.id || (status != ServiceStatus.STOPPED && status != ServiceStatus.FAILED)) {
                    return;
                }
                this.disconnect (handler_id);
                GLib.Timeout.add (300, () => {
                    start_service (service, variant_id);
                    return GLib.Source.REMOVE;
                });
            });
        }

        public void stop_all () {
            var keys = new Gee.ArrayList<string> ();
            foreach (var k in active_processes.keys) {
                keys.add (k);
            }
            foreach (var k in keys) {
                stop_service (k);
            }
        }

        /**
         * Returns the aggregate status of all services in a stack.
         */
        public StackStatus get_stack_status (string stack_name) {
            var stack_services = service_manager.get_services_by_stack (stack_name);
            if (stack_services.size == 0) {
                return StackStatus.STOPPED;
            }

            int running_count = 0;
            int starting_count = 0;
            int stopping_count = 0;
            int failed_count = 0;
            int stopped_count = 0;

            foreach (var s in stack_services) {
                switch (s.status) {
                    case ServiceStatus.RUNNING:
                        running_count++;
                        break;
                    case ServiceStatus.STARTING:
                        starting_count++;
                        break;
                    case ServiceStatus.STOPPING:
                        stopping_count++;
                        break;
                    case ServiceStatus.FAILED:
                        failed_count++;
                        break;
                    case ServiceStatus.STOPPED:
                    default:
                        stopped_count++;
                        break;
                }
            }

            if (failed_count > 0) {
                return StackStatus.FAILED;
            }
            if (running_count == stack_services.size) {
                return StackStatus.RUNNING;
            }
            if (stopped_count == stack_services.size) {
                return StackStatus.STOPPED;
            }
            if (starting_count == stack_services.size) {
                return StackStatus.STARTING;
            }
            if (stopping_count == stack_services.size) {
                return StackStatus.STOPPING;
            }
            return StackStatus.PARTIALLY_RUNNING;
        }

        /**
         * Starts all services in the specified stack.
         */
        public void start_stack (string stack_name) {
            var stack_services = service_manager.get_services_by_stack (stack_name);
            foreach (var s in stack_services) {
                if (s.status != ServiceStatus.RUNNING && s.status != ServiceStatus.STARTING) {
                    start_service (s, null);
                }
            }
        }

        /**
         * Stops all services in the specified stack.
         */
        public void stop_stack (string stack_name) {
            var stack_services = service_manager.get_services_by_stack (stack_name);
            foreach (var s in stack_services) {
                if (s.status == ServiceStatus.RUNNING || s.status == ServiceStatus.STARTING) {
                    stop_service (s.id);
                }
            }
        }

        /**
         * Restarts all services in the specified stack.
         */
        public void restart_stack (string stack_name) {
            var stack_services = service_manager.get_services_by_stack (stack_name);
            foreach (var s in stack_services) {
                restart_service (s, s.active_variant_id);
            }
        }

        private void on_process_exited (ServiceDefinition service, GLib.Subprocess subp, ActiveProcess active) {
            // Cancel kill timeout if still pending
            if (active.kill_timeout_id != 0) {
                GLib.Source.remove (active.kill_timeout_id);
                active.kill_timeout_id = 0;
            }

            active.cancellable.cancel ();
            active_processes.unset (service.id);

            bool exited = subp.get_if_exited ();
            int exit_code = exited ? subp.get_exit_status () : -1;
            bool signaled = subp.get_if_signaled ();
            int term_sig = signaled ? subp.get_term_sig () : 0;

            log_process_termination (service, exit_code, signaled, term_sig);
            handle_exit_status (service, active, exited, exit_code, term_sig);

            service.active_variant_id = null;
            service.metrics.reset ();
            status_changed (service.id, service.status);
        }

        private void log_process_termination (ServiceDefinition service, int exit_code, bool signaled, int term_sig) {
            var buffer = get_log_buffer (service.id);
            string footer = "--- [Exited: %s | Exit code: %d%s] ---".printf (
                service.name,
                exit_code,
                signaled ? " (Signal: %d)".printf (term_sig) : ""
            );
            buffer.append (footer, false);
            output_received (service.id, footer, false);
        }

        private void handle_exit_status (ServiceDefinition service, ActiveProcess active, bool exited, int exit_code, int term_sig) {
            if (active.stopping_manually) {
                service.status = ServiceStatus.STOPPED;
                return;
            }

            bool is_error = (!exited || exit_code != 0);
            if (!is_error) {
                service.status = ServiceStatus.STOPPED;
                return;
            }

            service.status = ServiceStatus.FAILED;
            notify_crash (service, tr ("Process exited with code %d").printf (exit_code));
            service_crashed (service, exit_code, term_sig);

            if (service.auto_restart) {
                schedule_crash_auto_restart (service);
            }
        }

        private void schedule_crash_auto_restart (ServiceDefinition service) {
            GLib.Timeout.add_seconds (2, () => {
                if (!is_running (service.id)) {
                    start_service (service, service.active_variant_id);
                }
                return GLib.Source.REMOVE;
            });
        }

        private void notify_crash (ServiceDefinition service, string reason) {
            if (!service_manager.settings.enable_notifications) return;

            var app = GLib.Application.get_default ();
            if (app != null) {
                var notif = new GLib.Notification ("Daemonette");
                notif.set_title (tr ("Service Crashed: %s").printf (service.name));
                notif.set_body (reason);
                notif.set_icon (new GLib.ThemedIcon ("dialog-warning"));
                app.send_notification ("crash_" + service.id, notif);
            }
        }

        /* -------------------------------------------------------------
         * Docker & Docker Compose Lifecycle Support
         * ------------------------------------------------------------- */

        private bool start_docker_service (ServiceDefinition service, string? variant_id = null) {
            if (is_running (service.id)) {
                GLib.warning ("Service '%s' is already running.", service.name);
                return false;
            }

            if (!DockerRunner.is_docker_available ()) {
                string err_msg = tr ("Docker is not available on this system.");
                GLib.warning ("%s", err_msg);
                var buffer = get_log_buffer (service.id);
                buffer.append ("--- [Error: %s] ---".printf (err_msg), true);
                output_received (service.id, err_msg, true);
                service.status = ServiceStatus.FAILED;
                status_changed (service.id, service.status);
                return false;
            }

            service.status = ServiceStatus.STARTING;
            status_changed (service.id, service.status);

            string[]? start_argv = null;
            if (service.service_type == ServiceType.COMPOSE) {
                start_argv = DockerRunner.build_compose_argv (service, "up", { "-d" });
            } else {
                start_argv = DockerRunner.build_docker_start_argv (service);
            }

            if (start_argv == null) {
                service.status = ServiceStatus.FAILED;
                status_changed (service.id, service.status);
                return false;
            }

            var buffer = get_log_buffer (service.id);
            string start_header = "--- [Starting: %s (%s)] ---".printf (service.name, service.service_type.to_display_string ());
            buffer.append (start_header, false);
            output_received (service.id, start_header, false);

            execute_docker_start.begin (service, start_argv, variant_id);
            return true;
        }

        private async void execute_docker_start (ServiceDefinition service, string[] start_argv, string? variant_id) {
            var buffer = get_log_buffer (service.id);
            int exit_code = -1;
            string stdout_str = "";
            string stderr_str = "";

            try {
                var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                if (service.working_directory != null && service.working_directory.strip () != "") {
                    launcher.set_cwd (service.working_directory);
                }

                var subp = launcher.spawnv (start_argv);
                yield subp.communicate_utf8_async (null, null, out stdout_str, out stderr_str);

                if (stdout_str != null && stdout_str.strip () != "") {
                    foreach (var line in stdout_str.strip ().split ("\n")) {
                        buffer.append (line, false);
                        output_received (service.id, line, false);
                    }
                }
                if (stderr_str != null && stderr_str.strip () != "") {
                    foreach (var line in stderr_str.strip ().split ("\n")) {
                        buffer.append (line, true);
                        output_received (service.id, line, true);
                    }
                }

                exit_code = subp.get_exit_status ();
            } catch (GLib.Error e) {
                string err_text = "Error starting docker: %s".printf (e.message);
                buffer.append (err_text, true);
                output_received (service.id, err_text, true);
                exit_code = -1;
            }

            if (exit_code != 0) {
                service.status = ServiceStatus.FAILED;
                status_changed (service.id, service.status);
                if (service.service_type == ServiceType.COMPOSE) {
                    DockerRunner.update_compose_metrics_async.begin (service);
                }
                return;
            }

            service.status = ServiceStatus.RUNNING;
            service.active_variant_id = variant_id;
            service.metrics.reset ();
            service.metrics.started_at = new GLib.DateTime.now_local ();
            status_changed (service.id, service.status);

            string ready_msg = "--- [Started: %s] ---".printf (service.name);
            buffer.append (ready_msg, false);
            output_received (service.id, ready_msg, false);

            if (service.service_type == ServiceType.COMPOSE) {
                DockerRunner.update_compose_metrics_async.begin (service);
            }

            spawn_docker_log_follower (service);
        }

        private void spawn_docker_log_follower (ServiceDefinition service) {
            string[]? log_argv = null;
            if (service.service_type == ServiceType.COMPOSE) {
                log_argv = DockerRunner.build_compose_argv (service, "logs", { "-f", "--tail", "50" });
            } else {
                log_argv = DockerRunner.build_docker_argv (service, "logs", { "-f", "--tail", "50" });
            }

            if (log_argv == null) {
                return;
            }

            var buffer = get_log_buffer (service.id);
            try {
                var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                if (service.working_directory != null && service.working_directory.strip () != "") {
                    launcher.set_cwd (service.working_directory);
                }
                launcher.set_child_setup (() => {
                    Posix.setpgid (0, 0);
                });

                var subp = launcher.spawnv (log_argv);
                int pid = int.parse (subp.get_identifier ());
                int pgid = pid;

                var active = new ActiveProcess (service.id, subp, pid, pgid);
                active_processes.set (service.id, active);

                attach_stream_readers (service.id, subp, buffer, active.cancellable);
                wait_for_docker_log_exit.begin (service, subp, active);
            } catch (GLib.Error e) {
                GLib.warning ("Failed to attach log stream for '%s': %s", service.name, e.message);
            }
        }

        private async void wait_for_docker_log_exit (ServiceDefinition service, GLib.Subprocess subp, ActiveProcess active) {
            try {
                yield subp.wait_async (active.cancellable);
            } catch (GLib.Error e) {
                // Cancelled intentionally
            }

            if (active_processes.has_key (service.id) && active_processes.get (service.id) == active) {
                active_processes.unset (service.id);
            }

            if (!active.stopping_manually) {
                ServiceStatus cur_status = DockerRunner.query_service_status (service);
                service.status = cur_status;
                service.metrics.reset ();
                status_changed (service.id, service.status);

                if (cur_status == ServiceStatus.FAILED) {
                    notify_crash (service, tr ("Container stopped or failed"));
                    service_crashed (service, -1, 0);
                    if (service.auto_restart) {
                        schedule_crash_auto_restart (service);
                    }
                }
            }
        }

        private void stop_docker_service (ServiceDefinition service) {
            service.status = ServiceStatus.STOPPING;
            status_changed (service.id, service.status);

            if (active_processes.has_key (service.id)) {
                var active = active_processes.get (service.id);
                active.stopping_manually = true;
                active.cancellable.cancel ();
                if (active.pgid > 0) {
                    Posix.killpg (active.pgid, Posix.Signal.TERM);
                }
                active_processes.unset (service.id);
            }

            string[]? stop_argv = null;
            if (service.service_type == ServiceType.COMPOSE) {
                stop_argv = DockerRunner.build_compose_argv (service, "stop");
            } else {
                stop_argv = DockerRunner.build_docker_argv (service, "stop", { "-t", "5" });
            }

            if (stop_argv != null) {
                execute_docker_stop.begin (service, stop_argv);
            } else {
                service.status = ServiceStatus.STOPPED;
                service.metrics.reset ();
                status_changed (service.id, service.status);
            }
        }

        private async void execute_docker_stop (ServiceDefinition service, string[] stop_argv) {
            var buffer = get_log_buffer (service.id);
            try {
                var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                if (service.working_directory != null && service.working_directory.strip () != "") {
                    launcher.set_cwd (service.working_directory);
                }
                var subp = launcher.spawnv (stop_argv);
                yield subp.wait_async (null);
            } catch (GLib.Error e) {
                GLib.warning ("Error stopping docker service %s: %s", service.name, e.message);
            }

            service.status = ServiceStatus.STOPPED;
            service.metrics.reset ();
            status_changed (service.id, service.status);

            if (service.service_type == ServiceType.COMPOSE) {
                DockerRunner.update_compose_metrics_async.begin (service);
            }

            string stop_msg = "--- [Stopped: %s] ---".printf (service.name);
            buffer.append (stop_msg, false);
            output_received (service.id, stop_msg, false);
        }

        /**
         * Refreshes the status of all Docker and Compose services from the Docker daemon.
         */
        public void sync_docker_services_status () {
            if (!DockerRunner.is_docker_available ()) {
                return;
            }

            foreach (var service in service_manager.services) {
                if (service.service_type != ServiceType.COMPOSE && service.service_type != ServiceType.DOCKER) {
                    continue;
                }
                if (service.status == ServiceStatus.STARTING || service.status == ServiceStatus.STOPPING) {
                    continue;
                }

                sync_single_docker_service_status (service);
            }
        }

        private void sync_single_docker_service_status (ServiceDefinition service) {
            ServiceStatus current = DockerRunner.query_service_status (service);
            if (current != service.status) {
                service.status = current;
                if (current == ServiceStatus.RUNNING && !active_processes.has_key (service.id)) {
                    spawn_docker_log_follower (service);
                }
                status_changed (service.id, service.status);
            }

            if (service.service_type == ServiceType.COMPOSE && service.docker_containers.size == 0) {
                DockerRunner.update_compose_metrics_async.begin (service);
            }
        }
    }
}
