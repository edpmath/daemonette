/* tests/test_utils.vala
 * Shared testing utilities for unit test suites.
 */

namespace Daemonette.Tests {

    public class TestUtils : Object {

        public static string make_test_directory (string prefix) {
            try {
                return GLib.DirUtils.make_tmp (prefix);
            } catch (GLib.Error e) {
                GLib.error ("No se pudo crear carpeta temporal de prueba '%s': %s", prefix, e.message);
            }
        }

        public static void remove_test_directory_and_contents (string dir_path) {
            try {
                var dir = GLib.Dir.open (dir_path);
                string? name = null;
                while ((name = dir.read_name ()) != null) {
                    string file_path = GLib.Path.build_filename (dir_path, name);
                    GLib.FileUtils.unlink (file_path);
                }
                GLib.DirUtils.remove (dir_path);
            } catch (GLib.Error e) {
                // Ignore errors if directory is already removed or cleanup fails
            }
        }
    }
}
