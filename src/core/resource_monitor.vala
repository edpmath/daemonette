/* src/core/resource_monitor.vala
 * Efficient resource monitor (CPU and RAM) that queries /proc directly,
 * aggregating total consumption across all processes in the same PGID.
 */

namespace Daemonette {

    public class ResourceMonitor : Object {
        private ServiceManager service_manager;
        private ProcessRunner process_runner;
        private uint timeout_id = 0;
        private bool is_active_view = false;

        // CPU tracking per PGID: pgid -> previous ticks
        private Gee.HashMap<int, uint64?> prev_cpu_ticks;
        private Gee.HashMap<int, int64?> prev_sample_times;

        public signal void metrics_updated ();

        public ResourceMonitor (ServiceManager service_manager, ProcessRunner process_runner) {
            this.service_manager = service_manager;
            this.process_runner = process_runner;
            this.prev_cpu_ticks = new Gee.HashMap<int, uint64?> ();
            this.prev_sample_times = new Gee.HashMap<int, int64?> ();

            // Promptly poll after a service transitions to RUNNING
            process_runner.status_changed.connect ((s_id, status) => {
                if (status == ServiceStatus.RUNNING) {
                    GLib.Timeout.add (400, () => {
                        poll_all_services ();
                        return GLib.Source.REMOVE;
                    });
                }
            });

            start_monitoring ();
        }

        public void set_high_frequency_mode (bool high_freq) {
            this.is_active_view = high_freq;
            restart_timer ();
        }

        private void start_monitoring () {
            restart_timer ();
        }

        private void restart_timer () {
            if (timeout_id != 0) {
                GLib.Source.remove (timeout_id);
                timeout_id = 0;
            }

            // If log viewer window is open: 1.5s; if closed: 6s
            uint interval_ms = is_active_view ? 1500 : 6000;

            timeout_id = GLib.Timeout.add (interval_ms, () => {
                poll_all_services ();
                return GLib.Source.CONTINUE;
            });
        }

        public void poll_all_services () {
            bool has_running = false;

            foreach (var service in service_manager.services) {
                if (service.status == ServiceStatus.RUNNING) {
                    has_running = true;
                    update_running_service_metrics (service);
                    continue;
                }

                reset_stopped_service_metrics (service);
            }

            if (has_running) {
                metrics_updated ();
            }
        }

        private void update_running_service_metrics (ServiceDefinition service) {
            int pgid = process_runner.get_pgid (service.id);
            if (pgid <= 0) {
                return;
            }

            uint64 total_ticks = 0;
            uint64 rss_bytes = read_pgid_metrics (pgid, out total_ticks);
            service.metrics.memory_rss_bytes = rss_bytes;

            calculate_cpu_percent (service, pgid, total_ticks);
        }

        private void calculate_cpu_percent (ServiceDefinition service, int pgid, uint64 total_ticks) {
            int64 now_us = GLib.get_monotonic_time ();

            if (!prev_cpu_ticks.has_key (pgid) || !prev_sample_times.has_key (pgid)) {
                prev_cpu_ticks.set (pgid, total_ticks);
                prev_sample_times.set (pgid, now_us);
                return;
            }

            uint64 diff_ticks = total_ticks - prev_cpu_ticks.get (pgid);
            int64 diff_time_us = now_us - prev_sample_times.get (pgid);

            if (diff_time_us > 0) {
                // sysconf(_SC_CLK_TCK) is typically 100 ticks/sec on Linux
                double ticks_per_sec = (double) diff_ticks / ((double) diff_time_us / 1000000.0);
                double cpu_pct = (ticks_per_sec / 100.0) * 100.0;
                service.metrics.cpu_percent = cpu_pct > 0.0 ? cpu_pct : 0.0;
            }

            prev_cpu_ticks.set (pgid, total_ticks);
            prev_sample_times.set (pgid, now_us);
        }

        private void reset_stopped_service_metrics (ServiceDefinition service) {
            if (service.metrics.pid <= 0) {
                return;
            }

            prev_cpu_ticks.unset (service.metrics.pgid);
            prev_sample_times.unset (service.metrics.pgid);
            service.metrics.reset ();
        }

        private uint64 read_pgid_metrics (int target_pgid, out uint64 total_cpu_ticks) {
            uint64 total_kb = 0;
            total_cpu_ticks = 0;

            try {
                var proc_dir = GLib.Dir.open ("/proc");
                string? name = null;
                while ((name = proc_dir.read_name ()) != null) {
                    int pid = int.parse (name);
                    if (pid <= 0) continue;

                    uint64 proc_ticks = 0;
                    uint64 proc_kb = read_single_proc_metrics (pid, target_pgid, out proc_ticks);
                    total_cpu_ticks += proc_ticks;
                    total_kb += proc_kb;
                }
            } catch (GLib.Error e) {
                // Process may have exited during traversal
            }

            return total_kb * 1024;
        }

        private uint64 read_single_proc_metrics (int pid, int target_pgid, out uint64 ticks) {
            ticks = 0;
            string stat_path = "/proc/%d/stat".printf (pid);
            string? stat_content = null;

            if (!safe_read_file (stat_path, out stat_content)) {
                return 0;
            }

            int proc_pgid = 0;
            if (!parse_stat_pgid_and_ticks (stat_content, out proc_pgid, out ticks)) {
                return 0;
            }

            if (proc_pgid != target_pgid) {
                ticks = 0;
                return 0;
            }

            return read_process_rss_kb (pid);
        }

        private static bool safe_read_file (string path, out string? content) {
            content = null;
            try {
                return GLib.FileUtils.get_contents (path, out content);
            } catch (GLib.Error e) {
                return false;
            }
        }

        private bool parse_stat_pgid_and_ticks (string stat_content, out int pgid, out uint64 ticks) {
            pgid = 0;
            ticks = 0;

            int rparen = stat_content.last_index_of_char (')');
            if (rparen <= 0 || rparen + 2 >= stat_content.length) {
                return false;
            }

            string rest = stat_content.substring (rparen + 2);
            string[] parts = rest.split (" ");

            // parts[0] = state, parts[1] = ppid, parts[2] = pgrp (pgid)
            if (parts.length <= 13) {
                return false;
            }

            pgid = int.parse (parts[2]);
            uint64 utime = (uint64) uint64.parse (parts[11]);
            uint64 stime = (uint64) uint64.parse (parts[12]);
            ticks = utime + stime;
            return true;
        }

        private uint64 read_process_rss_kb (int pid) {
            string status_path = "/proc/%d/status".printf (pid);
            string? status_content = null;
            if (!safe_read_file (status_path, out status_content)) {
                return 0;
            }
            return parse_vm_rss_kb (status_content);
        }

        private uint64 parse_vm_rss_kb (string status_content) {
            int idx = status_content.index_of ("VmRSS:");
            if (idx < 0) return 0;
            int end_line = status_content.index_of_char ('\n', idx);
            if (end_line < 0) end_line = status_content.length;
            string line = status_content.substring (idx, end_line - idx);

            string[] tokens = line.split (" ");
            for (int i = 1; i < tokens.length; i++) {
                string t = tokens[i].strip ();
                if (t != "" && t != "kB") {
                    return (uint64) uint64.parse (t);
                }
            }
            return 0;
        }
    }
}
