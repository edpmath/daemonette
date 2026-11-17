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
            if (probed_docker) {
                return cached_docker_bin;
            }

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
            return cached_docker_bin;
        }

        /**
         * Resolves the effective compose file path.
         * If service.compose_file is relative or empty, looks in service.working_directory.
         */
        public static string resolve_compose_file (ServiceDefinition service) {
            string raw = (service.compose_file != null) ? service.compose_file.strip () : "";
            if (raw != "") {
                return resolve_specified_compose_path (service, raw);
            }
            return resolve_default_compose_path (service);
        }

        private static string resolve_specified_compose_path (ServiceDefinition service, string path) {
            if (GLib.Path.is_absolute (path)) {
                return path;
            }
            string cwd = (service.working_directory != null) ? service.working_directory.strip () : "";
            if (cwd != "") {
                return GLib.Path.build_filename (cwd, path);
            }
            return path;
        }

        private static string resolve_default_compose_path (ServiceDefinition service) {
            string cwd = (service.working_directory != null) ? service.working_directory.strip () : "";
            if (cwd == "") {
                return "docker-compose.yml";
            }
            string[] candidates = {
                "docker-compose.yml",
                "docker-compose.yaml",
                "compose.yml",
                "compose.yaml"
            };
            foreach (var c in candidates) {
                string full_path = GLib.Path.build_filename (cwd, c);
                if (GLib.FileUtils.test (full_path, GLib.FileTest.EXISTS)) {
                    return full_path;
                }
            }
            return GLib.Path.build_filename (cwd, "docker-compose.yml");
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
                        if (root_node == null || root_node.get_node_type () != Json.NodeType.OBJECT) {
                            continue;
                        }

                        var obj = root_node.get_object ();
                        total_containers++;
                        string state = obj.has_member ("State") ? obj.get_string_member ("State").down () : "";
                        int exit_code = obj.has_member ("ExitCode") ? (int) obj.get_int_member ("ExitCode") : 0;

                        if (state == "running") {
                            running_containers++;
                        } else if (exit_code != 0) {
                            failed_containers++;
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
                    return ServiceStatus.RUNNING;
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
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return ServiceStatus.STOPPED;
                }

                var obj = root.get_object ();
                bool is_running = obj.has_member ("Running") ? obj.get_boolean_member ("Running") : false;
                if (is_running) {
                    return ServiceStatus.RUNNING;
                }
                bool is_restarting = obj.has_member ("Restarting") ? obj.get_boolean_member ("Restarting") : false;
                if (is_restarting) {
                    return ServiceStatus.STARTING;
                }
                int exit_code = obj.has_member ("ExitCode") ? (int) obj.get_int_member ("ExitCode") : 0;
                if (exit_code != 0) {
                    return ServiceStatus.FAILED;
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
                if (root == null || root.get_node_type () != Json.NodeType.OBJECT) {
                    return false;
                }

                var obj = root.get_object ();
                if (obj.has_member ("CPUPerc")) {
                    cpu_pct = parse_cpu_percentage (obj.get_string_member ("CPUPerc"));
                }
                if (obj.has_member ("MemUsage")) {
                    mem_bytes = parse_mem_usage_string (obj.get_string_member ("MemUsage"));
                }
                return true;
            } catch (GLib.Error e) {
                // Ignore query failures
            }

            return false;
        }

        public static uint64 parse_byte_size (string size_str) {
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

        public static double parse_cpu_percentage (string cpu_str) {
            string s = cpu_str.replace ("%", "").strip ();
            if (s == "") return 0.0;
            double val = double.parse (s);
            return val >= 0.0 ? val : 0.0;
        }

        public static uint64 parse_mem_usage_string (string mem_usage) {
            string[] parts = mem_usage.split ("/");
            if (parts.length > 0) {
                return parse_byte_size (parts[0].strip ());
            }
            return 0;
        }

        /**
         * Parses docker compose ps JSON output into DockerContainerInfo objects.
         * Handles both line-delimited JSON objects and JSON arrays.
         */
        public static Gee.ArrayList<DockerContainerInfo> parse_compose_ps_json (string json_output) {
            var list = new Gee.ArrayList<DockerContainerInfo> ();
            if (json_output.strip () == "") return list;

            string[] lines = json_output.strip ().split ("\n");
            var parser = new Json.Parser ();

            foreach (var line in lines) {
                string trimmed = line.strip ();
                if (trimmed == "") continue;

                try {
                    parser.load_from_data (trimmed);
                    var root = parser.get_root ();
                    if (root == null) continue;

                    parse_containers_from_root (list, root);
                } catch (GLib.Error e) {
                    // Ignore line errors
                }
            }
            return list;
        }

        private static void parse_containers_from_root (Gee.ArrayList<DockerContainerInfo> list, Json.Node root) {
            if (root.get_node_type () == Json.NodeType.OBJECT) {
                parse_and_add_container (list, root);
                return;
            }
            if (root.get_node_type () == Json.NodeType.ARRAY) {
                var arr = root.get_array ();
                for (uint i = 0; i < arr.get_length (); i++) {
                    parse_and_add_container (list, arr.get_element (i));
                }
            }
        }

        private static void parse_and_add_container (Gee.ArrayList<DockerContainerInfo> list, Json.Node node) {
            if (node.get_node_type () != Json.NodeType.OBJECT) {
                return;
            }
            var info = parse_container_json_object (node.get_object ());
            if (info != null) {
                list.add (info);
            }
        }

        public static int extract_exit_code_from_status (string status) {
            int open_paren = status.index_of ("(");
            if (open_paren < 0) {
                return 0;
            }
            int close_paren = status.index_of (")", open_paren);
            if (close_paren < 0) {
                return 0;
            }
            string num_str = status.substring (open_paren + 1, close_paren - open_paren - 1).strip ();
            return int.parse (num_str);
        }

        private static DockerContainerInfo? parse_container_json_object (Json.Object obj) {
            string id = obj.has_member ("ID") ? obj.get_string_member ("ID") : "";
            string name = obj.has_member ("Name") ? obj.get_string_member ("Name") : "";
            string service = obj.has_member ("Service") ? obj.get_string_member ("Service") : "";
            string image = obj.has_member ("Image") ? obj.get_string_member ("Image") : "";
            string state = obj.has_member ("State") ? obj.get_string_member ("State").down () : "";
            string status = obj.has_member ("Status") ? obj.get_string_member ("Status") : "";
            string health = obj.has_member ("Health") ? obj.get_string_member ("Health").down () : "";
            string ports = obj.has_member ("Ports") ? obj.get_string_member ("Ports") : "";
            int exit_code = obj.has_member ("ExitCode") ? (int) obj.get_int_member ("ExitCode") : 0;

            if (exit_code == 0 && status.contains ("Exited (")) {
                exit_code = extract_exit_code_from_status (status);
            }

            if (name == "" && service != "") {
                name = service;
            }
            if (service == "" && name != "") {
                service = name;
            }

            if (id == "" && name == "") return null;

            return new DockerContainerInfo (id, name, service, image, state, status, health, ports, exit_code);
        }

        /**
         * Applies parsed docker stats JSON output to an array of DockerContainerInfo.
         */
        public static void apply_stats_json_to_containers (string stats_json, Gee.ArrayList<DockerContainerInfo> containers) {
            if (stats_json.strip () == "" || containers.size == 0) return;

            string[] lines = stats_json.strip ().split ("\n");
            var parser = new Json.Parser ();

            foreach (var line in lines) {
                string trimmed = line.strip ();
                if (trimmed == "") continue;

                try {
                    parser.load_from_data (trimmed);
                    var root = parser.get_root ();
                    if (root == null || root.get_node_type () != Json.NodeType.OBJECT) continue;

                    apply_stat_object_to_containers (root.get_object (), containers);
                } catch (GLib.Error e) {
                    // Ignore malformed line
                }
            }
        }

        private static void apply_stat_object_to_containers (Json.Object obj, Gee.ArrayList<DockerContainerInfo> containers) {
            string stat_id = obj.has_member ("ID") ? obj.get_string_member ("ID").strip () : "";
            string stat_name = obj.has_member ("Name") ? obj.get_string_member ("Name").strip () : "";
            string stat_container = obj.has_member ("Container") ? obj.get_string_member ("Container").strip () : "";
            string cpu_str = obj.has_member ("CPUPerc") ? obj.get_string_member ("CPUPerc") : "0%";
            string mem_str = obj.has_member ("MemUsage") ? obj.get_string_member ("MemUsage") : "0B";

            double cpu = parse_cpu_percentage (cpu_str);
            uint64 mem = parse_mem_usage_string (mem_str);

            foreach (var c in containers) {
                if (!container_matches_stats (c, stat_id, stat_name, stat_container)) {
                    continue;
                }
                c.cpu_percent = cpu;
                c.memory_bytes = mem;
                break;
            }
        }

        private static bool container_matches_stats (DockerContainerInfo c, string stat_id, string stat_name, string stat_container) {
            if (stat_id != "" && (c.id == stat_id || c.id.has_prefix (stat_id) || stat_id.has_prefix (c.id))) {
                return true;
            }
            if (stat_name != "" && (c.name == stat_name || c.service_name == stat_name)) {
                return true;
            }
            if (stat_container != "" && (c.id == stat_container || stat_container.has_prefix (c.id))) {
                return true;
            }
            return false;
        }

        /**
         * Asynchronously queries all containers belonging to a Compose service.
         * Merges existing active/stopped containers with declared compose services.
         */
        public static async Gee.ArrayList<DockerContainerInfo> query_compose_containers_async (ServiceDefinition service) {
            var list = new Gee.ArrayList<DockerContainerInfo> ();
            if (!is_docker_available ()) {
                return list;
            }

            string[] argv = build_compose_argv (service, "ps", { "--all", "--format", "json" });
            try {
                var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                if (service.working_directory != null && service.working_directory.strip () != "") {
                    launcher.set_cwd (service.working_directory);
                }
                var subp = launcher.spawnv (argv);
                string stdout_buf;
                yield subp.communicate_utf8_async (null, null, out stdout_buf, null);

                if (stdout_buf != null) {
                    list = parse_compose_ps_json (stdout_buf);
                }
            } catch (GLib.Error e) {
                GLib.warning ("Error querying compose containers for '%s': %s", service.name, e.message);
            }

            yield merge_declared_compose_services_async (service, list);
            return list;
        }

        private static async void merge_declared_compose_services_async (ServiceDefinition service, Gee.ArrayList<DockerContainerInfo> list) {
            string compose_file = resolve_compose_file (service);
            if (compose_file == "") {
                return;
            }

            var declared_services = yield get_compose_services_for_definition_async (service, compose_file);
            foreach (var declared in declared_services) {
                if (has_container_for_service (list, declared)) {
                    continue;
                }
                var uncreated = new DockerContainerInfo ("", declared, declared, "", "stopped", "Stopped", "", "", 0);
                list.add (uncreated);
            }
        }

        private static bool has_container_for_service (Gee.ArrayList<DockerContainerInfo> list, string declared) {
            foreach (var c in list) {
                if (c.service_name == declared || c.name == declared) {
                    return true;
                }
            }
            return false;
        }

        private static async Gee.ArrayList<string> get_compose_services_for_definition_async (ServiceDefinition service, string compose_file) {
            var services = new Gee.ArrayList<string> ();
            string docker = get_docker_binary () ?? "docker";
            string[] argv = { docker, "compose", "-f", compose_file, "config", "--services" };

            try {
                var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                if (service.working_directory != null && service.working_directory.strip () != "") {
                    launcher.set_cwd (service.working_directory);
                }
                var subp = launcher.spawnv (argv);
                string stdout_buf;
                yield subp.communicate_utf8_async (null, null, out stdout_buf, null);
                if (stdout_buf == null) {
                    return services;
                }
                string[] lines = stdout_buf.strip ().split ("\n");
                foreach (var line in lines) {
                    string trimmed = line.strip ();
                    if (trimmed != "") {
                        services.add (trimmed);
                    }
                }
            } catch (GLib.Error e) {
                // Ignore config parse errors if file is invalid or missing
            }
            return services;
        }

        /**
         * Asynchronously updates the metrics and container list for a Compose stack.
         */
        public static async void update_compose_metrics_async (ServiceDefinition service) {
            var containers = yield query_compose_containers_async (service);
            if (containers.size == 0) {
                service.docker_containers = containers;
                service.metrics.memory_rss_bytes = 0;
                service.metrics.cpu_percent = 0.0;
                return;
            }

            var running_ids = get_running_container_ids (containers);
            if (running_ids.size > 0) {
                yield fetch_and_apply_container_stats_async (running_ids, containers, service.name);
            }

            uint64 total_mem = 0;
            double total_cpu = 0.0;
            foreach (var c in containers) {
                total_mem += c.memory_bytes;
                total_cpu += c.cpu_percent;
            }

            service.docker_containers = containers;
            service.metrics.memory_rss_bytes = total_mem;
            service.metrics.cpu_percent = total_cpu;
        }

        private static Gee.ArrayList<string> get_running_container_ids (Gee.ArrayList<DockerContainerInfo> containers) {
            var running_ids = new Gee.ArrayList<string> ();
            foreach (var c in containers) {
                if (c.state == "running" && c.id != "") {
                    running_ids.add (c.id);
                }
            }
            return running_ids;
        }

        private static async void fetch_and_apply_container_stats_async (Gee.ArrayList<string> running_ids, Gee.ArrayList<DockerContainerInfo> containers, string service_name) {
            string docker = get_docker_binary () ?? "docker";
            var args = new Gee.ArrayList<string> ();
            args.add (docker);
            args.add ("stats");
            args.add ("--no-stream");
            args.add ("--format");
            args.add ("{{json .}}");
            foreach (var id in running_ids) {
                args.add (id);
            }

            string[] argv = new string[args.size];
            for (int i = 0; i < args.size; i++) {
                argv[i] = args[i];
            }

            try {
                var subp = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string stdout_buf;
                yield subp.communicate_utf8_async (null, null, out stdout_buf, null);

                if (stdout_buf != null) {
                    apply_stats_json_to_containers (stdout_buf, containers);
                }
            } catch (GLib.Error e) {
                GLib.warning ("Error querying container stats for '%s': %s", service_name, e.message);
            }
        }

        /**
         * Asynchronously updates metrics for a standalone Docker container.
         */
        public static async void update_docker_metrics_async (ServiceDefinition service) {
            string target = service.container_name.strip ();
            if (target == "" || !is_docker_available ()) {
                service.metrics.memory_rss_bytes = 0;
                service.metrics.cpu_percent = 0.0;
                return;
            }

            string docker = get_docker_binary () ?? "docker";
            string[] argv = { docker, "stats", "--no-stream", "--format", "{{json .}}", target };

            try {
                var subp = new GLib.Subprocess.newv (argv, GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_SILENCE);
                string stdout_buf;
                yield subp.communicate_utf8_async (null, null, out stdout_buf, null);

                if (stdout_buf == null || stdout_buf.strip () == "") {
                    return;
                }

                var containers = new Gee.ArrayList<DockerContainerInfo> ();
                var c = new DockerContainerInfo ("", target, target, "", "running", "running");
                containers.add (c);
                apply_stats_json_to_containers (stdout_buf, containers);

                service.docker_containers = containers;
                service.metrics.memory_rss_bytes = c.memory_bytes;
                service.metrics.cpu_percent = c.cpu_percent;
            } catch (GLib.Error e) {
                // Failed query
            }
        }

        /**
         * Asynchronously starts a specific sub-service inside a Docker Compose project.
         */
        public static async bool start_compose_subservice_async (ServiceDefinition service, string subservice_name) {
            if (!is_docker_available () || subservice_name.strip () == "") {
                return false;
            }

            string[] argv = build_compose_argv (service, "up", { "-d", subservice_name.strip () });
            return yield run_compose_subservice_command_async (service, argv, subservice_name, "start");
        }

        /**
         * Asynchronously stops a specific sub-service inside a Docker Compose project.
         */
        public static async bool stop_compose_subservice_async (ServiceDefinition service, string subservice_name) {
            if (!is_docker_available () || subservice_name.strip () == "") {
                return false;
            }

            string[] argv = build_compose_argv (service, "stop", { subservice_name.strip () });
            return yield run_compose_subservice_command_async (service, argv, subservice_name, "stop");
        }

        /**
         * Asynchronously restarts a specific sub-service inside a Docker Compose project.
         */
        public static async bool restart_compose_subservice_async (ServiceDefinition service, string subservice_name) {
            if (!is_docker_available () || subservice_name.strip () == "") {
                return false;
            }

            string[] argv = build_compose_argv (service, "restart", { subservice_name.strip () });
            return yield run_compose_subservice_command_async (service, argv, subservice_name, "restart");
        }

        private static async bool run_compose_subservice_command_async (ServiceDefinition service, string[] argv, string subservice_name, string op_name) {
            try {
                var launcher = new GLib.SubprocessLauncher (GLib.SubprocessFlags.STDOUT_PIPE | GLib.SubprocessFlags.STDERR_PIPE);
                if (service.working_directory != null && service.working_directory.strip () != "") {
                    launcher.set_cwd (service.working_directory);
                }
                var subp = launcher.spawnv (argv);
                string stdout_buf, stderr_buf;
                yield subp.communicate_utf8_async (null, null, out stdout_buf, out stderr_buf);
                return (subp.get_exit_status () == 0);
            } catch (GLib.Error e) {
                GLib.warning ("Failed to %s compose subservice '%s': %s", op_name, subservice_name, e.message);
                return false;
            }
        }
    }
}
