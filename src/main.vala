/* src/main.vala
 * Main Daemonette application (Gtk.Application).
 */

namespace Daemonette {

    public class DaemonetteApp : Gtk.Application {
        private ServiceManager service_manager;
        private ProcessRunner process_runner;
        private ResourceMonitor resource_monitor;
        private TrayIndicator tray_indicator;
        private LogViewerWindow? log_window = null;

        public DaemonetteApp () {
            Object (
                application_id: "io.github.edpmath.Daemonette",
                flags: GLib.ApplicationFlags.FLAGS_NONE
            );
        }

        protected override void activate () {
            // Keep the application running in the background even if no windows are open
            hold ();

            service_manager = new ServiceManager ();
            service_manager.load_from_json ();
            I18n.get_instance ().set_language_mode (service_manager.settings.language);

            process_runner = new ProcessRunner (service_manager);
            resource_monitor = new ResourceMonitor (service_manager, process_runner);
            tray_indicator = new TrayIndicator (service_manager, process_runner, resource_monitor);

            // Connect tray indicator signals
            tray_indicator.request_new_service.connect (() => {
                var dialog = new ServiceEditorDialog (null, service_manager, null);
                dialog.show ();
            });

            tray_indicator.request_edit_service.connect ((service_id) => {
                var dialog = new ServiceEditorDialog (null, service_manager, service_id);
                dialog.show ();
            });

            tray_indicator.request_open_logs.connect ((service_id) => {
                show_log_viewer (service_id);
            });

            tray_indicator.request_quit.connect (() => {
                process_runner.stop_all ();
                // Brief timeout to allow graceful process termination
                GLib.Timeout.add (300, () => {
                    release ();
                    this.quit ();
                    return GLib.Source.REMOVE;
                });
            });

            autostart_configured_services ();

            stdout.printf ("Daemonette started in system tray (AppIndicator active).\n");
        }

        private void autostart_configured_services () {
            foreach (var s in service_manager.services) {
                if (s.autostart) {
                    process_runner.start_service (s, null);
                }
            }
        }

        private void show_log_viewer (string? service_id) {
            if (log_window != null) {
                present_existing_log_viewer (service_id);
                return;
            }

            create_and_show_log_viewer (service_id);
        }

        private void present_existing_log_viewer (string? service_id) {
            if (service_id != null) {
                log_window.select_service (service_id);
            }
            log_window.present ();
        }

        private void create_and_show_log_viewer (string? service_id) {
            log_window = new LogViewerWindow (service_manager, process_runner, resource_monitor, service_id);
            add_window (log_window);
            log_window.window_closed.connect (() => {
                log_window = null;
            });
            log_window.show_all ();
        }
    }

    public static int main (string[] args) {
        if ("--version" in args) {
            stdout.printf ("Daemonette 1.0.0\n");            return 0;
        }

        if ("--test" in args) {
            stdout.printf ("Daemonette selftest OK\n");
            return 0;
        }

        var app = new DaemonetteApp ();
        return app.run (args);
    }
}
