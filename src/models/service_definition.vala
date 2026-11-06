/* src/models/service_definition.vala
 * Data models for services, variants, and metrics in Daemonette.
 */

namespace Daemonette {

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
        public bool use_shell { get; set; default = true; }
        public Gee.HashMap<string, string> environment { get; set; }

        public ServiceVariant (string id, string name, string command, string url = "", bool use_shell = true) {
            this.id = id;
            this.name = name;
            this.command = command;
            this.url = url;
            this.use_shell = use_shell;
            this.environment = new Gee.HashMap<string, string> ();
        }

        public ServiceVariant clone () {
            var copy = new ServiceVariant (this.id, this.name, this.command, this.url, this.use_shell);
            foreach (var entry in this.environment.entries) {
                copy.environment.set (entry.key, entry.value);
            }
            return copy;
        }
    }

    public class ServiceDefinition : Object {
        public string id { get; set; }
        public string name { get; set; }
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

        public ServiceDefinition (string id, string name, string working_directory, string command, string url = "") {
            this.id = id;
            this.name = name;
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
            var copy = new ServiceDefinition (new_id, new_name, this.working_directory, this.command, this.url);
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
