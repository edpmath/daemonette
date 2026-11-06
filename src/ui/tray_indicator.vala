/* src/ui/tray_indicator.vala
 * System tray indicator (Ayatana AppIndicator) with hierarchical context menus.
 */

namespace Daemonette {

    public class TrayIndicator : Object {
        private AppIndicator.Indicator indicator;
        private ServiceManager service_manager;
        private ProcessRunner process_runner;
        private ResourceMonitor resource_monitor;
        private Gtk.Menu? current_menu;
        private Gtk.MenuItem? header_item = null;
        private Gee.HashMap<string, Gtk.MenuItem> service_items;

        public signal void request_new_service ();
        public signal void request_edit_service (string service_id);
        public signal void request_open_logs (string? service_id);
        public signal void request_quit ();

        public TrayIndicator (ServiceManager service_manager, ProcessRunner process_runner, ResourceMonitor resource_monitor) {
            this.service_manager = service_manager;
            this.process_runner = process_runner;
            this.resource_monitor = resource_monitor;
            this.service_items = new Gee.HashMap<string, Gtk.MenuItem> ();

            this.indicator = new AppIndicator.Indicator (
                "daemonette",
                "daemonette",
                AppIndicator.IndicatorCategory.APPLICATION_STATUS
            );
            setup_icon_theme ();
            this.indicator.set_status (AppIndicator.IndicatorStatus.ACTIVE);
            this.indicator.set_title ("Daemonette");

            // Listen to events to refresh the menu
            service_manager.service_added.connect ((s) => update_menu ());
            service_manager.service_updated.connect ((s) => update_menu ());
            service_manager.service_removed.connect ((id) => update_menu ());
            service_manager.services_reloaded.connect (() => update_menu ());

            process_runner.status_changed.connect ((id, st) => update_menu ());
            resource_monitor.metrics_updated.connect (() => update_metrics_labels ());

            // React immediately to language switching
            I18n.get_instance ().language_changed.connect (() => update_menu ());

            update_menu ();
        }

        public void update_menu () {
            var menu = new Gtk.Menu ();

            int running_count = 0;
            int failed_count = 0;
            uint64 total_ram = 0;
            count_service_stats (out running_count, out failed_count, out total_ram);

            update_indicator_icon (failed_count);

            // 1. Top summary header
            menu.append (build_header_item (running_count, total_ram));
            menu.append (new Gtk.SeparatorMenuItem ());

            // 2. Individual submenus per service
            populate_services_section (menu);
            menu.append (new Gtk.SeparatorMenuItem ());

            // 3. Global actions
            append_global_actions (menu, running_count);
            menu.append (new Gtk.SeparatorMenuItem ());

            // 4. Autostart on boot
            menu.append (build_autostart_item ());

            // 5. Language selector
            menu.append (build_language_item ());

            // 6. Quit
            menu.append (build_quit_item ());

            menu.show_all ();
            this.indicator.set_menu (menu);
            this.current_menu = menu;
        }

        private void count_service_stats (out int running_count, out int failed_count, out uint64 total_ram) {
            running_count = 0;
            failed_count = 0;
            total_ram = 0;

            foreach (var s in service_manager.services) {
                if (s.status == ServiceStatus.RUNNING || s.status == ServiceStatus.STARTING) {
                    running_count++;
                    total_ram += s.metrics.memory_rss_bytes;
                    continue;
                }
                if (s.status == ServiceStatus.FAILED) {
                    failed_count++;
                }
            }
        }

        private void setup_icon_theme () {
            // First check working directory / assets
            string local_assets = GLib.Path.build_filename (GLib.Environment.get_current_dir (), "assets");
            if (GLib.FileUtils.test (local_assets, GLib.FileTest.IS_DIR)) {
                indicator.set_icon_theme_path (local_assets);
                return;
            }

            // Fallback: check relative to binary location
            try {
                string exe_target = GLib.FileUtils.read_link ("/proc/self/exe");
                string exe_dir = GLib.Path.get_dirname (exe_target);
                string relative_assets = GLib.Path.build_filename (exe_dir, "..", "assets");
                if (GLib.FileUtils.test (relative_assets, GLib.FileTest.IS_DIR)) {
                    indicator.set_icon_theme_path (relative_assets);
                    return;
                }
            } catch (GLib.Error e) {
                // Ignore if link read fails
            }
        }

        private void update_indicator_icon (int failed_count) {
            if (failed_count > 0) {
                indicator.set_status (AppIndicator.IndicatorStatus.ATTENTION);
                indicator.set_attention_icon_full ("dialog-warning", tr ("Daemonette - Service error"));
                return;
            }
            indicator.set_status (AppIndicator.IndicatorStatus.ACTIVE);
            indicator.set_icon_full ("daemonette", "Daemonette");
        }

        private Gtk.MenuItem build_header_item (int running_count, uint64 total_ram) {
            string ram_str = format_bytes (total_ram);
            string header_text = (running_count > 0)
                ? tr ("[●] %d active | Total RAM: %s").printf (running_count, ram_str)
                : tr ("[○] 0 active (Idle)");

            var item = new Gtk.MenuItem.with_label (header_text);
            item.set_sensitive (false);
            this.header_item = item;
            return item;
        }

        private void populate_services_section (Gtk.Menu menu) {
            service_items.clear ();
            if (service_manager.services.size == 0) {
                var empty_item = new Gtk.MenuItem.with_label (tr ("(No registered services)"));
                empty_item.set_sensitive (false);
                menu.append (empty_item);
                return;
            }

            foreach (var s in service_manager.services) {
                var item = create_service_submenu_item (s);
                service_items.set (s.id, item);
                menu.append (item);
            }
        }

        private void append_global_actions (Gtk.Menu menu, int running_count) {
            var new_service_item = new Gtk.MenuItem.with_label (tr ("➕ Register new service..."));
            new_service_item.activate.connect (() => {
                request_new_service ();
            });
            menu.append (new_service_item);

            var stop_all_item = new Gtk.MenuItem.with_label (tr ("🛑 Stop all services"));
            stop_all_item.set_sensitive (running_count > 0);
            stop_all_item.activate.connect (() => {
                process_runner.stop_all ();
            });
            menu.append (stop_all_item);

            var logs_item = new Gtk.MenuItem.with_label (tr ("📋 Global Log Viewer..."));
            logs_item.activate.connect (() => {
                request_open_logs (null);
            });
            menu.append (logs_item);
        }

        private Gtk.MenuItem build_autostart_item () {
            var autostart_item = new Gtk.CheckMenuItem.with_label (tr ("Start Daemonette on boot"));
            autostart_item.set_active (service_manager.is_autostart_configured ());
            autostart_item.toggled.connect (() => {
                service_manager.set_autostart_configured (autostart_item.get_active ());
            });
            return autostart_item;
        }

        private Gtk.MenuItem build_language_item () {
            var lang_item = new Gtk.MenuItem.with_label (tr ("🌐 Language"));
            var lang_sub = new Gtk.Menu ();

            string current_mode = service_manager.settings.language;

            var sys_item = new Gtk.RadioMenuItem.with_label (null, tr ("System Default (Auto)"));
            sys_item.set_active (current_mode == "system");
            sys_item.toggled.connect (() => {
                if (sys_item.active) {
                    service_manager.set_language ("system");
                }
            });
            lang_sub.append (sys_item);

            unowned GLib.SList<Gtk.RadioMenuItem> group = sys_item.get_group ();

            var en_item = new Gtk.RadioMenuItem.with_label (group, "English");
            en_item.set_active (current_mode == "en");
            en_item.toggled.connect (() => {
                if (en_item.active) {
                    service_manager.set_language ("en");
                }
            });
            lang_sub.append (en_item);

            var es_item = new Gtk.RadioMenuItem.with_label (group, "Español");
            es_item.set_active (current_mode == "es");
            es_item.toggled.connect (() => {
                if (es_item.active) {
                    service_manager.set_language ("es");
                }
            });
            lang_sub.append (es_item);

            lang_item.set_submenu (lang_sub);
            return lang_item;
        }

        private Gtk.MenuItem build_quit_item () {
            var quit_item = new Gtk.MenuItem.with_label (tr ("🚪 Quit Daemonette"));
            quit_item.activate.connect (() => {
                request_quit ();
            });
            return quit_item;
        }

        private Gtk.MenuItem create_service_submenu_item (ServiceDefinition service) {
            string status_bullet;
            string extra_info;
            resolve_status_indicator (service, out status_bullet, out extra_info);

            string label = "%s %s %s".printf (status_bullet, service.name, extra_info);
            var main_item = new Gtk.MenuItem.with_label (label);
            var submenu = new Gtk.Menu ();

            if (service.status == ServiceStatus.RUNNING || service.status == ServiceStatus.STARTING) {
                build_running_service_submenu (submenu, service);
                main_item.set_submenu (submenu);
                return main_item;
            }

            build_stopped_service_submenu (submenu, service);
            main_item.set_submenu (submenu);
            return main_item;
        }

        private void resolve_status_indicator (ServiceDefinition service, out string status_bullet, out string extra_info) {
            switch (service.status) {
                case ServiceStatus.RUNNING:
                    status_bullet = "🟢";
                    extra_info = "(%s)".printf (service.metrics.format_memory ());
                    return;
                case ServiceStatus.STARTING:
                    status_bullet = "🟡";
                    extra_info = "(%s)".printf (tr ("Starting..."));
                    return;
                case ServiceStatus.STOPPING:
                    status_bullet = "🟠";
                    extra_info = "(%s)".printf (tr ("Stopping..."));
                    return;
                case ServiceStatus.FAILED:
                    status_bullet = "🔴";
                    extra_info = "(%s)".printf (tr ("Error"));
                    return;
                case ServiceStatus.STOPPED:
                default:
                    status_bullet = "⚪";
                    extra_info = "(%s)".printf (tr ("Stopped"));
                    return;
            }
        }

        private void build_running_service_submenu (Gtk.Menu submenu, ServiceDefinition service) {
            var stop_item = new Gtk.MenuItem.with_label (tr ("⏹ Stop"));
            stop_item.activate.connect (() => {
                process_runner.stop_service (service.id);
            });
            submenu.append (stop_item);

            var restart_item = new Gtk.MenuItem.with_label (tr ("🔄 Restart"));
            restart_item.activate.connect (() => {
                process_runner.restart_service (service, service.active_variant_id);
            });
            submenu.append (restart_item);

            submenu.append (new Gtk.SeparatorMenuItem ());

            string target_url = get_effective_url (service);
            if (target_url != "") {
                var browser_item = new Gtk.MenuItem.with_label (tr ("🌐 Open in Browser (%s)").printf (target_url));
                browser_item.activate.connect (() => {
                    try {
                        GLib.AppInfo.launch_default_for_uri (target_url, null);
                    } catch (GLib.Error e) {
                        GLib.warning ("No se pudo abrir URL %s: %s", target_url, e.message);
                    }
                });
                submenu.append (browser_item);
            }

            append_common_service_actions (submenu, service, tr ("📋 View Logs & Resources..."));
        }

        private void build_stopped_service_submenu (Gtk.Menu submenu, ServiceDefinition service) {
            var start_item = new Gtk.MenuItem.with_label (tr ("▶ Start Default (%s)").printf (service.command));
            start_item.activate.connect (() => {
                process_runner.start_service (service, null);
            });
            submenu.append (start_item);

            foreach (var v in service.variants) {
                string v_label = tr ("⚡ Variant: %s").printf (v.name);
                var var_item = new Gtk.MenuItem.with_label (v_label);
                string v_id = v.id;
                var_item.activate.connect (() => {
                    process_runner.start_service (service, v_id);
                });
                submenu.append (var_item);
            }

            submenu.append (new Gtk.SeparatorMenuItem ());
            append_common_service_actions (submenu, service, tr ("📋 View Previous Logs..."));
        }

        private void append_common_service_actions (Gtk.Menu submenu, ServiceDefinition service, string logs_label) {
            var term_item = new Gtk.MenuItem.with_label (tr ("💻 Open Terminal in Folder"));
            term_item.activate.connect (() => {
                TerminalLauncher.open_terminal (service.working_directory);
            });
            submenu.append (term_item);

            var log_item = new Gtk.MenuItem.with_label (logs_label);
            log_item.activate.connect (() => {
                request_open_logs (service.id);
            });
            submenu.append (log_item);

            var edit_item = new Gtk.MenuItem.with_label (tr ("⚙️ Configure Service..."));
            edit_item.activate.connect (() => {
                request_edit_service (service.id);
            });
            submenu.append (edit_item);
        }

        private string get_effective_url (ServiceDefinition service) {
            if (service.active_variant_id != null) {
                var v = service.find_variant (service.active_variant_id);
                if (v != null && v.url.strip () != "") {
                    return v.url.strip ();
                }
            }
            return service.url.strip ();
        }

        private void update_metrics_labels () {
            int running_count = 0;
            int failed_count = 0;
            uint64 total_ram = 0;
            count_service_stats (out running_count, out failed_count, out total_ram);

            if (header_item != null) {
                string ram_str = format_bytes (total_ram);
                header_item.label = (running_count > 0)
                    ? tr ("[●] %d active | Total RAM: %s").printf (running_count, ram_str)
                    : tr ("[○] 0 active (Idle)");
            }

            foreach (var entry in service_items.entries) {
                var s = service_manager.get_service (entry.key);
                if (s != null) {
                    string status_bullet;
                    string extra_info;
                    resolve_status_indicator (s, out status_bullet, out extra_info);
                    entry.value.label = "%s %s %s".printf (status_bullet, s.name, extra_info);
                }
            }
        }

        private string format_bytes (uint64 bytes) {
            if (bytes < 1024 * 1024) {
                return "%llu KB".printf (bytes / 1024);
            }
            if (bytes < 1024ULL * 1024ULL * 1024ULL) {
                return "%.1f MB".printf ((double) bytes / (1024.0 * 1024.0));
            }
            return "%.2f GB".printf ((double) bytes / (1024.0 * 1024.0 * 1024.0));
        }
    }
}
