/* src/ui/service_editor_dialog.vala
 * Modal GTK3 dialog to add, edit, duplicate, and delete services and their variants.
 * Supports native processes, Docker Compose, and standalone Docker containers.
 */

namespace Daemonette {

    public class ServiceEditorDialog : Gtk.Dialog {
        private ServiceManager service_manager;
        private ServiceDefinition? target_service;
        private bool is_edit_mode;

        // Main form widgets
        private Gtk.ComboBoxText type_combo;
        private Gtk.Entry name_entry;
        private Gtk.Entry stack_entry;
        private Gtk.Label dir_label;
        private Gtk.FileChooserButton dir_chooser;
        private Gtk.Label command_label;
        private Gtk.Entry command_entry;
        private Gtk.Label compose_file_label;
        private Gtk.Box compose_file_box;
        private Gtk.Entry compose_file_entry;
        private Gtk.Button compose_file_btn;
        private Gtk.Label compose_service_label;
        private Gtk.Entry compose_service_entry;
        private Gtk.Label container_name_label;
        private Gtk.Entry container_name_entry;
        private Gtk.Label url_label;
        private Gtk.Entry url_entry;

        // Toggles
        private Gtk.Frame options_frame;
        private Gtk.CheckButton shell_check;
        private Gtk.CheckButton dotenv_check;
        private Gtk.CheckButton autorestart_check;
        private Gtk.CheckButton autostart_check;

        // Variant management
        private Gee.ArrayList<ServiceVariant> variants_list;
        private Gtk.ListBox variants_listbox;

        public ServiceEditorDialog (Gtk.Window? parent, ServiceManager service_manager, string? service_id = null) {
            Object (
                title: service_id == null ? tr ("Register New Service") : tr ("Configure Service"),
                transient_for: parent,
                modal: true,
                destroy_with_parent: true,
                use_header_bar: 1
            );

            this.service_manager = service_manager;
            this.is_edit_mode = (service_id != null);
            this.variants_list = new Gee.ArrayList<ServiceVariant> ();

            if (is_edit_mode) {
                this.target_service = service_manager.get_service (service_id);
            }

            set_default_size (580, 640);
            border_width = 10;

            setup_ui ();
            load_data ();
        }

        private void setup_ui () {
            var content_area = get_content_area ();
            content_area.spacing = 12;

            var notebook = new Gtk.Notebook ();

            // Tab 1: General
            var general_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 10);
            general_box.border_width = 12;

            var grid = new Gtk.Grid ();
            grid.column_spacing = 12;
            grid.row_spacing = 10;

            // Row 0: Service Type
            grid.attach (new Gtk.Label (tr ("Service Type:")) { xalign = 0 }, 0, 0, 1, 1);
            type_combo = new Gtk.ComboBoxText ();
            type_combo.append ("process", tr ("Local Process (Command)"));
            type_combo.append ("compose", tr ("Docker Compose"));
            type_combo.append ("docker", tr ("Docker Container"));
            type_combo.active_id = "process";
            type_combo.changed.connect (on_service_type_changed);
            grid.attach (type_combo, 1, 0, 1, 1);

            // Row 1: Name
            grid.attach (new Gtk.Label (tr ("Service Name:")) { xalign = 0 }, 0, 1, 1, 1);
            name_entry = new Gtk.Entry ();
            name_entry.placeholder_text = tr ("e.g. Quasar Frontend, Backend API...");
            name_entry.hexpand = true;
            grid.attach (name_entry, 1, 1, 1, 1);

            // Row 2: Stack (Optional)
            grid.attach (new Gtk.Label (tr ("Stack (Optional):")) { xalign = 0 }, 0, 2, 1, 1);
            stack_entry = new Gtk.Entry ();
            stack_entry.placeholder_text = tr ("e.g. MyApp, E-Commerce, Backend Services...");
            stack_entry.hexpand = true;
            var completion = new Gtk.EntryCompletion ();
            var list_store = new Gtk.ListStore (1, typeof (string));
            foreach (var st in service_manager.get_stacks ()) {
                Gtk.TreeIter iter;
                list_store.append (out iter);
                list_store.set (iter, 0, st, -1);
            }
            completion.set_model (list_store);
            completion.set_text_column (0);
            completion.inline_completion = true;
            completion.popup_completion = true;
            stack_entry.set_completion (completion);
            grid.attach (stack_entry, 1, 2, 1, 1);

            // Row 3: Working directory
            dir_label = new Gtk.Label (tr ("Working Directory:")) { xalign = 0 };
            grid.attach (dir_label, 0, 3, 1, 1);
            dir_chooser = new Gtk.FileChooserButton (tr ("Select project directory"), Gtk.FileChooserAction.SELECT_FOLDER);
            dir_chooser.hexpand = true;
            grid.attach (dir_chooser, 1, 3, 1, 1);

            // Row 4: Command (for process or docker run override)
            command_label = new Gtk.Label (tr ("Main Command:")) { xalign = 0 };
            grid.attach (command_label, 0, 4, 1, 1);
            command_entry = new Gtk.Entry ();
            command_entry.placeholder_text = tr ("e.g. quasar dev, npm run dev, python main.py");
            command_entry.hexpand = true;
            grid.attach (command_entry, 1, 4, 1, 1);

            // Row 5: Compose file
            compose_file_label = new Gtk.Label (tr ("Docker Compose File:")) { xalign = 0 };
            grid.attach (compose_file_label, 0, 5, 1, 1);

            compose_file_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            compose_file_entry = new Gtk.Entry ();
            compose_file_entry.placeholder_text = "docker-compose.yml";
            compose_file_entry.hexpand = true;
            compose_file_box.pack_start (compose_file_entry, true, true, 0);

            compose_file_btn = new Gtk.Button.from_icon_name ("document-open-symbolic", Gtk.IconSize.BUTTON);
            compose_file_btn.tooltip_text = tr ("Browse...");
            compose_file_btn.clicked.connect (on_browse_compose_file);
            compose_file_box.pack_end (compose_file_btn, false, false, 0);
            grid.attach (compose_file_box, 1, 5, 1, 1);

            // Row 6: Compose subservice
            compose_service_label = new Gtk.Label (tr ("Subservice (Optional):")) { xalign = 0 };
            grid.attach (compose_service_label, 0, 6, 1, 1);
            compose_service_entry = new Gtk.Entry ();
            compose_service_entry.placeholder_text = tr ("Leave empty for all services in Compose");
            compose_service_entry.hexpand = true;
            grid.attach (compose_service_entry, 1, 6, 1, 1);

            // Row 7: Container name
            container_name_label = new Gtk.Label (tr ("Container Name / ID:")) { xalign = 0 };
            grid.attach (container_name_label, 0, 7, 1, 1);
            container_name_entry = new Gtk.Entry ();
            container_name_entry.placeholder_text = "e.g. postgres-dev, my-redis";
            container_name_entry.hexpand = true;
            grid.attach (container_name_entry, 1, 7, 1, 1);

            // Row 8: URL
            url_label = new Gtk.Label (tr ("Local URL (Optional):")) { xalign = 0 };
            grid.attach (url_label, 0, 8, 1, 1);
            url_entry = new Gtk.Entry ();
            url_entry.placeholder_text = tr ("e.g. http://localhost:9000");
            url_entry.hexpand = true;
            grid.attach (url_entry, 1, 8, 1, 1);

            general_box.pack_start (grid, false, false, 0);

            // Execution options and toggles
            options_frame = new Gtk.Frame (tr ("Execution Options"));
            var options_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 6);
            options_box.border_width = 10;

            shell_check = new Gtk.CheckButton.with_label (tr ("Run via shell ($SHELL - supports pipes and variables)"));
            shell_check.active = true;
            options_box.pack_start (shell_check, false, false, 0);

            dotenv_check = new Gtk.CheckButton.with_label (tr ("Automatically load local .env variables"));
            dotenv_check.active = true;
            options_box.pack_start (dotenv_check, false, false, 0);

            autorestart_check = new Gtk.CheckButton.with_label (tr ("Automatically restart if process crashes"));
            autorestart_check.active = false;
            options_box.pack_start (autorestart_check, false, false, 0);

            autostart_check = new Gtk.CheckButton.with_label (tr ("Automatically start service when opening Daemonette"));
            autostart_check.active = false;
            options_box.pack_start (autostart_check, false, false, 0);

            options_frame.add (options_box);
            general_box.pack_start (options_frame, false, false, 0);

            notebook.append_page (general_box, new Gtk.Label (tr ("General")));

            // Tab 2: Variants
            var variants_page = new Gtk.Box (Gtk.Orientation.VERTICAL, 8);
            variants_page.border_width = 12;

            var var_header = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var var_info_label = new Gtk.Label (tr ("Command variants (e.g. test mode, watchers, etc.):")) { xalign = 0 };
            var_header.pack_start (var_info_label, true, true, 0);

            var add_var_btn = new Gtk.Button.with_label (tr ("➕ Add Variant"));
            add_var_btn.clicked.connect (on_add_variant_clicked);
            var_header.pack_end (add_var_btn, false, false, 0);
            variants_page.pack_start (var_header, false, false, 0);

            var scrolled_var = new Gtk.ScrolledWindow (null, null);
            scrolled_var.vexpand = true;
            variants_listbox = new Gtk.ListBox ();
            variants_listbox.set_selection_mode (Gtk.SelectionMode.NONE);
            variants_listbox.row_activated.connect ((row) => {
                int idx = row.get_index ();
                if (idx >= 0 && idx < variants_list.size) {
                    open_variant_dialog (variants_list.get (idx), idx);
                }
            });
            scrolled_var.add (variants_listbox);
            variants_page.pack_start (scrolled_var, true, true, 0);

            notebook.append_page (variants_page, new Gtk.Label (tr ("Variants")));

            content_area.pack_start (notebook, true, true, 0);

            // Action buttons in header / footer
            add_button (tr ("Cancel"), Gtk.ResponseType.CANCEL);

            if (is_edit_mode && target_service != null) {
                // Duplicate button
                var duplicate_btn = new Gtk.Button.with_label (tr ("Duplicate"));
                duplicate_btn.tooltip_text = tr ("Create a copy of this service");
                duplicate_btn.clicked.connect (() => {
                    service_manager.duplicate_service (target_service.id);
                    destroy ();
                });
                var header = get_header_bar ();
                if (header != null) {
                    header.pack_start (duplicate_btn);
                }

                // Delete button
                var delete_btn = new Gtk.Button.with_label (tr ("Delete"));
                delete_btn.get_style_context ().add_class ("destructive-action");
                delete_btn.clicked.connect (on_delete_clicked);
                if (header != null) {
                    header.pack_start (delete_btn);
                }
            }

            var save_btn = (Gtk.Button) add_button (tr ("Save"), Gtk.ResponseType.OK);
            save_btn.get_style_context ().add_class ("suggested-action");

            response.connect (on_response);
            on_service_type_changed ();
            show_all ();
        }

        private void on_service_type_changed () {
            string type_id = type_combo.get_active_id () ?? "process";
            switch (type_id) {
                case "compose":
                    command_label.hide ();
                    command_entry.hide ();
                    container_name_label.hide ();
                    container_name_entry.hide ();
                    compose_file_label.show ();
                    compose_file_box.show ();
                    compose_service_label.show ();
                    compose_service_entry.show ();
                    shell_check.hide ();
                    dotenv_check.hide ();
                    break;
                case "docker":
                    compose_file_label.hide ();
                    compose_file_box.hide ();
                    compose_service_label.hide ();
                    compose_service_entry.hide ();
                    container_name_label.show ();
                    container_name_entry.show ();
                    command_label.label = tr ("Docker Run Command (Optional):");
                    command_entry.placeholder_text = tr ("e.g. docker run --rm -p 5432:5432 postgres:16");
                    command_label.show ();
                    command_entry.show ();
                    shell_check.hide ();
                    dotenv_check.hide ();
                    break;
                case "process":
                default:
                    compose_file_label.hide ();
                    compose_file_box.hide ();
                    compose_service_label.hide ();
                    compose_service_entry.hide ();
                    container_name_label.hide ();
                    container_name_entry.hide ();
                    command_label.label = tr ("Main Command:");
                    command_entry.placeholder_text = tr ("e.g. quasar dev, npm run dev, python main.py");
                    command_label.show ();
                    command_entry.show ();
                    shell_check.show ();
                    dotenv_check.show ();
                    break;
            }
        }

        private void on_browse_compose_file () {
            var file_dialog = new Gtk.FileChooserDialog (
                tr ("Select Compose File (*.yml, *.yaml)"),
                this,
                Gtk.FileChooserAction.OPEN,
                tr ("Cancel"), Gtk.ResponseType.CANCEL,
                tr ("Select"), Gtk.ResponseType.ACCEPT,
                null
            );

            var filter = new Gtk.FileFilter ();
            filter.set_filter_name ("Docker Compose (*.yml, *.yaml)");
            filter.add_pattern ("*.yml");
            filter.add_pattern ("*.yaml");
            file_dialog.add_filter (filter);

            string current_dir = dir_chooser.get_filename () ?? GLib.Environment.get_home_dir ();
            file_dialog.set_current_folder (current_dir);

            if (file_dialog.run () == Gtk.ResponseType.ACCEPT) {
                string chosen = file_dialog.get_filename ();
                compose_file_entry.text = chosen;
                if (dir_chooser.get_filename () == null || dir_chooser.get_filename () == "") {
                    dir_chooser.set_filename (GLib.Path.get_dirname (chosen));
                }
                update_compose_services_completion (chosen);
            }
            file_dialog.destroy ();
        }

        private void update_compose_services_completion (string compose_path) {
            var services = DockerRunner.get_compose_services (compose_path);
            if (services.size > 0) {
                var comp = new Gtk.EntryCompletion ();
                var store = new Gtk.ListStore (1, typeof (string));
                foreach (var s in services) {
                    Gtk.TreeIter iter;
                    store.append (out iter);
                    store.set (iter, 0, s, -1);
                }
                comp.set_model (store);
                comp.set_text_column (0);
                comp.inline_completion = true;
                comp.popup_completion = true;
                compose_service_entry.set_completion (comp);
            }
        }

        private void load_data () {
            if (!is_edit_mode || target_service == null) {
                dir_chooser.set_current_folder (GLib.Environment.get_home_dir ());
                type_combo.active_id = "process";
                on_service_type_changed ();
                return;
            }

            type_combo.active_id = target_service.service_type.to_string_id ();
            name_entry.text = target_service.name;
            stack_entry.text = target_service.stack;
            if (target_service.working_directory.strip () != "") {
                dir_chooser.set_filename (target_service.working_directory);
            }
            command_entry.text = target_service.command;
            compose_file_entry.text = target_service.compose_file;
            compose_service_entry.text = target_service.compose_service;
            container_name_entry.text = target_service.container_name;
            url_entry.text = target_service.url;
            shell_check.active = target_service.use_shell;
            dotenv_check.active = target_service.load_dotenv;
            autorestart_check.active = target_service.auto_restart;
            autostart_check.active = target_service.autostart;

            if (target_service.compose_file.strip () != "") {
                string resolved = DockerRunner.resolve_compose_file (target_service);
                update_compose_services_completion (resolved);
            }

            variants_list.clear ();
            foreach (var v in target_service.variants) {
                variants_list.add (v.clone ());
            }
            refresh_variants_list ();
            on_service_type_changed ();
        }

        private void refresh_variants_list () {
            clear_variants_listbox ();

            if (variants_list.size == 0) {
                append_empty_variant_row ();
                variants_listbox.show_all ();
                return;
            }

            append_variant_rows ();
            variants_listbox.show_all ();
        }

        private void clear_variants_listbox () {
            foreach (var child in variants_listbox.get_children ()) {
                variants_listbox.remove (child);
            }
        }

        private void append_empty_variant_row () {
            var empty_row = new Gtk.ListBoxRow ();
            var empty_lbl = new Gtk.Label (tr ("No variants added.")) { margin = 12 };
            empty_lbl.get_style_context ().add_class ("dim-label");
            empty_row.add (empty_lbl);
            variants_listbox.add (empty_row);
        }

        private void append_variant_rows () {
            for (int i = 0; i < variants_list.size; i++) {
                int index = i;
                var v = variants_list.get (i);
                var row = new Gtk.ListBoxRow ();
                var box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 8) { margin = 6 };

                var info_box = new Gtk.Box (Gtk.Orientation.VERTICAL, 2);
                string v_icon = (v.icon != null && v.icon.strip () != "") ? v.icon.strip () : "⚡";
                var title_lbl = new Gtk.Label ("%s %s".printf (v_icon, v.name)) { xalign = 0 };
                var cmd_lbl = new Gtk.Label (v.command) { xalign = 0 };
                cmd_lbl.get_style_context ().add_class ("dim-label");
                info_box.pack_start (title_lbl, false, false, 0);
                info_box.pack_start (cmd_lbl, false, false, 0);

                box.pack_start (info_box, true, true, 0);

                // Edit button
                var edit_btn = new Gtk.Button.from_icon_name ("document-edit-symbolic", Gtk.IconSize.BUTTON);
                edit_btn.tooltip_text = tr ("Edit this variant");
                edit_btn.clicked.connect (() => {
                    open_variant_dialog (v, index);
                });
                box.pack_end (edit_btn, false, false, 0);

                // Delete button
                var del_btn = new Gtk.Button.from_icon_name ("user-trash-symbolic", Gtk.IconSize.BUTTON);
                del_btn.tooltip_text = tr ("Delete this variant");
                del_btn.clicked.connect (() => {
                    variants_list.remove_at (index);
                    refresh_variants_list ();
                });
                box.pack_end (del_btn, false, false, 0);

                row.add (box);
                variants_listbox.add (row);
            }
        }

        private void on_add_variant_clicked () {
            open_variant_dialog (null, -1);
        }

        private void open_variant_dialog (ServiceVariant? existing_variant = null, int index = -1) {
            bool is_edit = (existing_variant != null);
            var diag = new Gtk.Dialog.with_buttons (
                is_edit ? tr ("Edit Variant") : tr ("Add Variant"),
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                tr ("Cancel"), Gtk.ResponseType.CANCEL,
                is_edit ? tr ("Save") : tr ("Add"), Gtk.ResponseType.OK,
                null
            );

            var area = diag.get_content_area ();
            area.spacing = 8;
            area.border_width = 12;

            // Icon / Emoji selector
            area.pack_start (new Gtk.Label (tr ("Icon / Emoji:")) { xalign = 0 }, false, false, 0);
            var icon_box = new Gtk.Box (Gtk.Orientation.HORIZONTAL, 6);
            var v_icon = new Gtk.Entry ();
            v_icon.text = (is_edit && existing_variant.icon != null && existing_variant.icon.strip () != "") ? existing_variant.icon : "⚡";
            v_icon.width_chars = 4;
            icon_box.pack_start (v_icon, false, false, 0);

            // Quick emoji presets
            string[] preset_emojis = { "⚡", "🧪", "🔧", "🚀", "🐛", "📦", "🔄", "📊", "🌐", "⚙️" };
            foreach (var emoji in preset_emojis) {
                string e = emoji;
                var pill = new Gtk.Button.with_label (e);
                pill.clicked.connect (() => {
                    v_icon.text = e;
                });
                icon_box.pack_start (pill, false, false, 0);
            }
            area.pack_start (icon_box, false, false, 0);

            var v_name = new Gtk.Entry () { placeholder_text = tr ("Name (e.g. E2E Mode)") };
            if (is_edit) v_name.text = existing_variant.name;

            var v_cmd = new Gtk.Entry () { placeholder_text = tr ("Alternative command") };
            if (is_edit) v_cmd.text = existing_variant.command;

            var v_url = new Gtk.Entry () { placeholder_text = tr ("Specific URL (optional)") };
            if (is_edit) v_url.text = existing_variant.url;

            var v_shell = new Gtk.CheckButton.with_label (tr ("Run via shell ($SHELL)")) {
                active = is_edit ? existing_variant.use_shell : true
            };

            area.pack_start (new Gtk.Label (tr ("Variant name:")) { xalign = 0 }, false, false, 0);
            area.pack_start (v_name, false, false, 0);
            area.pack_start (new Gtk.Label (tr ("Command:")) { xalign = 0 }, false, false, 0);
            area.pack_start (v_cmd, false, false, 0);
            area.pack_start (new Gtk.Label (tr ("Local URL (optional):")) { xalign = 0 }, false, false, 0);
            area.pack_start (v_url, false, false, 0);
            area.pack_start (v_shell, false, false, 0);

            diag.show_all ();
            if (diag.run () == Gtk.ResponseType.OK) {
                string name = v_name.text.strip ();
                string cmd = v_cmd.text.strip ();
                string icon = v_icon.text.strip () != "" ? v_icon.text.strip () : "⚡";
                string url = v_url.text.strip ();
                bool shell = v_shell.active;

                if (name != "" && cmd != "") {
                    if (is_edit && existing_variant != null && index >= 0) {
                        existing_variant.name = name;
                        existing_variant.command = cmd;
                        existing_variant.url = url;
                        existing_variant.icon = icon;
                        existing_variant.use_shell = shell;
                        variants_list.set (index, existing_variant);
                    } else {
                        string var_id = "var_" + GLib.Uuid.string_random ();
                        var new_var = new ServiceVariant (var_id, name, cmd, url, shell, icon);
                        variants_list.add (new_var);
                    }
                    refresh_variants_list ();
                }
            }
            diag.destroy ();
        }

        private void on_delete_clicked () {
            if (target_service == null) return;

            var confirm = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                Gtk.MessageType.WARNING,
                Gtk.ButtonsType.CANCEL,
                tr ("Are you sure you want to delete service '%s'?"),
                target_service.name
            );
            confirm.secondary_text = tr ("This action cannot be undone.");
            confirm.add_button (tr ("Delete Permanently"), Gtk.ResponseType.ACCEPT);

            int res = confirm.run ();
            confirm.destroy ();

            if (res == Gtk.ResponseType.ACCEPT) {
                service_manager.delete_service (target_service.id);
                destroy ();
            }
        }

        private void on_response (int response_id) {
            if (response_id != Gtk.ResponseType.OK) {
                destroy ();
                return;
            }

            string name = name_entry.text.strip ();
            string stack = stack_entry.text.strip ();
            string cmd = command_entry.text.strip ();
            string dir = dir_chooser.get_filename () ?? "";
            string url = url_entry.text.strip ();
            string type_id = type_combo.get_active_id () ?? "process";
            ServiceType s_type = ServiceType.from_string_id (type_id);
            string compose_f = compose_file_entry.text.strip ();
            string compose_s = compose_service_entry.text.strip ();
            string container_n = container_name_entry.text.strip ();

            if (name == "") {
                show_validation_error (tr ("Please specify at least the service name."));
                return;
            }

            if (s_type == ServiceType.PROCESS && cmd == "") {
                show_validation_error (tr ("Please specify at least the service name and command."));
                return;
            }

            if (s_type == ServiceType.COMPOSE && compose_f == "" && dir == "") {
                show_validation_error (tr ("Please specify at least the service name and compose file or directory."));
                return;
            }

            if (s_type == ServiceType.DOCKER && container_n == "" && cmd == "") {
                show_validation_error (tr ("Please specify at least the service name and container name or run command."));
                return;
            }

            if (is_edit_mode && target_service != null) {
                apply_service_updates (target_service, name, stack, cmd, dir, url, s_type, compose_f, compose_s, container_n);
                service_manager.update_service (target_service);
                destroy ();
                return;
            }

            save_new_service (name, stack, cmd, dir, url, s_type, compose_f, compose_s, container_n);
            destroy ();
        }

        private void show_validation_error (string message) {
            var error_diag = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.MODAL,
                Gtk.MessageType.ERROR,
                Gtk.ButtonsType.OK,
                "%s",
                message
            );
            error_diag.run ();
            error_diag.destroy ();
        }

        private void apply_service_updates (ServiceDefinition service, string name, string stack, string cmd, string dir, string url, ServiceType s_type, string compose_f, string compose_s, string container_n) {
            service.name = name;
            service.stack = stack;
            service.command = cmd;
            service.working_directory = dir;
            service.url = url;
            service.service_type = s_type;
            service.compose_file = compose_f;
            service.compose_service = compose_s;
            service.container_name = container_n;
            service.use_shell = shell_check.active;
            service.load_dotenv = dotenv_check.active;
            service.auto_restart = autorestart_check.active;
            service.autostart = autostart_check.active;
            service.variants = variants_list;
        }

        private void save_new_service (string name, string stack, string cmd, string dir, string url, ServiceType s_type, string compose_f, string compose_s, string container_n) {
            string new_id = "srv_" + GLib.Uuid.string_random ();
            var new_service = new ServiceDefinition (new_id, name, dir, cmd, url, stack, s_type, compose_f, compose_s, container_n);
            new_service.use_shell = shell_check.active;
            new_service.load_dotenv = dotenv_check.active;
            new_service.auto_restart = autorestart_check.active;
            new_service.autostart = autostart_check.active;
            new_service.variants = variants_list;

            service_manager.add_service (new_service);
        }
    }
}
