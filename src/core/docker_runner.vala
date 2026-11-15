/* src/core/docker_runner.vala
 * Docker and Docker Compose execution engine.
 * Seamlessly supports Docker Desktop and native Docker Engine via the Docker CLI.
 */

namespace Daemonette {

    public class DockerRunner : Object {
        private static string? cached_docker_bin = null;
        private static bool probed_docker = false;

        public static bool is_docker_available () {
            return get_docker_binary () != null;
        }

        public static string? get_docker_binary () {
            if (!probed_docker) {
                probed_docker = true;
                string? in_path = GLib.Environment.find_program_in_path ("docker");
                if (in_path != null && in_path != "" && GLib.FileUtils.test (in_path, GLib.FileTest.IS_EXECUTABLE)) {
                    cached_docker_bin = in_path;
                    return cached_docker_bin;
                }

                string[] candidates = {
                    "/usr/bin/docker",
                    "/usr/local/bin/docker",
                    "/bin/docker"
                };
                foreach (var c in candidates) {
                    if (GLib.FileUtils.test (c, GLib.FileTest.IS_EXECUTABLE)) {
                        cached_docker_bin = c;
                        break;
                    }
                }
            }
            return cached_docker_bin;
        }

        /**
         * Resolves the effective compose file path.
         * If service.compose_file is relative or empty, looks in service.working_directory.
         */
        public static string resolve_compose_file (ServiceDefinition service) {
            if (service.compose_file != null && service.compose_file.strip () != "") {
                string path = service.compose_file.strip ();
                if (GLib.Path.is_absolute (path)) {
                    return path;
                }
                if (service.working_directory != null && service.working_directory.strip () != "") {
                    return GLib.Path.build_filename (service.working_directory.strip (), path);
                }
                return path;
            }

            // If empty, search standard compose filenames in working_directory
            if (service.working_directory != null && service.working_directory.strip () != "") {
                string[] candidates = {
                    "docker-compose.yml",
                    "docker-compose.yaml",
                    "compose.yml",
                    "compose.yaml"
                };
                foreach (var c in candidates) {
                    string full_path = GLib.Path.build_filename (service.working_directory.strip (), c);
                    if (GLib.FileUtils.test (full_path, GLib.FileTest.EXISTS)) {
                        return full_path;
                    }
                }
                return GLib.Path.build_filename (service.working_directory.strip (), "docker-compose.yml");
            }

            return "docker-compose.yml";
        }

        /**
         * Builds argv for a docker compose command.
         */
        public static string[] build_compose_argv (ServiceDefinition service, string subcommand, string[]? extra_args = null) {
            var args = new Gee.ArrayList<string> ();
            string docker = get_docker_binary () ?? "docker";
            args.add (docker);
            args.add ("compose");

            string compose_file = resolve_compose_file (service);
            if (compose_file != "") {
                args.add ("-f");
                args.add (compose_file);
            }

            // Subcommand (e.g. "up", "stop", "restart", "ps", "logs")
            args.add (subcommand);

            if (extra_args != null) {
                foreach (var arg in extra_args) {
                    args.add (arg);
                }
            }

            // Target specific compose service if configured
            if (service.compose_service != null && service.compose_service.strip () != "") {
                args.add (service.compose_service.strip ());
            }

            string[] result = new string[args.size];
            for (int i = 0; i < args.size; i++) {
                result[i] = args[i];
            }
            return result;
        }

        /**
         * Builds argv for a standalone docker container command.
         */
        public static string[]? build_docker_argv (ServiceDefinition service, string subcommand, string[]? extra_args = null) {
            string target = service.container_name.strip ();
            if (target == "") {
                return null;
            }

            var args = new Gee.ArrayList<string> ();
            string docker = get_docker_binary () ?? "docker";
            args.add (docker);
            args.add (subcommand);

            if (extra_args != null) {
                foreach (var arg in extra_args) {
                    args.add (arg);
                }
            }

            args.add (target);

            string[] result = new string[args.size];
            for (int i = 0; i < args.size; i++) {
                result[i] = args[i];
            }
            return result;
        }

        /**
         * Builds argv to start a standalone docker container.
         * If command is defined and starts with "docker run", use that;
         * otherwise use "docker start <container_name>".
         */
        public static string[]? build_docker_start_argv (ServiceDefinition service) {
            if (service.command != null && service.command.strip ().has_prefix ("docker run")) {
                try {
                    string[] argv;
                    GLib.Shell.parse_argv (service.command.strip (), out argv);
                    return argv;
                } catch (GLib.ShellError e) {
                    // Fall back to standard docker start
                }
            }

            return build_docker_argv (service, "start");
        }

        /**
         * Lists service names declared in a docker-compose file.
         */
        public static Gee.ArrayList<string> get_compose_services (string compose_file) {
            var services = new Gee.ArrayList<string> ();
            string docker = get_docker_binary () ?? "docker";
            string[] argv = { docker, "compose", "-f", compose_file, "config", "--services" };

            try {
                var subp = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string stdout_buf;
                subp.communicate_utf8 (null, null, out stdout_buf, null);
                if (stdout_buf != null) {
                    string[] lines = stdout_buf.strip ().split ("\n");
                    foreach (var line in lines) {
                        string trimmed = line.strip ();
                        if (trimmed != "") {
                            services.add (trimmed);
                        }
                    }
                }
            } catch (GLib.Error e) {
                GLib.warning ("Failed to query compose services for %s: %s", compose_file, e.message);
            }

            return services;
        }

        /**
         * Queries the real-time status of a Docker / Compose service from the Docker daemon.
         */
        public static ServiceStatus query_service_status (ServiceDefinition service) {
            if (!is_docker_available ()) {
                return ServiceStatus.STOPPED;
            }

            if (service.service_type == ServiceType.COMPOSE) {
                return query_compose_status (service);
            } else if (service.service_type == ServiceType.DOCKER) {
                return query_docker_status (service);
            }

            return ServiceStatus.STOPPED;
        }

        private static ServiceStatus query_compose_status (ServiceDefinition service) {
            string[] argv = build_compose_argv (service, "ps", { "--all", "--format", "json" });

            try {
                var subp = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string stdout_buf;
                subp.communicate_utf8 (null, null, out stdout_buf, null);

                if (stdout_buf == null || stdout_buf.strip () == "") {
                    return ServiceStatus.STOPPED;
                }

                string[] lines = stdout_buf.strip ().split ("\n");
                int total_containers = 0;
                int running_containers = 0;
                int failed_containers = 0;

                var parser = new Json.Parser ();
                foreach (var line in lines) {
                    string trimmed = line.strip ();
                    if (trimmed == "") continue;

                    try {
                        parser.load_from_data (trimmed);
                        var root_node = parser.get_root ();
                        if (root_node != null && root_node.get_node_type () == Json.NodeType.OBJECT) {
                            var obj = root_node.get_object ();
                            total_containers++;
                            string state = obj.has_member ("State") ? obj.get_string_member ("State").down () : "";
                            int exit_code = obj.has_member ("ExitCode") ? (int) obj.get_int_member ("ExitCode") : 0;

                            if (state == "running") {
                                running_containers++;
                            } else if (exit_code != 0) {
                                failed_containers++;
                            }
                        }
                    } catch (GLib.Error e) {
                        // Ignore malformed JSON line
                    }
                }

                if (total_containers == 0) {
                    return ServiceStatus.STOPPED;
                }
                if (running_containers == total_containers) {
                    return ServiceStatus.RUNNING;
                }
                if (running_containers > 0) {
                    return ServiceStatus.RUNNING; // At least partially running
                }
                if (failed_containers > 0) {
                    return ServiceStatus.FAILED;
                }
                return ServiceStatus.STOPPED;
            } catch (GLib.Error e) {
                return ServiceStatus.STOPPED;
            }
        }

        private static ServiceStatus query_docker_status (ServiceDefinition service) {
            string target = service.container_name.strip ();
            if (target == "") {
                return ServiceStatus.STOPPED;
            }

            string docker = get_docker_binary () ?? "docker";
            string[] argv = { docker, "inspect", target, "--format", "{{json .State}}" };

            try {
                var subp = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string stdout_buf;
                subp.communicate_utf8 (null, null, out stdout_buf, null);

                if (stdout_buf == null || stdout_buf.strip () == "") {
                    return ServiceStatus.STOPPED;
                }

                var parser = new Json.Parser ();
                parser.load_from_data (stdout_buf.strip ());
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    bool is_running = obj.has_member ("Running") ? obj.get_boolean_member ("Running") : false;
                    bool is_restarting = obj.has_member ("Restarting") ? obj.get_boolean_member ("Restarting") : false;
                    int exit_code = obj.has_member ("ExitCode") ? (int) obj.get_int_member ("ExitCode") : 0;

                    if (is_running) return ServiceStatus.RUNNING;
                    if (is_restarting) return ServiceStatus.STARTING;
                    if (exit_code != 0) return ServiceStatus.FAILED;
                }
                return ServiceStatus.STOPPED;
            } catch (GLib.Error e) {
                return ServiceStatus.STOPPED;
            }
        }

        /**
         * Asynchronously queries container memory and CPU stats via docker stats.
         */
        public static bool query_container_metrics (string container_name, out uint64 mem_bytes, out double cpu_pct) {
            mem_bytes = 0;
            cpu_pct = 0.0;

            if (container_name.strip () == "" || !is_docker_available ()) {
                return false;
            }

            string docker = get_docker_binary () ?? "docker";
            string[] argv = { docker, "stats", "--no-stream", "--format", "{{json .}}", container_name.strip () };

            try {
                var subp = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string stdout_buf;
                subp.communicate_utf8 (null, null, out stdout_buf, null);

                if (stdout_buf == null || stdout_buf.strip () == "") {
                    return false;
                }

                var parser = new Json.Parser ();
                parser.load_from_data (stdout_buf.strip ());
                var root = parser.get_root ();
                if (root != null && root.get_node_type () == Json.NodeType.OBJECT) {
                    var obj = root.get_object ();
                    if (obj.has_member ("CPUPerc")) {
                        string cpu_str = obj.get_string_member ("CPUPerc").replace ("%", "").strip ();
                        cpu_pct = double.parse (cpu_str);
                    }
                    if (obj.has_member ("MemUsage")) {
                        string mem_str = obj.get_string_member ("MemUsage");
                        // Format is e.g. "37.62MiB / 7.569GiB"
                        string[] parts = mem_str.split ("/");
                        if (parts.length > 0) {
                            mem_bytes = parse_byte_size (parts[0].strip ());
                        }
                    }
                    return true;
                }
            } catch (GLib.Error e) {
                // Ignore query failures
            }

            return false;
        }

        private static uint64 parse_byte_size (string size_str) {
            string s = size_str.strip ();
            double val = 0.0;

            if (s.has_suffix ("GiB") || s.has_suffix ("GB")) {
                val = double.parse (s.replace ("GiB", "").replace ("GB", "").strip ());
                return (uint64) (val * 1024.0 * 1024.0 * 1024.0);
            } else if (s.has_suffix ("MiB") || s.has_suffix ("MB")) {
                val = double.parse (s.replace ("MiB", "").replace ("MB", "").strip ());
                return (uint64) (val * 1024.0 * 1024.0);
            } else if (s.has_suffix ("KiB") || s.has_suffix ("kB") || s.has_suffix ("KB")) {
                val = double.parse (s.replace ("KiB", "").replace ("kB", "").replace ("KB", "").strip ());
                return (uint64) (val * 1024.0);
            } else if (s.has_suffix ("B")) {
                val = double.parse (s.replace ("B", "").strip ());
                return (uint64) val;
            }

            return 0;
        }
    }
}
