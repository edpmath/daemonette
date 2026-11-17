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

        // Views & Docker / Compose inspector
        private Gtk.Box view_toolbar;
        private Gtk.Stack main_stack;
        private Gtk.StackSwitcher main_stack_switcher;
        private Gtk.Box container_filter_box;
        private Gtk.Label container_filter_label;
        private Gtk.ComboBoxText container_filter_combo;
        private Gtk.ScrolledWindow containers_scrolled;
        private Gtk.ListBox containers_listbox;

        private string? active_container_filter = null;
        private bool updating_filter_combo = false;

        private ulong log_output_handler_id = 0;
        private ulong metrics_handler_id = 0;
        private ulong status_handler_id = 0;
        private ulong lang_handler_id = 0;

        public signal void window_closed ();

        public LogViewerWindow (ServiceManager service_manager, ProcessRunner process_runner, ResourceMonitor resource_monitor, string? initial_service_id = null, string? initial_container_filter = null) {
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
            this.active_container_filter = (initial_container_filter != null && initial_container_filter != "" && initial_container_filter != "__all__") ? initial_container_filter : null;

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
            select_service (current_service_id, active_container_filter);

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
                GLib.warning ("Failed to load CSS styles: %s", e.message);
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

            // 2.2 View switcher & container filter toolbar
            view_toolbar = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8);
            view_toolbar.margin_start = 8;
            view_toolbar.margin_end = 8;
            view_toolbar.margin_top = 4;
            view_toolbar.margin_bottom = 4;

            main_stack = new Gtk.Stack ();
            main_stack.transition_type = Gtk.StackTransitionType.CROSSFADE;
            main_stack.vexpand = true;
            main_stack.hexpand = true;

            main_stack_switcher = new Gtk.StackSwitcher ();
            main_stack_switcher.stack = main_stack;
            view_toolbar.pack_start (main_stack_switcher, false, false, 0);

            container_filter_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            container_filter_label = new Gtk.Label (tr ("Filter:")) { xalign = 1 };
            container_filter_label.get_style_context ().add_class ("dim-label");
            container_filter_combo = new Gtk.ComboBoxText ();
            container_filter_combo.append ("__all__", tr ("🐳 All Containers"));
            container_filter_combo.active_id = "__all__";
            container_filter_combo.changed.connect (on_container_filter_changed);

            container_filter_box.pack_start (container_filter_label, false, false, 0);
            container_filter_box.pack_start (container_filter_combo, false, false, 0);
            view_toolbar.pack_end (container_filter_box, false, false, 0);
            view_toolbar.show_all ();

            main_box.pack_start (view_toolbar, false, false, 0);
            main_box.pack_start (new Gtk.Separator (Gtk.Orientation.HORIZONTAL), false, false, 0);

            // 2.3 Page 1: Logs
            var logs_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 0);

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
            logs_box.pack_start (scrolled_logs, true, true, 0);

            // Bottom bar in logs
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

            logs_box.pack_start (bottom_bar, false, false, 0);
            main_stack.add_titled (logs_box, "logs", tr ("📄 Logs"));

            // 2.4 Page 2: Containers
            containers_scrolled = new Gtk.ScrolledWindow (null, null);
            containers_scrolled.vexpand = true;
            containers_scrolled.hexpand = true;

            containers_listbox = new Gtk.ListBox ();
            containers_listbox.set_selection_mode (Gtk.SelectionMode.NONE);
            containers_scrolled.add (containers_listbox);
            main_stack.add_titled (containers_scrolled, "containers", tr ("🐳 Containers"));

            main_stack.notify["visible-child-name"].connect (() => {
                update_toolbar_visibility ();
            });

            main_box.pack_start (main_stack, true, true, 0);

            main_paned.pack2 (main_box, true, false);
            add (main_paned);
        }

        private void connect_signals () {
            // Incoming real-time log lines
            log_output_handler_id = process_runner.output_received.connect ((s_id, line, is_stderr) => {
                if (s_id != current_service_id) {
                    return;
                }
                if (active_container_filter != null && !line_matches_container_filter (line, active_container_filter)) {
                    return;
                }
                AnsiParser.insert_formatted (log_textbuffer, line);
                if (autoscroll_enabled) {
                    scroll_to_bottom ();
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
                if (current_service_id == null) {
                    return;
                }
                update_header_for_current_service ();
                refresh_sidebar_metrics ();
                if (main_stack.visible_child_name == "containers") {
                    refresh_containers_view ();
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
            container_filter_label.label = tr ("Filter:");
            refresh_sidebar ();
            update_header_for_current_service ();
        }

        public void select_service (string? service_id, string? container_name = null) {
            this.current_service_id = service_id;
            this.active_container_filter = (container_name != null && container_name != "" && container_name != "__all__") ? container_name : null;
            update_header_for_current_service ();
            reload_logs_for_current_service ();
            sync_sidebar_selection ();
        }

        private void sync_sidebar_selection () {
            foreach (var child in sidebar_listbox.get_children ()) {
                var row = (Gtk.ListBoxRow) child;
                string? s_id = row.get_data ("service_id");
                string? c_name = row.get_data ("container_name");
                if (s_id == current_service_id && c_name == active_container_filter) {
                    sidebar_listbox.select_row (row);
                    break;
                }
            }
        }

        private void refresh_sidebar () {
            foreach (var child in sidebar_listbox.get_children ()) {
                sidebar_listbox.remove (child);
            }

            var ordered_services = get_ordered_services ();
            int index_to_select = 0;
            int i = 0;

            foreach (var s in ordered_services) {
                var row = create_sidebar_service_row (s);
                if (s.id == current_service_id && active_container_filter == null) {
                    index_to_select = i;
                }
                sidebar_listbox.add (row);
                i++;

                bool has_containers = (s.service_type == ServiceType.COMPOSE || s.service_type == ServiceType.DOCKER) && s.docker_containers.size > 0;
                if (!has_containers) {
                    continue;
                }

                foreach (var c in s.docker_containers) {
                    var sub_row = create_sidebar_container_row (s, c);
                    if (s.id == current_service_id && active_container_filter == c.name) {
                        index_to_select = i;
                    }
                    sidebar_listbox.add (sub_row);
                    i++;
                }
            }

            sidebar_listbox.show_all ();

            var row_to_select = sidebar_listbox.get_row_at_index (index_to_select);
            if (row_to_select != null) {
                sidebar_listbox.select_row (row_to_select);
            }
        }

        private Gee.ArrayList<ServiceDefinition> get_ordered_services () {
            var ordered = new Gee.ArrayList<ServiceDefinition> ();
            var stacks = service_manager.get_stacks ();
            foreach (var st in stacks) {
                foreach (var s in service_manager.get_services_by_stack (st)) {
                    ordered.add (s);
                }
            }
            foreach (var s in service_manager.get_ungrouped_services ()) {
                ordered.add (s);
            }
            return ordered;
        }

        private Gtk.ListBoxRow create_sidebar_service_row (ServiceDefinition s) {
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

            string type_tag = "";
            if (s.service_type == ServiceType.COMPOSE) {
                type_tag = "🐳 ";
            } else if (s.service_type == ServiceType.DOCKER) {
                type_tag = "📦 ";
            }

            var title_lbl = new Gtk.Label ("%s %s%s".printf (bullet, type_tag, GLib.Markup.escape_text (s.name))) { use_markup = true, xalign = 0 };
            string mem_text = (s.status == ServiceStatus.RUNNING) ? s.metrics.format_memory () : tr ("Stopped");
            string subtitle = mem_text;
            if (s.service_type != ServiceType.PROCESS) {
                subtitle = "%s • %s".printf (subtitle, s.service_type.to_display_string ());
            }
            if (s.stack != "") {
                subtitle = "%s • %s".printf (subtitle, s.stack);
            }
            var mem_lbl = new Gtk.Label (subtitle) { xalign = 0 };
            mem_lbl.get_style_context ().add_class ("dim-label");

            box.pack_start (title_lbl, false, false, 0);
            box.pack_start (mem_lbl, false, false, 0);
            row.add (box);

            row.set_data ("service_id", s.id);
            row.set_data ("container_name", null);
            return row;
        }

        private Gtk.ListBoxRow create_sidebar_container_row (ServiceDefinition s, DockerContainerInfo c) {
            var sub_row = new Gtk.ListBoxRow ();
            var sub_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            sub_box.margin_top = 3;
            sub_box.margin_bottom = 3;
            sub_box.margin_end = 6;
            sub_box.margin_start = 22;

            string c_bullet = c.get_status_bullet ();
            var c_title = new Gtk.Label ("%s <span foreground='#cdd6f4'>%s</span>".printf (c_bullet, GLib.Markup.escape_text (c.name))) { use_markup = true, xalign = 0 };
            string c_sub = c.format_memory ();
            if (c.cpu_percent > 0.0) {
                c_sub += " • %.1f%% CPU".printf (c.cpu_percent);
            }
            if (c.state != "running") {
                c_sub = c.is_failed () ? tr ("Failed") : tr ("Stopped");
            }
            var c_mem = new Gtk.Label ("<span size='small' foreground='#a6adc8'>%s</span>".printf (c_sub)) { use_markup = true, xalign = 0 };

            sub_box.pack_start (c_title, false, false, 0);
            sub_box.pack_start (c_mem, false, false, 0);
            sub_row.add (sub_box);

            sub_row.set_data ("service_id", s.id);
            sub_row.set_data ("container_name", c.name);
            return sub_row;
        }

        private string get_container_status_bullet (DockerContainerInfo c) {
            return c.get_status_bullet ();
        }

        private int last_sidebar_container_count = -1;

        private void refresh_sidebar_metrics () {
            int total_containers = count_all_containers ();
            if (last_sidebar_container_count != -1 && total_containers != last_sidebar_container_count) {
                last_sidebar_container_count = total_containers;
                refresh_sidebar ();
                return;
            }
            last_sidebar_container_count = total_containers;

            foreach (var child in sidebar_listbox.get_children ()) {
                update_single_sidebar_row_metric ((Gtk.ListBoxRow) child);
            }
        }

        private int count_all_containers () {
            int count = 0;
            foreach (var s in service_manager.services) {
                count += s.docker_containers.size;
            }
            return count;
        }

        private void update_single_sidebar_row_metric (Gtk.ListBoxRow row) {
            string? s_id = row.get_data ("service_id");
            if (s_id == null) {
                return;
            }
            var s = service_manager.get_service (s_id);
            if (s == null) {
                return;
            }

            var box = (Gtk.Box) row.get_child ();
            var children = box.get_children ();
            if (children.length () <= 1) {
                return;
            }

            var title_lbl = (Gtk.Label) children.nth_data (0);
            var mem_lbl = (Gtk.Label) children.nth_data (1);
            string? c_name = row.get_data ("container_name");

            if (c_name != null) {
                update_container_row_metric (title_lbl, mem_lbl, s, c_name);
                return;
            }

            update_service_row_metric (title_lbl, mem_lbl, s);
        }

        private void update_container_row_metric (Gtk.Label title_lbl, Gtk.Label mem_lbl, ServiceDefinition s, string c_name) {
            DockerContainerInfo? matched_c = null;
            foreach (var c in s.docker_containers) {
                if (c.name == c_name || c.service_name == c_name) {
                    matched_c = c;
                    break;
                }
            }
            if (matched_c == null) {
                return;
            }

            string c_bullet = matched_c.get_status_bullet ();
            title_lbl.label = "%s <span foreground='#cdd6f4'>%s</span>".printf (c_bullet, GLib.Markup.escape_text (matched_c.name));

            string c_sub = matched_c.format_memory ();
            if (matched_c.cpu_percent > 0.0) {
                c_sub += " • %.1f%% CPU".printf (matched_c.cpu_percent);
            }
            if (matched_c.state != "running") {
                c_sub = matched_c.is_failed () ? tr ("Failed") : tr ("Stopped");
            }
            mem_lbl.label = "<span size='small' foreground='#a6adc8'>%s</span>".printf (c_sub);
        }

        private void update_service_row_metric (Gtk.Label title_lbl, Gtk.Label mem_lbl, ServiceDefinition s) {
            string bullet;
            switch (s.status) {
                case ServiceStatus.RUNNING: bullet = "🟢"; break;
                case ServiceStatus.STARTING: bullet = "🟡"; break;
                case ServiceStatus.STOPPING: bullet = "🟠"; break;
                case ServiceStatus.FAILED: bullet = "🔴"; break;
                case ServiceStatus.STOPPED:
                default: bullet = "⚪"; break;
            }

            string type_tag = "";
            if (s.service_type == ServiceType.COMPOSE) {
                type_tag = "🐳 ";
            } else if (s.service_type == ServiceType.DOCKER) {
                type_tag = "📦 ";
            }

            title_lbl.label = "%s %s%s".printf (bullet, type_tag, GLib.Markup.escape_text (s.name));

            string mem_text = (s.status == ServiceStatus.RUNNING) ? s.metrics.format_memory () : tr ("Stopped");
            string subtitle = mem_text;
            if (s.service_type != ServiceType.PROCESS) {
                subtitle = "%s • %s".printf (subtitle, s.service_type.to_display_string ());
            }
            if (s.stack != "") {
                subtitle = "%s • %s".printf (subtitle, s.stack);
            }
            mem_lbl.label = subtitle;
        }

        private void on_sidebar_row_selected (Gtk.ListBoxRow? row) {
            if (row == null) {
                return;
            }
            string? s_id = row.get_data ("service_id");
            if (s_id == null) {
                return;
            }
            string? c_name = row.get_data ("container_name");
            if (s_id == current_service_id && c_name == active_container_filter) {
                return;
            }
            select_service (s_id, c_name);
        }

        private void update_header_for_current_service () {
            if (current_service_id == null) {
                reset_header_to_empty ();
                update_toolbar_visibility ();
                return;
            }

            var s = service_manager.get_service (current_service_id);
            if (s == null) {
                update_toolbar_visibility ();
                return;
            }

            update_header_title_and_metrics (s);
            update_header_status_badge (s);

            browser_btn.sensitive = (s.url.strip () != "");
            terminal_btn.sensitive = (s.working_directory.strip () != "");

            update_container_tab_title (s);
            populate_container_filter_combo (s);
            update_toolbar_visibility ();
            refresh_containers_view ();
        }

        private void reset_header_to_empty () {
            title_label.label = tr ("No service selected");
            status_badge.label = tr ("Inactive");
            start_stop_btn.sensitive = false;
            restart_btn.sensitive = false;
            browser_btn.sensitive = false;
            terminal_btn.sensitive = false;
        }

        private void update_header_title_and_metrics (ServiceDefinition s) {
            DockerContainerInfo? matched_c = find_container_by_filter (s, active_container_filter);
            string type_badge = get_service_type_badge (s.service_type);

            if (matched_c != null) {
                string stack_part = (s.stack != "") ? " <span size='small' foreground='#89b4fa'>(%s)</span>".printf (GLib.Markup.escape_text (s.stack)) : "";
                title_label.label = "<b>%s</b>%s%s › <span foreground='#a6e3a1'><b>%s</b></span>".printf (
                    GLib.Markup.escape_text (s.name),
                    type_badge,
                    stack_part,
                    GLib.Markup.escape_text (matched_c.name)
                );
                metrics_label.label = tr ("Container RAM: %s | CPU: %.1f%% (Total stack: %s)").printf (
                    matched_c.format_memory (),
                    matched_c.cpu_percent,
                    s.metrics.format_memory ()
                );
                return;
            }

            if (active_container_filter != null) {
                string stack_part = (s.stack != "") ? " <span size='small' foreground='#89b4fa'>(%s)</span>".printf (GLib.Markup.escape_text (s.stack)) : "";
                title_label.label = "<b>%s</b>%s%s › <span foreground='#a6e3a1'><b>%s</b></span>".printf (
                    GLib.Markup.escape_text (s.name),
                    type_badge,
                    stack_part,
                    GLib.Markup.escape_text (active_container_filter)
                );
                metrics_label.label = tr ("RAM: %s | CPU: %.1f%% | Uptime: %s").printf (
                    s.metrics.format_memory (),
                    s.metrics.cpu_percent,
                    s.metrics.format_uptime ()
                );
                return;
            }

            if (s.stack != "") {
                title_label.label = "<b>%s</b>%s <span size='small' foreground='#89b4fa'>(Stack: %s)</span>".printf (
                    GLib.Markup.escape_text (s.name),
                    type_badge,
                    GLib.Markup.escape_text (s.stack)
                );
            } else {
                title_label.label = "<b>%s</b>%s".printf (
                    GLib.Markup.escape_text (s.name),
                    type_badge
                );
            }

            metrics_label.label = tr ("RAM: %s | CPU: %.1f%% | Uptime: %s").printf (
                s.metrics.format_memory (),
                s.metrics.cpu_percent,
                s.metrics.format_uptime ()
            );
        }

        private DockerContainerInfo? find_container_by_filter (ServiceDefinition s, string? filter) {
            if (filter == null || filter == "") {
                return null;
            }
            foreach (var c in s.docker_containers) {
                if (c.name == filter || c.service_name == filter) {
                    return c;
                }
            }
            return null;
        }

        private string get_service_type_badge (ServiceType st) {
            if (st == ServiceType.COMPOSE) {
                return " <span size='small' foreground='#a6e3a1'>[Compose]</span>";
            }
            if (st == ServiceType.DOCKER) {
                return " <span size='small' foreground='#89dceb'>[Docker]</span>";
            }
            return "";
        }

        private void update_header_status_badge (ServiceDefinition s) {
            DockerContainerInfo? matched_c = find_container_by_filter (s, active_container_filter);
            if (matched_c != null) {
                update_header_status_badge_for_container (matched_c);
                return;
            }
            update_header_status_badge_for_service (s);
        }

        private void update_header_status_badge_for_container (DockerContainerInfo c) {
            var ctx = status_badge.get_style_context ();
            ctx.remove_class ("status-running");
            ctx.remove_class ("status-stopped");
            ctx.remove_class ("status-failed");

            if (c.is_failed ()) {
                status_badge.label = tr ("Error / Failed");
                ctx.add_class ("status-failed");
                start_stop_btn.label = tr ("▶ Start");
                start_stop_btn.sensitive = true;
                restart_btn.sensitive = true;
                return;
            }

            if (c.is_running ()) {
                status_badge.label = tr ("Running");
                ctx.add_class ("status-running");
                start_stop_btn.label = tr ("⏹ Stop");
                start_stop_btn.sensitive = true;
                restart_btn.sensitive = true;
                return;
            }

            if (c.state == "starting") {
                status_badge.label = tr ("Starting...");
                ctx.add_class ("status-running");
                start_stop_btn.label = tr ("⏹ Stop");
                start_stop_btn.sensitive = true;
                restart_btn.sensitive = false;
                return;
            }

            status_badge.label = tr ("Stopped");
            ctx.add_class ("status-stopped");
            start_stop_btn.label = tr ("▶ Start");
            start_stop_btn.sensitive = true;
            restart_btn.sensitive = false;
        }

        private void update_header_status_badge_for_service (ServiceDefinition s) {
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
        }

        private void update_container_tab_title (ServiceDefinition s) {
            int count = s.docker_containers.size;
            string tab_title = (s.service_type == ServiceType.DOCKER)
                ? tr ("📦 Container")
                : (count > 0 ? tr ("🐳 Containers (%d)").printf (count) : tr ("🐳 Containers"));
            main_stack.child_set (containers_scrolled, "title", tab_title, null);
        }

        private void populate_container_filter_combo (ServiceDefinition s) {
            updating_filter_combo = true;
            string? prev_filter = active_container_filter;
            container_filter_combo.remove_all ();
            container_filter_combo.append ("__all__", tr ("🐳 All Containers"));

            bool found_prev = false;
            foreach (var c in s.docker_containers) {
                string target_name = c.name != "" ? c.name : c.service_name;
                if (target_name == "") {
                    continue;
                }
                container_filter_combo.append (target_name, target_name);
                if (prev_filter != null && (prev_filter == target_name || prev_filter == c.name || prev_filter == c.service_name)) {
                    found_prev = true;
                    prev_filter = target_name;
                }
            }

            if (found_prev && prev_filter != null) {
                container_filter_combo.active_id = prev_filter;
                active_container_filter = prev_filter;
            } else if (prev_filter != null && s.docker_containers.size == 0) {
                container_filter_combo.append (prev_filter, prev_filter);
                container_filter_combo.active_id = prev_filter;
                active_container_filter = prev_filter;
            } else {
                active_container_filter = null;
                container_filter_combo.active_id = "__all__";
            }
            updating_filter_combo = false;
        }

        private void update_toolbar_visibility () {
            if (current_service_id == null) {
                view_toolbar.hide ();
                return;
            }
            var s = service_manager.get_service (current_service_id);
            if (s == null) {
                view_toolbar.hide ();
                return;
            }

            bool is_docker = (s.service_type == ServiceType.COMPOSE || s.service_type == ServiceType.DOCKER);
            if (!is_docker) {
                view_toolbar.hide ();
                main_stack.set_visible_child_name ("logs");
                return;
            }

            view_toolbar.show ();
            main_stack_switcher.show ();
            string? page = main_stack.visible_child_name;
            if (page == null || page == "logs") {
                container_filter_box.show_all ();
                return;
            }

            container_filter_box.hide ();
        }

        private void on_container_filter_changed () {
            if (updating_filter_combo) return;
            string? active_id = container_filter_combo.active_id;
            if (active_id == null || active_id == "__all__") {
                active_container_filter = null;
            } else {
                active_container_filter = active_id;
            }
            update_header_for_current_service ();
            reload_logs_for_current_service ();
            sync_sidebar_selection ();
        }

        public static bool line_matches_container_filter (string line, string filter) {
            if (filter == "" || filter == "__all__") {
                return true;
            }
            string clean_line = AnsiParser.strip_ansi (line);
            if (matches_pipe_prefix (clean_line, filter)) {
                return true;
            }
            if (clean_line.contains (filter)) {
                return true;
            }
            if (clean_line.has_prefix ("--- [") && clean_line.contains (filter)) {
                return true;
            }
            return false;
        }

        private static bool matches_pipe_prefix (string clean_line, string filter) {
            int pipe_pos = clean_line.index_of ("|");
            if (pipe_pos <= 0) {
                return false;
            }
            string prefix = clean_line.substring (0, pipe_pos).strip ();
            return (prefix == filter || prefix.has_prefix (filter) || filter.has_prefix (prefix));
        }

        private void refresh_containers_view () {
            foreach (var child in containers_listbox.get_children ()) {
                containers_listbox.remove (child);
            }

            if (current_service_id == null) {
                return;
            }
            var s = service_manager.get_service (current_service_id);
            if (s == null) {
                return;
            }

            if (s.docker_containers.size == 0) {
                containers_listbox.add (create_empty_containers_row ());
                containers_listbox.show_all ();
                return;
            }

            foreach (var c in s.docker_containers) {
                containers_listbox.add (create_container_inspector_row (s, c));
            }

            containers_listbox.show_all ();
        }

        private Gtk.ListBoxRow create_empty_containers_row () {
            var empty_row = new Gtk.ListBoxRow ();
            var empty_lbl = new Gtk.Label (tr ("No active containers found for this service.")) {
                margin = 20,
                xalign = 0.5f
            };
            empty_lbl.get_style_context ().add_class ("dim-label");
            empty_row.add (empty_lbl);
            return empty_row;
        }

        private Gtk.ListBoxRow create_container_inspector_row (ServiceDefinition s, DockerContainerInfo c) {
            var row = new Gtk.ListBoxRow ();
            var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 12) { margin = 10 };

            var bullet_lbl = new Gtk.Label (get_container_status_bullet (c)) { xalign = 0.5f };
            box.pack_start (bullet_lbl, false, false, 0);

            box.pack_start (create_container_info_box (c), true, true, 0);
            box.pack_start (create_container_metrics_box (c), false, false, 8);
            box.pack_start (create_container_actions_box (s, c), false, false, 0);

            row.add (box);
            return row;
        }

        private Gtk.Box create_container_info_box (DockerContainerInfo c) {
            var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 3) { hexpand = true };
            string name_str = "<b>%s</b>".printf (GLib.Markup.escape_text (c.name));
            if (c.service_name != "" && c.service_name != c.name) {
                name_str += " <span size='small' foreground='#89dceb'>(service: %s)</span>".printf (GLib.Markup.escape_text (c.service_name));
            }
            var name_lbl = new Gtk.Label (name_str) { use_markup = true, xalign = 0 };

            string sub_text = tr ("image: %s").printf (GLib.Markup.escape_text (c.image));
            if (c.status_text != "") {
                sub_text += " • " + GLib.Markup.escape_text (c.status_text);
            }
            if (c.health != "") {
                string h_color = (c.health == "healthy") ? "#a6e3a1" : "#f38ba8";
                sub_text += " • <span foreground='%s'><b>%s</b></span>".printf (h_color, GLib.Markup.escape_text (c.health));
            }
            var sub_lbl = new Gtk.Label (sub_text) { use_markup = true, xalign = 0 };
            sub_lbl.get_style_context ().add_class ("dim-label");

            info_box.pack_start (name_lbl, false, false, 0);
            info_box.pack_start (sub_lbl, false, false, 0);

            if (c.ports != "") {
                var ports_lbl = new Gtk.Label ("<span size='small' foreground='#cdd6f4'>%s</span>".printf (GLib.Markup.escape_text (c.ports))) { use_markup = true, xalign = 0 };
                info_box.pack_start (ports_lbl, false, false, 0);
            }
            return info_box;
        }

        private Gtk.Box create_container_metrics_box (DockerContainerInfo c) {
            var metrics_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
            var ram_lbl = new Gtk.Label ("<b>%s</b>".printf (c.format_memory ())) { use_markup = true, xalign = 1 };
            var cpu_lbl = new Gtk.Label ("<span size='small' foreground='#a6adc8'>%.1f%% CPU</span>".printf (c.cpu_percent)) { use_markup = true, xalign = 1 };
            metrics_box.pack_start (ram_lbl, false, false, 0);
            metrics_box.pack_start (cpu_lbl, false, false, 0);
            return metrics_box;
        }

        private Gtk.Box create_container_actions_box (ServiceDefinition s, DockerContainerInfo c) {
            var actions_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 4);

            var view_btn = new Gtk.Button.from_icon_name ("text-x-generic-symbolic", Gtk.IconSize.BUTTON);
            view_btn.tooltip_text = tr ("View logs for %s").printf (c.name);
            string c_name = c.name;
            view_btn.clicked.connect (() => {
                select_container_logs (c_name);
            });
            actions_box.pack_start (view_btn, false, false, 0);

            if (s.service_type == ServiceType.COMPOSE) {
                append_compose_container_action_buttons (actions_box, s, c);
            }

            return actions_box;
        }

        private void append_compose_container_action_buttons (Gtk.Box actions_box, ServiceDefinition s, DockerContainerInfo c) {
            string target_subservice = c.service_name != "" ? c.service_name : c.name;

            if (c.state != "running") {
                var start_btn = new Gtk.Button.from_icon_name ("media-playback-start-symbolic", Gtk.IconSize.BUTTON);
                start_btn.tooltip_text = tr ("Start container %s").printf (target_subservice);
                start_btn.clicked.connect (() => {
                    start_compose_subservice (s, target_subservice);
                });
                actions_box.pack_start (start_btn, false, false, 0);
            } else {
                var stop_btn = new Gtk.Button.from_icon_name ("media-playback-stop-symbolic", Gtk.IconSize.BUTTON);
                stop_btn.tooltip_text = tr ("Stop container %s").printf (target_subservice);
                stop_btn.clicked.connect (() => {
                    stop_compose_subservice (s, target_subservice);
                });
                actions_box.pack_start (stop_btn, false, false, 0);
            }

            var restart_btn = new Gtk.Button.from_icon_name ("view-refresh-symbolic", Gtk.IconSize.BUTTON);
            restart_btn.tooltip_text = tr ("Restart container %s").printf (target_subservice);
            restart_btn.clicked.connect (() => {
                restart_compose_subservice (s, target_subservice);
            });
            actions_box.pack_start (restart_btn, false, false, 0);
        }

        private void select_container_logs (string container_name) {
            updating_filter_combo = true;
            container_filter_combo.active_id = container_name;
            active_container_filter = container_name;
            updating_filter_combo = false;

            main_stack.set_visible_child_name ("logs");
            update_header_for_current_service ();
            reload_logs_for_current_service ();
            sync_sidebar_selection ();
        }

        private void start_compose_subservice (ServiceDefinition service, string subservice_name) {
            var buf = process_runner.get_log_buffer (service.id);
            string header = "--- [Starting container: %s] ---".printf (subservice_name);
            buf.append (header, false);
            reload_logs_for_current_service ();

            DockerRunner.start_compose_subservice_async.begin (service, subservice_name, (obj, res) => {
                bool ok = DockerRunner.start_compose_subservice_async.end (res);
                string msg = ok
                    ? "--- [Container %s started successfully] ---".printf (subservice_name)
                    : "--- [Failed to start container %s] ---".printf (subservice_name);
                buf.append (msg, !ok);
                resource_monitor.poll_all_services ();
                reload_logs_for_current_service ();
            });
        }

        private void stop_compose_subservice (ServiceDefinition service, string subservice_name) {
            var buf = process_runner.get_log_buffer (service.id);
            string header = "--- [Stopping container: %s] ---".printf (subservice_name);
            buf.append (header, false);
            reload_logs_for_current_service ();

            DockerRunner.stop_compose_subservice_async.begin (service, subservice_name, (obj, res) => {
                bool ok = DockerRunner.stop_compose_subservice_async.end (res);
                string msg = ok
                    ? "--- [Container %s stopped successfully] ---".printf (subservice_name)
                    : "--- [Failed to stop container %s] ---".printf (subservice_name);
                buf.append (msg, !ok);
                resource_monitor.poll_all_services ();
                reload_logs_for_current_service ();
            });
        }

        private void restart_compose_subservice (ServiceDefinition service, string subservice_name) {
            var buf = process_runner.get_log_buffer (service.id);
            string header = "--- [Restarting container: %s] ---".printf (subservice_name);
            buf.append (header, false);
            reload_logs_for_current_service ();

            DockerRunner.restart_compose_subservice_async.begin (service, subservice_name, (obj, res) => {
                bool ok = DockerRunner.restart_compose_subservice_async.end (res);
                string msg = ok
                    ? "--- [Container %s restarted successfully] ---".printf (subservice_name)
                    : "--- [Failed to restart container %s] ---".printf (subservice_name);
                buf.append (msg, !ok);
                resource_monitor.poll_all_services ();
                reload_logs_for_current_service ();
            });
        }

        private void reload_logs_for_current_service () {
            log_textbuffer.text = "";
            if (current_service_id == null) {
                return;
            }

            var buf = process_runner.get_log_buffer (current_service_id);
            var entries = buf.get_entries ();
            foreach (var e in entries) {
                if (active_container_filter != null && !line_matches_container_filter (e.text, active_container_filter)) {
                    continue;
                }
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

            DockerContainerInfo? matched_c = find_container_by_filter (s, active_container_filter);
            if (matched_c != null && s.service_type == ServiceType.COMPOSE) {
                string target_sub = matched_c.service_name != "" ? matched_c.service_name : matched_c.name;
                if (matched_c.is_running ()) {
                    stop_compose_subservice (s, target_sub);
                } else {
                    start_compose_subservice (s, target_sub);
                }
                return;
            }

            if (s.status == ServiceStatus.RUNNING || s.status == ServiceStatus.STARTING) {
                process_runner.stop_service (s.id);
                return;
            }

            process_runner.start_service (s, null);
        }

        private void on_restart_clicked () {
            if (current_service_id == null) return;
            var s = service_manager.get_service (current_service_id);
            if (s == null) return;

            DockerContainerInfo? matched_c = find_container_by_filter (s, active_container_filter);
            if (matched_c != null && s.service_type == ServiceType.COMPOSE) {
                string target_sub = matched_c.service_name != "" ? matched_c.service_name : matched_c.name;
                restart_compose_subservice (s, target_sub);
                return;
            }

            process_runner.restart_service (s, s.active_variant_id);
        }

        private void on_browser_clicked () {
            if (current_service_id == null) return;
            var s = service_manager.get_service (current_service_id);
            if (s == null || s.url.strip () == "") return;
            try {
                GLib.AppInfo.launch_default_for_uri (s.url.strip (), null);
            } catch (GLib.Error e) {
                GLib.warning ("Failed to open URL %s: %s", s.url, e.message);
            }
        }

        private void on_terminal_clicked () {
            if (current_service_id == null) return;
            var s = service_manager.get_service (current_service_id);
            if (s == null) return;
            TerminalLauncher.open_terminal (s.working_directory);
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
