/* src/ui/log_viewer_window.vala
 * Centralized minimal log viewer and real-time resource monitor window.
 */

namespace Daemonette {

    public class LogViewerWindow : Gtk.Window {
        private ServiceManager service_manager;
        private ProcessRunner process_runner;
        private ResourceMonitor resource_monitor;

        private string? current_service_id = null;
        private bool autoscroll_enabled = true;

        // UI widgets
        private Gtk.ListBox sidebar_listbox;
        private Gtk.Label sidebar_header;
        private Gtk.Label title_label;
        private Gtk.Label status_badge;
        private Gtk.Label metrics_label;
        private Gtk.Button start_stop_btn;
        private Gtk.Button restart_btn;
        private Gtk.Button browser_btn;
        private Gtk.Button terminal_btn;

        private Gtk.TextView log_textview;
        private Gtk.TextBuffer log_textbuffer;
        private Gtk.ScrolledWindow scrolled_logs;
        private Gtk.ToggleButton autoscroll_toggle;
        private Gtk.Button clear_btn;
        private Gtk.Button copy_btn;

        private ulong log_output_handler_id = 0;
        private ulong metrics_handler_id = 0;
        private ulong status_handler_id = 0;
        private ulong lang_handler_id = 0;

        public signal void window_closed ();

        public LogViewerWindow (ServiceManager service_manager, ProcessRunner process_runner, ResourceMonitor resource_monitor, string? initial_service_id = null) {
            Object (
                title: tr ("Daemonette - Log Viewer & Resource Monitor"),
                default_width: 880,
                default_height: 560,
                window_position: Gtk.WindowPosition.CENTER
            );

            this.service_manager = service_manager;
            this.process_runner = process_runner;
            this.resource_monitor = resource_monitor;
            this.current_service_id = initial_service_id;

            // Notify resource monitor to switch to high-frequency polling
            resource_monitor.set_high_frequency_mode (true);

            setup_css ();
            setup_ui ();
            connect_signals ();

            // Select initial service or the first available one
            if (current_service_id == null && service_manager.services.size > 0) {
                current_service_id = service_manager.services.get (0).id;
            }

            refresh_sidebar ();
            select_service (current_service_id);

            delete_event.connect (on_delete_event);
        }

        private void setup_css () {
            var css = new Gtk.CssProvider ();
            try {
                css.load_from_data ("""
                    .log-view {
                        font-family: monospace;
                        font-size: 9.5pt;
                        background-color: #1e1e2e;
                        color: #cdd6f4;
                    }
                    .status-pill {
                        border-radius: 12px;
                        padding: 2px 10px;
                        font-weight: bold;
                        font-size: 0.85em;
                    }
                    .status-running {
                        background-color: #a6e3a1;
                        color: #11111b;
                    }
                    .status-stopped {
                        background-color: #45475a;
                        color: #cdd6f4;
                    }
                    .status-failed {
                        background-color: #f38ba8;
                        color: #11111b;
                    }
                    .metrics-pill {
                        color: #a6adc8;
                        font-size: 0.9em;
                    }
                """);
                Gtk.StyleContext.add_provider_for_screen (
                    Gdk.Screen.get_default (),
                    css,
                    Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
                );
            } catch (GLib.Error e) {
                GLib.warning ("Error al cargar estilos CSS: %s", e.message);
            }
        }

        private void setup_ui () {
            var main_paned = new Gtk.Paned (Gtk.Orientation.HORIZONTAL);
            main_paned.set_position (220);

            // 1. Sidebar (Services list)
            var sidebar_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            sidebar_box.set_size_request (180, -1);
            sidebar_box.border_width = 8;

            sidebar_header = new Gtk.Label (tr ("Services")) { xalign = 0 };
            sidebar_header.get_style_context ().add_class ("dim-label");
            sidebar_box.pack_start (sidebar_header, false, false, 4);

            var scrolled_sidebar = new Gtk.ScrolledWindow (null, null);
            scrolled_sidebar.hscrollbar_policy = Gtk.PolicyType.NEVER;
            scrolled_sidebar.vexpand = true;

            sidebar_listbox = new Gtk.ListBox ();
            sidebar_listbox.set_selection_mode (Gtk.SelectionMode.SINGLE);
            sidebar_listbox.row_selected.connect (on_sidebar_row_selected);
            scrolled_sidebar.add (sidebar_listbox);
            sidebar_box.pack_start (scrolled_sidebar, true, true, 0);

            main_paned.pack1 (sidebar_box, false, false);

            // 2. Main panel (Logs and controls area)
            var main_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

            // 2.1 Header
            var header_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 10);
            header_box.border_width = 10;

            var title_info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3);
            var title_row = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            title_label = new Gtk.Label (tr ("Select a service")) { xalign = 0 };
            title_label.use_markup = true;

            status_badge = new Gtk.Label (tr ("Stopped"));
            status_badge.get_style_context ().add_class ("status-pill");
            status_badge.get_style_context ().add_class ("status-stopped");

            title_row.pack_start (title_label, false, false, 0);
            title_row.pack_start (status_badge, false, false, 0);
            title_info_box.pack_start (title_row, false, false, 0);

            metrics_label = new Gtk.Label (tr ("RAM: 0 KB | CPU: 0.0% | Uptime: 0s")) { xalign = 0 };
            metrics_label.get_style_context ().add_class ("metrics-pill");
            title_info_box.pack_start (metrics_label, false, false, 0);

            header_box.pack_start (title_info_box, true, true, 0);

            // Quick action buttons in header
            start_stop_btn = new Gtk.Button.with_label (tr ("▶ Start"));
            start_stop_btn.clicked.connect (on_start_stop_clicked);
            header_box.pack_end (start_stop_btn, false, false, 0);

            restart_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic", Gtk.IconSize.BUTTON);
            restart_btn.tooltip_text = tr ("Restart service");
            restart_btn.clicked.connect (on_restart_clicked);
            header_box.pack_end (restart_btn, false, false, 0);

            browser_btn = new Gtk.Button.from_icon_name ("web-browser-symbolic", Gtk.IconSize.BUTTON);
            browser_btn.tooltip_text = tr ("Open in browser");
            browser_btn.clicked.connect (on_browser_clicked);
            header_box.pack_end (browser_btn, false, false, 0);

            terminal_btn = new Gtk.Button.from_icon_name ("utilities-terminal-symbolic", Gtk.IconSize.BUTTON);
            terminal_btn.tooltip_text = tr ("Open terminal in folder");
            terminal_btn.clicked.connect (on_terminal_clicked);
            header_box.pack_end (terminal_btn, false, false, 0);

            main_box.pack_start (header_box, false, false, 0);
            main_box.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);

            // 2.2 Log text display area
            scrolled_logs = new Gtk.ScrolledWindow (null, null);
            scrolled_logs.vexpand = true;
            scrolled_logs.hexpand = true;

            log_textbuffer = new Gtk.TextBuffer (null);
            AnsiParser.setup_tags (log_textbuffer);

            log_textview = new Gtk.TextView.with_buffer (log_textbuffer);
            log_textview.editable = false;
            log_textview.cursor_visible = false;
            log_textview.monospace = true;
            log_textview.left_margin = 10;
            log_textview.right_margin = 10;
            log_textview.top_margin = 8;
            log_textview.bottom_margin = 8;
            log_textview.get_style_context ().add_class ("log-view");

            scrolled_logs.add (log_textview);
            main_box.pack_start (scrolled_logs, true, true, 0);

            // 2.3 Minimal bottom status/action bar
            var bottom_bar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            bottom_bar.border_width = 6;

            clear_btn = new Gtk.Button.with_label (tr ("Clear"));
            clear_btn.tooltip_text = tr ("Clear log display");
            clear_btn.clicked.connect (() => {
                log_textbuffer.text = "";
                if (current_service_id != null) {
                    process_runner.get_log_buffer (current_service_id).clear ();
                }
            });
            bottom_bar.pack_start (clear_btn, false, false, 0);

            copy_btn = new Gtk.Button.with_label (tr ("Copy"));
            copy_btn.tooltip_text = tr ("Copy logs to clipboard");
            copy_btn.clicked.connect (() => {
                var clipboard = Gtk.Clipboard.get_default (Gdk.Display.get_default ());
                clipboard.set_text (log_textbuffer.text, -1);
            });
            bottom_bar.pack_start (copy_btn, false, false, 0);

            autoscroll_toggle = new Gtk.ToggleButton.with_label (tr ("⬇ Auto-scroll"));
            autoscroll_toggle.active = true;
            autoscroll_toggle.toggled.connect (() => {
                autoscroll_enabled = autoscroll_toggle.active;
            });
            bottom_bar.pack_end (autoscroll_toggle, false, false, 0);

            main_box.pack_start (bottom_bar, false, false, 0);

            main_paned.pack2 (main_box, true, false);
            add (main_paned);
        }

        private void connect_signals () {
            // Incoming real-time log lines
            log_output_handler_id = process_runner.output_received.connect ((s_id, line, is_stderr) => {
                if (s_id == current_service_id) {
                    AnsiParser.insert_formatted (log_textbuffer, line);
                    if (autoscroll_enabled) {
                        scroll_to_bottom ();
                    }
                }
            });

            // Service status updates
            status_handler_id = process_runner.status_changed.connect ((s_id, status) => {
                refresh_sidebar ();
                if (s_id == current_service_id) {
                    update_header_for_current_service ();
                }
            });

            // CPU / RAM metrics updates
            metrics_handler_id = resource_monitor.metrics_updated.connect (() => {
                if (current_service_id != null) {
                    update_header_for_current_service ();
                    refresh_sidebar_metrics ();
                }
            });

            // Language changes
            lang_handler_id = I18n.get_instance ().language_changed.connect (() => {
                on_language_changed ();
            });
        }

        private void on_language_changed () {
            this.title = tr ("Daemonette - Log Viewer & Resource Monitor");
            sidebar_header.label = tr ("Services");
            clear_btn.label = tr ("Clear");
            clear_btn.tooltip_text = tr ("Clear log display");
            copy_btn.label = tr ("Copy");
            copy_btn.tooltip_text = tr ("Copy logs to clipboard");
            autoscroll_toggle.label = tr ("⬇ Auto-scroll");
            restart_btn.tooltip_text = tr ("Restart service");
            browser_btn.tooltip_text = tr ("Open in browser");
            terminal_btn.tooltip_text = tr ("Open terminal in folder");
            refresh_sidebar ();
            update_header_for_current_service ();
        }

        public void select_service (string? service_id) {
            this.current_service_id = service_id;
            update_header_for_current_service ();
            reload_logs_for_current_service ();
        }

        private void refresh_sidebar () {
            // Clear current list items
            foreach (var child in sidebar_listbox.get_children ()) {
                sidebar_listbox.remove (child);
            }

            int index_to_select = 0;
            int i = 0;

            foreach (var s in service_manager.services) {
                var row = new Gtk.ListBoxRow ();
                var box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2) { margin = 6 };

                string bullet;
                switch (s.status) {
                    case ServiceStatus.RUNNING: bullet = "🟢"; break;
                    case ServiceStatus.STARTING: bullet = "🟡"; break;
                    case ServiceStatus.STOPPING: bullet = "🟠"; break;
                    case ServiceStatus.FAILED: bullet = "🔴"; break;
                    case ServiceStatus.STOPPED:
                    default: bullet = "⚪"; break;
                }

                var title_lbl = new Gtk.Label ("%s %s".printf (bullet, s.name)) { xalign = 0 };
                var mem_lbl = new Gtk.Label (s.status == ServiceStatus.RUNNING ? s.metrics.format_memory () : tr ("Stopped")) { xalign = 0 };
                mem_lbl.get_style_context ().add_class ("dim-label");

                box.pack_start (title_lbl, false, false, 0);
                box.pack_start (mem_lbl, false, false, 0);
                row.add (box);

                // Store service_id in the row widget
                row.set_data ("service_id", s.id);

                if (s.id == current_service_id) {
                    index_to_select = i;
                }

                sidebar_listbox.add (row);
                i++;
            }

            sidebar_listbox.show_all ();

            var row_to_select = sidebar_listbox.get_row_at_index (index_to_select);
            if (row_to_select != null) {
                sidebar_listbox.select_row (row_to_select);
            }
        }

        private void refresh_sidebar_metrics () {
            int i = 0;
            foreach (var s in service_manager.services) {
                var row = sidebar_listbox.get_row_at_index (i);
                if (row != null) {
                    var box = (Gtk.Box) row.get_child ();
                    var children = box.get_children ();
                    if (children.length () > 1) {
                        var mem_lbl = (Gtk.Label) children.nth_data (1);
                        mem_lbl.label = (s.status == ServiceStatus.RUNNING) ? s.metrics.format_memory () : tr ("Stopped");
                    }
                }
                i++;
            }
        }

        private void on_sidebar_row_selected (Gtk.ListBoxRow? row) {
            if (row == null) return;
            string? s_id = row.get_data ("service_id");
            if (s_id != null && s_id != current_service_id) {
                select_service (s_id);
            }
        }

        private void update_header_for_current_service () {
            if (current_service_id == null) {
                title_label.label = tr ("No service selected");
                status_badge.label = tr ("Inactive");
                start_stop_btn.sensitive = false;
                restart_btn.sensitive = false;
                browser_btn.sensitive = false;
                terminal_btn.sensitive = false;
                return;
            }

            var s = service_manager.get_service (current_service_id);
            if (s == null) return;

            title_label.label = "<b>%s</b>".printf (GLib.Markup.escape_text (s.name));

            // Update status badge
            var ctx = status_badge.get_style_context ();
            ctx.remove_class ("status-running");
            ctx.remove_class ("status-stopped");
            ctx.remove_class ("status-failed");

            switch (s.status) {
                case ServiceStatus.RUNNING:
                    status_badge.label = tr ("Running");
                    ctx.add_class ("status-running");
                    start_stop_btn.label = tr ("⏹ Stop");
                    start_stop_btn.sensitive = true;
                    restart_btn.sensitive = true;
                    break;
                case ServiceStatus.STARTING:
                    status_badge.label = tr ("Starting...");
                    ctx.add_class ("status-running");
                    start_stop_btn.label = tr ("⏹ Stop");
                    start_stop_btn.sensitive = true;
                    restart_btn.sensitive = false;
                    break;
                case ServiceStatus.STOPPING:
                    status_badge.label = tr ("Stopping...");
                    ctx.add_class ("status-stopped");
                    start_stop_btn.sensitive = false;
                    restart_btn.sensitive = false;
                    break;
                case ServiceStatus.FAILED:
                    status_badge.label = tr ("Error / Crashed");
                    ctx.add_class ("status-failed");
                    start_stop_btn.label = tr ("▶ Start");
                    start_stop_btn.sensitive = true;
                    restart_btn.sensitive = true;
                    break;
                case ServiceStatus.STOPPED:
                default:
                    status_badge.label = tr ("Stopped");
                    ctx.add_class ("status-stopped");
                    start_stop_btn.label = tr ("▶ Start");
                    start_stop_btn.sensitive = true;
                    restart_btn.sensitive = false;
                    break;
            }

            metrics_label.label = tr ("RAM: %s | CPU: %.1f%% | Uptime: %s").printf (
                s.metrics.format_memory (),
                s.metrics.cpu_percent,
                s.metrics.format_uptime ()
            );

            browser_btn.sensitive = (s.url.strip () != "");
            terminal_btn.sensitive = (s.working_directory.strip () != "");
        }

        private void reload_logs_for_current_service () {
            log_textbuffer.text = "";
            if (current_service_id == null) return;

            var buf = process_runner.get_log_buffer (current_service_id);
            var entries = buf.get_entries ();
            foreach (var e in entries) {
                AnsiParser.insert_formatted (log_textbuffer, e.text);
            }

            if (autoscroll_enabled) {
                scroll_to_bottom ();
            }
        }

        private void scroll_to_bottom () {
            Gtk.TextIter end_iter;
            log_textbuffer.get_end_iter (out end_iter);
            var mark = log_textbuffer.create_mark (null, end_iter, false);
            log_textview.scroll_to_mark (mark, 0.0, false, 0.0, 1.0);
            log_textbuffer.delete_mark (mark);
        }

        private void on_start_stop_clicked () {
            if (current_service_id == null) return;
            var s = service_manager.get_service (current_service_id);
            if (s == null) return;

            if (s.status == ServiceStatus.RUNNING || s.status == ServiceStatus.STARTING) {
                process_runner.stop_service (s.id);
                return;
            }

            process_runner.start_service (s, null);
        }

        private void on_restart_clicked () {
            if (current_service_id == null) return;
            var s = service_manager.get_service (current_service_id);
            if (s != null) {
                process_runner.restart_service (s, s.active_variant_id);
            }
        }

        private void on_browser_clicked () {
            if (current_service_id == null) return;
            var s = service_manager.get_service (current_service_id);
            if (s != null && s.url.strip () != "") {
                try {
                    GLib.AppInfo.launch_default_for_uri (s.url.strip (), null);
                } catch (GLib.Error e) {
                    GLib.warning ("No se pudo abrir URL %s: %s", s.url, e.message);
                }
            }
        }

        private void on_terminal_clicked () {
            if (current_service_id == null) return;
            var s = service_manager.get_service (current_service_id);
            if (s != null) {
                TerminalLauncher.open_terminal (s.working_directory);
            }
        }

        private bool on_delete_event () {
            // Disconnect signal handlers to prevent memory leaks
            if (log_output_handler_id != 0) {
                process_runner.disconnect (log_output_handler_id);
                log_output_handler_id = 0;
            }
            if (status_handler_id != 0) {
                process_runner.disconnect (status_handler_id);
                status_handler_id = 0;
            }
            if (metrics_handler_id != 0) {
                resource_monitor.disconnect (metrics_handler_id);
                metrics_handler_id = 0;
            }
            if (lang_handler_id != 0) {
                I18n.get_instance ().disconnect (lang_handler_id);
                lang_handler_id = 0;
            }

            // Return resource monitor to low-frequency polling mode
            resource_monitor.set_high_frequency_mode (false);
            window_closed ();

            return false; // Allow normal window destruction
        }
    }
}
