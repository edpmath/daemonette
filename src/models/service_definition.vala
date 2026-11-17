/* src/models/service_definition.vala
 * Data models for services, variants, and metrics in Daemonette.
 */

namespace Daemonette {

    public enum ServiceType {
        PROCESS,
        DOCKER,
        COMPOSE;

        public string to_string_id () {
            switch (this) {
                case DOCKER:
                    return "docker";
                case COMPOSE:
                    return "compose";
                case PROCESS:
                default:
                    return "process";
            }
        }

        public static ServiceType from_string_id (string? str) {
            if (str == null) return PROCESS;
            switch (str.down ()) {
                case "docker":
                case "container":
                    return DOCKER;
                case "compose":
                case "docker-compose":
                case "docker_compose":
                    return COMPOSE;
                case "process":
                case "native":
                default:
                    return PROCESS;
            }
        }

        public string to_display_string () {
            switch (this) {
                case DOCKER:
                    return tr ("Docker Container");
                case COMPOSE:
                    return tr ("Docker Compose");
                case PROCESS:
                default:
                    return tr ("Local Process");
            }
        }
    }

    public enum ServiceStatus {
        STOPPED,
        STARTING,
        RUNNING,
        STOPPING,
        FAILED;

        public string to_display_string () {
            switch (this) {
                case STARTING:
                    return tr ("Starting...");
                case RUNNING:
                    return tr ("Running");
                case STOPPING:
                    return tr ("Stopping...");
                case FAILED:
                    return tr ("Error / Stopped");
                case STOPPED:
                default:
                    return tr ("Stopped");
            }
        }
    }

    public enum StackStatus {
        STOPPED,
        STARTING,
        RUNNING,
        PARTIALLY_RUNNING,
        STOPPING,
        FAILED;

        public string to_display_string () {
            switch (this) {
                case STARTING:
                    return tr ("Starting...");
                case RUNNING:
                    return tr ("Running");
                case PARTIALLY_RUNNING:
                    return tr ("Partially Running");
                case STOPPING:
                    return tr ("Stopping...");
                case FAILED:
                    return tr ("Error / Stopped");
                case STOPPED:
                default:
                    return tr ("Stopped");
            }
        }
    }

    public class ProcessMetrics : Object {
        public uint64 memory_rss_bytes { get; set; default = 0; }
        public double cpu_percent { get; set; default = 0.0; }
        public int pid { get; set; default = 0; }
        public int pgid { get; set; default = 0; }
        public GLib.DateTime? started_at { get; set; default = null; }

        public void reset () {
            memory_rss_bytes = 0;
            cpu_percent = 0.0;
            pid = 0;
            pgid = 0;
            started_at = null;
        }

        public string format_memory () {
            if (memory_rss_bytes < 1024 * 1024) {
                return "%llu KB".printf (memory_rss_bytes / 1024);
            }
            if (memory_rss_bytes < 1024ULL * 1024ULL * 1024ULL) {
                return "%.1f MB".printf ((double) memory_rss_bytes / (1024.0 * 1024.0));
            }
            return "%.2f GB".printf ((double) memory_rss_bytes / (1024.0 * 1024.0 * 1024.0));
        }

        public string format_uptime () {
            if (started_at == null) {
                return "0s";
            }
            var now = new GLib.DateTime.now_local ();
            var diff = now.difference (started_at);
            int64 total_seconds = diff / GLib.TimeSpan.SECOND;
            if (total_seconds < 0) total_seconds = 0;

            int hours = (int)(total_seconds / 3600);
            int minutes = (int)((total_seconds % 3600) / 60);
            int seconds = (int)(total_seconds % 60);

            if (hours > 0) {
                return "%02dh %02dm".printf (hours, minutes);
            }
            return "%02dm %02ds".printf (minutes, seconds);
        }
    }

    public class ServiceVariant : Object {
        public string id { get; set; }
        public string name { get; set; }
        public string command { get; set; }
        public string url { get; set; default = ""; }
        public string icon { get; set; default = "⚡"; }
        public bool use_shell { get; set; default = true; }
        public Gee.HashMap<string, string> environment { get; set; }

        public ServiceVariant (string id, string name, string command, string url = "", bool use_shell = true, string icon = "⚡") {
            this.id = id;
            this.name = name;
            this.command = command;
            this.url = url;
            this.use_shell = use_shell;
            this.icon = (icon != null && icon.strip () != "") ? icon.strip () : "⚡";
            this.environment = new Gee.HashMap<string, string> ();
        }

        public ServiceVariant clone () {
            var copy = new ServiceVariant (this.id, this.name, this.command, this.url, this.use_shell, this.icon);
            foreach (var entry in this.environment.entries) {
                copy.environment.set (entry.key, entry.value);
            }
            return copy;
        }
    }

    public class DockerContainerInfo : Object {
        public string id { get; set; default = ""; }
        public string name { get; set; default = ""; }
        public string service_name { get; set; default = ""; }
        public string image { get; set; default = ""; }
        public string state { get; set; default = ""; }
        public string status_text { get; set; default = ""; }
        public string health { get; set; default = ""; }
        public string ports { get; set; default = ""; }
        public int exit_code { get; set; default = 0; }
        public uint64 memory_bytes { get; set; default = 0; }
        public double cpu_percent { get; set; default = 0.0; }

        public DockerContainerInfo (string id, string name, string service_name, string image, string state, string status_text, string health = "", string ports = "", int exit_code = 0) {
            this.id = id;
            this.name = name;
            this.service_name = service_name;
            this.image = image;
            this.state = state;
            this.status_text = status_text;
            this.health = health;
            this.ports = ports;
            this.exit_code = exit_code;
            this.memory_bytes = 0;
            this.cpu_percent = 0.0;
        }

        public bool is_running () {
            return state == "running";
        }

        public bool is_failed () {
            if (state == "dead") {
                return true;
            }
            if (health == "unhealthy") {
                return true;
            }
            if (exit_code != 0) {
                return true;
            }
            if (state == "exited" && (status_text.contains ("Exited (1") || status_text.contains ("error"))) {
                return true;
            }
            return false;
        }

        public string get_status_bullet () {
            if (is_failed ()) {
                return "🔴";
            }
            if (state == "starting" || health == "starting") {
                return "🟡";
            }
            if (is_running ()) {
                return "🟢";
            }
            if (state == "paused") {
                return "⏸";
            }
            return "⚪";
        }

        public string format_memory () {
            if (memory_bytes < 1024 * 1024) {
                return "%llu KB".printf (memory_bytes / 1024);
            }
            if (memory_bytes < 1024ULL * 1024ULL * 1024ULL) {
                return "%.1f MB".printf ((double) memory_bytes / (1024.0 * 1024.0));
            }
            return "%.2f GB".printf ((double) memory_bytes / (1024.0 * 1024.0 * 1024.0));
        }

        public DockerContainerInfo clone () {
            var c = new DockerContainerInfo (this.id, this.name, this.service_name, this.image, this.state, this.status_text, this.health, this.ports, this.exit_code);
            c.memory_bytes = this.memory_bytes;
            c.cpu_percent = this.cpu_percent;
            return c;
        }
    }

    public class ServiceDefinition : Object {
        public string id { get; set; }
        public string name { get; set; }
        public string stack { get; set; default = ""; }
        public ServiceType service_type { get; set; default = ServiceType.PROCESS; }
        public string compose_file { get; set; default = ""; }
        public string compose_service { get; set; default = ""; }
        public string container_name { get; set; default = ""; }
        public string working_directory { get; set; }
        public string command { get; set; }
        public string url { get; set; default = ""; }
        public bool use_shell { get; set; default = true; }
        public bool load_dotenv { get; set; default = true; }
        public bool auto_restart { get; set; default = false; }
        public bool autostart { get; set; default = false; }
        public Gee.HashMap<string, string> environment { get; set; }
        public Gee.ArrayList<ServiceVariant> variants { get; set; }

        // Runtime state (not serialized to JSON)
        public ServiceStatus status { get; set; default = ServiceStatus.STOPPED; }
        public string? active_variant_id { get; set; default = null; }
        public ProcessMetrics metrics { get; set; }
        public Gee.ArrayList<DockerContainerInfo> docker_containers { get; set; }

        public ServiceDefinition (string id, string name, string working_directory, string command, string url = "", string stack = "", ServiceType service_type = ServiceType.PROCESS, string compose_file = "", string compose_service = "", string container_name = "") {
            this.id = id;
            this.name = name;
            this.stack = stack;
            this.service_type = service_type;
            this.compose_file = compose_file;
            this.compose_service = compose_service;
            this.container_name = container_name;
            this.working_directory = working_directory;
            this.command = command;
            this.url = url;
            this.use_shell = true;
            this.load_dotenv = true;
            this.auto_restart = false;
            this.autostart = false;
            this.environment = new Gee.HashMap<string, string> ();
            this.variants = new Gee.ArrayList<ServiceVariant> ();
            this.metrics = new ProcessMetrics ();
            this.docker_containers = new Gee.ArrayList<DockerContainerInfo> ();
        }

        public ServiceVariant? find_variant (string variant_id) {
            foreach (var v in variants) {
                if (v.id == variant_id) {
                    return v;
                }
            }
            return null;
        }

        /**
         * Clones this service with a newly generated ID and name
         * for the "Duplicate Service" feature.
         */
        public ServiceDefinition clone_as_new (string new_name) {
            string new_id = "srv_" + GLib.Uuid.string_random ();
            var copy = new ServiceDefinition (new_id, new_name, this.working_directory, this.command, this.url, this.stack, this.service_type, this.compose_file, this.compose_service, this.container_name);
            copy.use_shell = this.use_shell;
            copy.load_dotenv = this.load_dotenv;
            copy.auto_restart = this.auto_restart;
            copy.autostart = this.autostart;

            foreach (var entry in this.environment.entries) {
                copy.environment.set (entry.key, entry.value);
            }

            foreach (var v in this.variants) {
                var v_copy = v.clone ();
                v_copy.id = "var_" + GLib.Uuid.string_random ();
                copy.variants.add (v_copy);
            }

            return copy;
        }
    }
}
