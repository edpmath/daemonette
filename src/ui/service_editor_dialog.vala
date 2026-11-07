/* src/ui/service_editor_dialog.vala
 * Modal GTK3 dialog to add, edit, duplicate, and delete services and their variants.
 */

namespace Daemonette {

    public class ServiceEditorDialog : Gtk.Dialog {
        private ServiceManager service_manager;
        private ServiceDefinition? target_service;
        private bool is_edit_mode;

        // Main form widgets
        private Gtk.Entry name_entry;
        private Gtk.FileChooserButton dir_chooser;
        private Gtk.Entry command_entry;
        private Gtk.Entry url_entry;
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

            set_default_size (560, 620);
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

            // Name
            grid.attach (new Gtk.Label (tr ("Service Name:")) { xalign = 0 }, 0, 0, 1, 1);
            name_entry = new Gtk.Entry ();
            name_entry.placeholder_text = tr ("e.g. Quasar Frontend, Backend API...");
            name_entry.hexpand = true;
            grid.attach (name_entry, 1, 0, 1, 1);

            // Working directory
            grid.attach (new Gtk.Label (tr ("Working Directory:")) { xalign = 0 }, 0, 1, 1, 1);
            dir_chooser = new Gtk.FileChooserButton (tr ("Select project directory"), Gtk.FileChooserAction.SELECT_FOLDER);
            dir_chooser.hexpand = true;
            grid.attach (dir_chooser, 1, 1, 1, 1);

            // Command
            grid.attach (new Gtk.Label (tr ("Main Command:")) { xalign = 0 }, 0, 2, 1, 1);
            command_entry = new Gtk.Entry ();
            command_entry.placeholder_text = tr ("e.g. quasar dev, npm run dev, python main.py");
            command_entry.hexpand = true;
            grid.attach (command_entry, 1, 2, 1, 1);

            // URL
            grid.attach (new Gtk.Label (tr ("Local URL (Optional):")) { xalign = 0 }, 0, 3, 1, 1);
            url_entry = new Gtk.Entry ();
            url_entry.placeholder_text = tr ("e.g. http://localhost:9000");
            url_entry.hexpand = true;
            grid.attach (url_entry, 1, 3, 1, 1);

            general_box.pack_start (grid, false, false, 0);

            // Execution options and toggles
            var options_frame = new Gtk.Frame (tr ("Execution Options"));
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
            show_all ();
        }

        private void load_data () {
            if (!is_edit_mode || target_service == null) {
                dir_chooser.set_current_folder (GLib.Environment.get_home_dir ());
                return;
            }

            name_entry.text = target_service.name;
            if (target_service.working_directory.strip () != "") {
                dir_chooser.set_filename (target_service.working_directory);
            }
            command_entry.text = target_service.command;
            url_entry.text = target_service.url;
            shell_check.active = target_service.use_shell;
            dotenv_check.active = target_service.load_dotenv;
            autorestart_check.active = target_service.auto_restart;
            autostart_check.active = target_service.autostart;

            variants_list.clear ();
            foreach (var v in target_service.variants) {
                variants_list.add (v.clone ());
            }
            refresh_variants_list ();
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
                var title_lbl = new Gtk.Label ("⚡ %s".printf (v.name)) { xalign = 0 };
                var cmd_lbl = new Gtk.Label (v.command) { xalign = 0 };
                cmd_lbl.get_style_context ().add_class ("dim-label");
                info_box.pack_start (title_lbl, false, false, 0);
                info_box.pack_start (cmd_lbl, false, false, 0);

                box.pack_start (info_box, true, true, 0);

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
            var diag = new Gtk.Dialog.with_buttons (
                tr ("Add Variant"),
                this,
                Gtk.DialogFlags.MODAL | Gtk.DialogFlags.DESTROY_WITH_PARENT,
                tr ("Cancel"), Gtk.ResponseType.CANCEL,
                tr ("Add"), Gtk.ResponseType.OK,
                null
            );

            var area = diag.get_content_area ();
            area.spacing = 8;
            area.border_width = 12;

            var v_name = new Gtk.Entry () { placeholder_text = tr ("Name (e.g. E2E Mode)") };
            var v_cmd = new Gtk.Entry () { placeholder_text = tr ("Alternative command") };
            var v_url = new Gtk.Entry () { placeholder_text = tr ("Specific URL (optional)") };
            var v_shell = new Gtk.CheckButton.with_label (tr ("Run via shell ($SHELL)")) { active = true };

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
                if (name != "" && cmd != "") {
                    string var_id = "var_" + GLib.Uuid.string_random ();
                    var new_var = new ServiceVariant (var_id, name, cmd, v_url.text.strip (), v_shell.active);
                    variants_list.add (new_var);
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
            string cmd = command_entry.text.strip ();
            string dir = dir_chooser.get_filename () ?? "";
            string url = url_entry.text.strip ();

            if (name == "" || cmd == "") {
                show_validation_error ();
                return;
            }

            if (is_edit_mode && target_service != null) {
                apply_service_updates (target_service, name, cmd, dir, url);
                service_manager.update_service (target_service);
                destroy ();
                return;
            }

            save_new_service (name, cmd, dir, url);
            destroy ();
        }

        private void show_validation_error () {
            var error_diag = new Gtk.MessageDialog (
                this,
                Gtk.DialogFlags.MODAL,
                Gtk.MessageType.ERROR,
                Gtk.ButtonsType.OK,
                tr ("Please specify at least the service name and command.")
            );
            error_diag.run ();
            error_diag.destroy ();
        }

        private void apply_service_updates (ServiceDefinition service, string name, string cmd, string dir, string url) {
            service.name = name;
            service.command = cmd;
            service.working_directory = dir;
            service.url = url;
            service.use_shell = shell_check.active;
            service.load_dotenv = dotenv_check.active;
            service.auto_restart = autorestart_check.active;
            service.autostart = autostart_check.active;
            service.variants = variants_list;
        }

        private void save_new_service (string name, string cmd, string dir, string url) {
            string new_id = "srv_" + GLib.Uuid.string_random ();
            var new_service = new ServiceDefinition (new_id, name, dir, cmd, url);
            new_service.use_shell = shell_check.active;
            new_service.load_dotenv = dotenv_check.active;
            new_service.auto_restart = autorestart_check.active;
            new_service.autostart = autostart_check.active;
            new_service.variants = variants_list;

            service_manager.add_service (new_service);
        }
    }
}
