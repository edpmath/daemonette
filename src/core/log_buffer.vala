/* src/core/log_buffer.vala
 * In-memory circular ring buffer to retain the last N log lines of a service.
 */

namespace Daemonette {

    public class LogEntry : Object {
        public GLib.DateTime timestamp { get; private set; }
        public string text { get; private set; }
        public bool is_stderr { get; private set; }

        public LogEntry (string text, bool is_stderr = false) {
            this.timestamp = new GLib.DateTime.now_local ();
            this.text = text;
            this.is_stderr = is_stderr;
        }

        public string format_line () {
            return "[%02d:%02d:%02d] %s".printf (
                timestamp.get_hour (),
                timestamp.get_minute (),
                timestamp.get_second (),
                text
            );
        }
    }

    public class LogRingBuffer : Object {
        public int max_lines { get; set; default = 2000; }
        private Gee.LinkedList<LogEntry> entries;

        public signal void entry_added (LogEntry entry);
        public signal void cleared ();

        public LogRingBuffer (int max_lines = 2000) {
            this.max_lines = max_lines > 50 ? max_lines : 2000;
            this.entries = new Gee.LinkedList<LogEntry> ();
        }

        public void append (string line, bool is_stderr = false) {
            var entry = new LogEntry (line, is_stderr);
            entries.add (entry);

            // Keep buffer size bounded to max_lines
            while (entries.size > max_lines) {
                entries.remove_at (0);
            }

            entry_added (entry);
        }

        public Gee.List<LogEntry> get_entries () {
            var copy = new Gee.ArrayList<LogEntry> ();
            foreach (var e in entries) {
                copy.add (e);
            }
            return copy;
        }

        public void clear () {
            entries.clear ();
            cleared ();
        }

        public int size () {
            return entries.size;
        }
    }
}
