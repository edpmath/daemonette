/* src/core/service_manager.vala
 * Manager for JSON persistence, .env file parsing, and configuration lifecycle.
 */

namespace Daemonette {

    public class ServiceManager : Object {
        private string config_dir;
        private string config_path;
        private string autostart_path;

        public AppSettings settings { get; private set; }
        public Gee.ArrayList<ServiceDefinition> services { get; private set; }

        public signal void service_added (ServiceDefinition service);
        public signal void service_updated (ServiceDefinition service);
        public signal void service_removed (string service_id);
        public signal void services_reloaded ();

        public ServiceManager (string? custom_config_dir = null) {
            this.settings = new AppSettings ();
            this.services = new Gee.ArrayList<ServiceDefinition> ();

            this.config_dir = resolve_config_dir (custom_config_dir);
            this.config_path = GLib.Path.build_filename (this.config_dir, "services.json");
            this.autostart_path = GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "autostart", "io.github.edpmath.Daemonette.desktop");

            ensure_config_dir ();
        }

        private static string resolve_config_dir (string? custom_dir) {
            if (custom_dir != null && custom_dir.strip () != "") {
                return custom_dir.strip ();
            }
            return GLib.Path.build_filename (GLib.Environment.get_user_config_dir (), "daemonette");
        }

        private void ensure_config_dir () {
            GLib.File dir = GLib.File.new_for_path (this.config_dir);
            if (dir.query_exists ()) {
                return;
            }

            try {
                dir.make_directory_with_parents ();
            } catch (GLib.Error e) {
                GLib.warning ("No se pudo crear el directorio de configuración %s: %s", this.config_dir, e.message);
            }
        }

        public ServiceDefinition? get_service (string service_id) {
            foreach (var s in services) {
                if (s.id == service_id) {
                    return s;
                }
            }
            return null;
        }

        public void add_service (ServiceDefinition service) {
            services.add (service);
            save_to_json ();
            service_added (service);
        }

        public bool update_service (ServiceDefinition updated) {
            for (int i = 0; i < services.size; i++) {
                if (services[i].id == updated.id) {
                    services[i] = updated;
                    save_to_json ();
                    service_updated (updated);
                    return true;
                }
            }
            return false;
        }

        public bool delete_service (string service_id) {
            for (int i = 0; i < services.size; i++) {
                if (services[i].id == service_id) {
                    services.remove_at (i);
                    save_to_json ();
                    service_removed (service_id);
                    return true;
                }
            }
            return false;
        }

        public ServiceDefinition? duplicate_service (string service_id) {
            var original = get_service (service_id);
            if (original == null) return null;

            string copy_name = "%s (%s)".printf (original.name, tr ("Copy"));
            var cloned = original.clone_as_new (copy_name);
            add_service (cloned);
            return cloned;
        }

        public void set_language (string lang) {
            if (settings.language != lang) {
                settings.language = lang;
                save_to_json ();
                I18n.get_instance ().set_language_mode (lang);
            }
        }

        /* -------------------------------------------------------------
         * JSON Persistence: Loading and Saving
         * ------------------------------------------------------------- */

        public bool load_from_json () {
            GLib.File file = GLib.File.new_for_path (this.config_path);
            if (!file.query_exists ()) {
                return false;
            }

            try {
                var parser = new Json.Parser ();
                parser.load_from_file (this.config_path);

                var root_node = parser.get_root ();
                if (root_node == null || root_node.get_node_type () != Json.NodeType.OBJECT) {
                    GLib.warning ("Archivo de configuración JSON no válido.");
                    return false;
                }

                var root_obj = root_node.get_object ();
                deserialize_settings (root_obj);
                I18n.get_instance ().set_language_mode (settings.language);
                deserialize_services (root_obj);

                services_reloaded ();
                return true;
            } catch (GLib.Error e) {
                GLib.warning ("Error al leer configuración JSON: %s", e.message);
                return false;
            }
        }

        private void deserialize_settings (Json.Object root_obj) {
            if (!root_obj.has_member ("settings")) {
                return;
            }

            var set_obj = root_obj.get_object_member ("settings");
            if (set_obj.has_member ("poll_interval_seconds")) {
                settings.poll_interval_seconds = (int) set_obj.get_int_member ("poll_interval_seconds");
            }
            if (set_obj.has_member ("max_log_lines")) {
                settings.max_log_lines = (int) set_obj.get_int_member ("max_log_lines");
            }
            if (set_obj.has_member ("enable_notifications")) {
                settings.enable_notifications = set_obj.get_boolean_member ("enable_notifications");
            }
            if (set_obj.has_member ("autostart_on_login")) {
                settings.autostart_on_login = set_obj.get_boolean_member ("autostart_on_login");
            }
            if (set_obj.has_member ("language")) {
                settings.language = set_obj.get_string_member ("language");
            }
        }

        private void deserialize_services (Json.Object root_obj) {
            services.clear ();
            if (!root_obj.has_member ("services")) {
                return;
            }

            var srv_array = root_obj.get_array_member ("services");
            foreach (var srv_elem in srv_array.get_elements ()) {
                if (srv_elem.get_node_type () != Json.NodeType.OBJECT) {
                    continue;
                }
                var service = deserialize_single_service (srv_elem.get_object ());
                services.add (service);
            }
        }

        private ServiceDefinition deserialize_single_service (Json.Object s_obj) {
            string id = s_obj.has_member ("id") ? s_obj.get_string_member ("id") : "srv_" + GLib.Uuid.string_random ();
            string name = s_obj.has_member ("name") ? s_obj.get_string_member ("name") : "Unnamed";
            string working_dir = s_obj.has_member ("working_directory") ? s_obj.get_string_member ("working_directory") : "";
            string command = s_obj.has_member ("command") ? s_obj.get_string_member ("command") : "";
            string url = s_obj.has_member ("url") ? s_obj.get_string_member ("url") : "";

            var service = new ServiceDefinition (id, name, working_dir, command, url);

            if (s_obj.has_member ("use_shell")) {
                service.use_shell = s_obj.get_boolean_member ("use_shell");
            }
            if (s_obj.has_member ("load_dotenv")) {
                service.load_dotenv = s_obj.get_boolean_member ("load_dotenv");
            }
            if (s_obj.has_member ("auto_restart")) {
                service.auto_restart = s_obj.get_boolean_member ("auto_restart");
            }
            if (s_obj.has_member ("autostart")) {
                service.autostart = s_obj.get_boolean_member ("autostart");
            }

            if (s_obj.has_member ("environment")) {
                var env_obj = s_obj.get_object_member ("environment");
                foreach (var member in env_obj.get_members ()) {
                    service.environment.set (member, env_obj.get_string_member (member));
                }
            }

            if (s_obj.has_member ("variants")) {
                var var_array = s_obj.get_array_member ("variants");
                foreach (var var_elem in var_array.get_elements ()) {
                    if (var_elem.get_node_type () != Json.NodeType.OBJECT) {
                        continue;
                    }
                    service.variants.add (deserialize_single_variant (var_elem.get_object ()));
                }
            }

            return service;
        }

        private ServiceVariant deserialize_single_variant (Json.Object v_obj) {
            string v_id = v_obj.has_member ("id") ? v_obj.get_string_member ("id") : "var_" + GLib.Uuid.string_random ();
            string v_name = v_obj.has_member ("name") ? v_obj.get_string_member ("name") : "Variant";
            string v_cmd = v_obj.has_member ("command") ? v_obj.get_string_member ("command") : "";
            string v_url = v_obj.has_member ("url") ? v_obj.get_string_member ("url") : "";
            bool v_shell = v_obj.has_member ("use_shell") ? v_obj.get_boolean_member ("use_shell") : true;

            var variant = new ServiceVariant (v_id, v_name, v_cmd, v_url, v_shell);

            if (v_obj.has_member ("environment")) {
                var v_env_obj = v_obj.get_object_member ("environment");
                foreach (var member in v_env_obj.get_members ()) {
                    variant.environment.set (member, v_env_obj.get_string_member (member));
                }
            }

            return variant;
        }

        public bool save_to_json () {
            ensure_config_dir ();

            var builder = new Json.Builder ();
            builder.begin_object ();

            builder.set_member_name ("version");
            builder.add_int_value (1);

            serialize_settings (builder);
            serialize_services (builder);

            builder.end_object ();

            try {
                var generator = new Json.Generator ();
                generator.pretty = true;
                generator.set_root (builder.get_root ());
                generator.to_file (this.config_path);
                return true;
            } catch (GLib.Error e) {
                GLib.warning ("Error al guardar configuración JSON en %s: %s", this.config_path, e.message);
                return false;
            }
        }

        private void serialize_settings (Json.Builder builder) {
            builder.set_member_name ("settings");
            builder.begin_object ();
            builder.set_member_name ("poll_interval_seconds");
            builder.add_int_value (settings.poll_interval_seconds);
            builder.set_member_name ("max_log_lines");
            builder.add_int_value (settings.max_log_lines);
            builder.set_member_name ("enable_notifications");
            builder.add_boolean_value (settings.enable_notifications);
            builder.set_member_name ("autostart_on_login");
            builder.add_boolean_value (settings.autostart_on_login);
            builder.set_member_name ("language");
            builder.add_string_value (settings.language);
            builder.end_object ();
        }

        private void serialize_services (Json.Builder builder) {
            builder.set_member_name ("services");
            builder.begin_array ();

            foreach (var s in services) {
                serialize_single_service (builder, s);
            }

            builder.end_array ();
        }

        private void serialize_single_service (Json.Builder builder, ServiceDefinition s) {
            builder.begin_object ();

            builder.set_member_name ("id");
            builder.add_string_value (s.id);
            builder.set_member_name ("name");
            builder.add_string_value (s.name);
            builder.set_member_name ("working_directory");
            builder.add_string_value (s.working_directory);
            builder.set_member_name ("command");
            builder.add_string_value (s.command);
            builder.set_member_name ("url");
            builder.add_string_value (s.url);
            builder.set_member_name ("use_shell");
            builder.add_boolean_value (s.use_shell);
            builder.set_member_name ("load_dotenv");
            builder.add_boolean_value (s.load_dotenv);
            builder.set_member_name ("auto_restart");
            builder.add_boolean_value (s.auto_restart);
            builder.set_member_name ("autostart");
            builder.add_boolean_value (s.autostart);

            builder.set_member_name ("environment");
            builder.begin_object ();
            foreach (var entry in s.environment.entries) {
                builder.set_member_name (entry.key);
                builder.add_string_value (entry.value);
            }
            builder.end_object ();

            builder.set_member_name ("variants");
            builder.begin_array ();
            foreach (var v in s.variants) {
                serialize_single_variant (builder, v);
            }
            builder.end_array ();

            builder.end_object ();
        }

        private void serialize_single_variant (Json.Builder builder, ServiceVariant v) {
            builder.begin_object ();
            builder.set_member_name ("id");
            builder.add_string_value (v.id);
            builder.set_member_name ("name");
            builder.add_string_value (v.name);
            builder.set_member_name ("command");
            builder.add_string_value (v.command);
            builder.set_member_name ("url");
            builder.add_string_value (v.url);
            builder.set_member_name ("use_shell");
            builder.add_boolean_value (v.use_shell);

            builder.set_member_name ("environment");
            builder.begin_object ();
            foreach (var entry in v.environment.entries) {
                builder.set_member_name (entry.key);
                builder.add_string_value (entry.value);
            }
            builder.end_object ();

            builder.end_object ();
        }

        /* -------------------------------------------------------------
         * .env File Parsing
         * ------------------------------------------------------------- */

        public Gee.HashMap<string, string> parse_dotenv (string working_directory) {
            var env_map = new Gee.HashMap<string, string> ();
            if (working_directory.strip () == "") return env_map;

            string dotenv_path = GLib.Path.build_filename (working_directory, ".env");
            GLib.File file = GLib.File.new_for_path (dotenv_path);
            if (!file.query_exists ()) {
                return env_map;
            }

            try {
                var dis = new GLib.DataInputStream (file.read ());
                string? line = null;
                size_t length = 0;

                while ((line = dis.read_line (out length)) != null) {
                    parse_dotenv_line (line, env_map);
                }
            } catch (GLib.Error e) {
                GLib.warning ("Error al leer archivo .env en %s: %s", dotenv_path, e.message);
            }

            return env_map;
        }

        private void parse_dotenv_line (string line, Gee.HashMap<string, string> env_map) {
            string trimmed = line.strip ();
            if (trimmed == "" || trimmed.has_prefix ("#")) {
                return;
            }

            int equal_idx = trimmed.index_of_char ('=');
            if (equal_idx <= 0) {
                return;
            }

            string key = trimmed.substring (0, equal_idx).strip ();
            string raw_val = trimmed.substring (equal_idx + 1).strip ();
            string clean_val = strip_enclosing_quotes (raw_val);

            env_map.set (key, clean_val);
        }

        private string strip_enclosing_quotes (string raw_val) {
            bool is_double_quoted = raw_val.has_prefix ("\"") && raw_val.has_suffix ("\"");
            bool is_single_quoted = raw_val.has_prefix ("'") && raw_val.has_suffix ("'");

            if ((is_double_quoted || is_single_quoted) && raw_val.length >= 2) {
                return raw_val.substring (1, raw_val.length - 2);
            }

            return raw_val;
        }

        /* -------------------------------------------------------------
         * System Autostart Management (~/.config/autostart/)
         * ------------------------------------------------------------- */

        public bool is_autostart_configured () {
            GLib.File file = GLib.File.new_for_path (this.autostart_path);
            return file.query_exists ();
        }

        public bool set_autostart_configured (bool enable) {
            if (!enable) {
                return disable_autostart ();
            }
            return enable_autostart ();
        }

        private bool disable_autostart () {
            GLib.File file = GLib.File.new_for_path (this.autostart_path);
            settings.autostart_on_login = false;
            save_to_json ();

            if (!file.query_exists ()) {
                return true;
            }

            try {
                file.delete ();
                return true;
            } catch (GLib.Error e) {
                GLib.warning ("No se pudo eliminar archivo de autostart: %s", e.message);
                return false;
            }
        }

        private bool enable_autostart () {
            string autostart_dir = GLib.Path.get_dirname (this.autostart_path);
            GLib.File dir = GLib.File.new_for_path (autostart_dir);
            if (!dir.query_exists ()) {
                try {
                    dir.make_directory_with_parents ();
                } catch (GLib.Error e) {
                    GLib.warning ("No se pudo crear carpeta autostart %s: %s", autostart_dir, e.message);
                    return false;
                }
            }

            GLib.File file = GLib.File.new_for_path (this.autostart_path);
            string content = """[Desktop Entry]
Type=Application
Name=Daemonette
Comment=Background service manager for local development
Exec=daemonette
Icon=daemonette
Terminal=false
Categories=Development;Utility;
X-GNOME-Autostart-enabled=true
""";

            try {
                var stream = file.replace (null, false, GLib.FileCreateFlags.NONE);
                var dos = new GLib.DataOutputStream (stream);
                dos.put_string (content);
                dos.close ();

                settings.autostart_on_login = true;
                save_to_json ();
                return true;
            } catch (GLib.Error e) {
                GLib.warning ("No se pudo escribir archivo de autostart en %s: %s", this.autostart_path, e.message);
                return false;
            }
        }
    }
}
