/* src/models/app_settings.vala
 * Global configuration settings for the Daemonette application.
 */

namespace Daemonette {

    public class AppSettings : Object {
        public int poll_interval_seconds { get; set; default = 2; }
        public int max_log_lines { get; set; default = 2000; }
        public bool enable_notifications { get; set; default = true; }
        public bool autostart_on_login { get; set; default = false; }
        public string language { get; set; default = "system"; } // "system", "en", "es"

        public AppSettings () {
        }
    }
}
