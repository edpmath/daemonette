/* src/core/terminal_launcher.vala
 * Detection and launching of modern terminal emulators in the service working directory.
 */

namespace Daemonette {

    public class TerminalLauncher : Object {

        public static bool open_terminal (string working_directory) {
            string target_dir = resolve_target_dir (working_directory);

            if (try_spawn_custom_terminal (target_dir)) {
                return true;
            }

            if (try_spawn_candidate_terminal (target_dir)) {
                return true;
            }

            GLib.warning ("No se encontró ningún emulador de terminal compatible instalado.");
            return false;
        }

        private static string resolve_target_dir (string working_directory) {
            if (working_directory.strip () != "") {
                return working_directory;
            }
            return GLib.Environment.get_home_dir ();
        }

        private static bool try_spawn_custom_terminal (string target_dir) {
            unowned string? custom_term = GLib.Environment.get_variable ("TERMINAL");
            if (custom_term == null || custom_term.strip () == "") {
                return false;
            }
            return try_spawn_terminal (custom_term, target_dir);
        }

        private static bool try_spawn_candidate_terminal (string target_dir) {
            string[] terminal_candidates = {
                "ptyxis",
                "gnome-terminal",
                "mate-terminal",
                "kgx",
                "kitty",
                "alacritty",
                "x-terminal-emulator",
                "xterm"
            };

            foreach (var term in terminal_candidates) {
                if (GLib.Environment.find_program_in_path (term) == null) {
                    continue;
                }
                if (try_spawn_terminal (term, target_dir)) {
                    return true;
                }
            }

            return false;
        }

        private static bool try_spawn_terminal (string binary, string working_dir) {
            string[] argv = build_terminal_argv (binary, working_dir);

            try {
                GLib.Process.spawn_async (
                    working_dir,
                    argv,
                    null,
                    GLib.SpawnFlags.SEARCH_PATH,
                    null,
                    null
                );
                return true;
            } catch (GLib.SpawnError e) {
                GLib.warning ("Error al lanzar terminal '%s': %s", binary, e.message);
                return false;
            }
        }

        private static string[] build_terminal_argv (string binary, string working_dir) {
            if (binary == "kitty") {
                return new string[] { binary, "--directory", working_dir };
            }

            if (supports_working_directory_option (binary)) {
                return new string[] { binary, "--working-directory", working_dir };
            }

            return new string[] { binary };
        }

        private static bool supports_working_directory_option (string binary) {
            return binary == "ptyxis" ||
                   binary == "gnome-terminal" ||
                   binary == "mate-terminal" ||
                   binary == "kgx" ||
                   binary == "alacritty";
        }
    }
}
