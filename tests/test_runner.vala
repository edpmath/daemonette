/* tests/test_runner.vala
 * Test runner entrypoint for Daemonette unit tests.
 */

namespace Daemonette.Tests {

    public static int main (string[] args) {
        // Initialize GLib test harness
        GLib.Test.init (ref args);

        // Initialize GTK without failing in headless CI environments with no display
        Gtk.init_check (ref args);

        // Register test suites
        register_models_tests ();
        register_i18n_tests ();
        register_log_buffer_tests ();
        register_service_manager_tests ();
        register_process_runner_tests ();
        register_ansi_parser_tests ();

        return GLib.Test.run ();
    }
}
