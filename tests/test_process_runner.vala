/* tests/test_process_runner.vala
 * Unit tests for ProcessRunner, stream capturing, and process lifecycle.
 */

namespace Daemonette.Tests {

    public void register_process_runner_tests () {
        GLib.Test.add_func ("/core/process_runner/start_and_capture_output", test_start_and_capture_output);
        GLib.Test.add_func ("/core/process_runner/stop_terminates_pgid", test_stop_terminates_pgid);
    }

    private void test_start_and_capture_output () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_runner_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);
        var runner = new ProcessRunner (mgr);

        var service = new ServiceDefinition ("srv_echo", "Echo Service", tmp_dir, "echo HelloDaemonette");
        service.use_shell = true;
        mgr.add_service (service);

        var loop = new GLib.MainLoop ();
        bool output_found = false;

        runner.output_received.connect ((s_id, line, is_stderr) => {
            if (line.contains ("HelloDaemonette")) {
                output_found = true;
            }
        });

        runner.status_changed.connect ((s_id, status) => {
            if (s_id == service.id && status == ServiceStatus.STOPPED) {
                loop.quit ();
            }
        });

        // Safety timeout to prevent hangs
        GLib.Timeout.add_seconds (5, () => {
            loop.quit ();
            return GLib.Source.REMOVE;
        });

        bool started = runner.start_service (service);
        assert_true (started);

        loop.run ();

        assert_true (output_found);
        assert_true (service.status == ServiceStatus.STOPPED);

        var buffer = runner.get_log_buffer (service.id);
        assert_true (buffer.size () > 0);

        // Cleanup
        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_stop_terminates_pgid () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_kill_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);
        var runner = new ProcessRunner (mgr);

        var service = new ServiceDefinition ("srv_sleeper", "Sleeper Service", tmp_dir, "sleep 30");
        service.use_shell = true;
        mgr.add_service (service);

        var loop = new GLib.MainLoop ();

        bool started = runner.start_service (service);
        assert_true (started);
        assert_true (runner.is_running (service.id));

        int pid = runner.get_pid (service.id);
        int pgid = runner.get_pgid (service.id);
        assert_true (pid > 0);
        assert_true (pgid > 0);

        runner.status_changed.connect ((s_id, status) => {
            if (s_id == service.id && status == ServiceStatus.STOPPED) {
                loop.quit ();
            }
        });

        // Stop service after 200 ms
        GLib.Timeout.add (200, () => {
            runner.stop_service (service.id);
            return GLib.Source.REMOVE;
        });

        // Safety timeout
        GLib.Timeout.add_seconds (5, () => {
            loop.quit ();
            return GLib.Source.REMOVE;
        });

        loop.run ();

        assert_true (!runner.is_running (service.id));
        assert_true (service.status == ServiceStatus.STOPPED);

        // Cleanup
        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }
}
