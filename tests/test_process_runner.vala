/* tests/test_process_runner.vala
 * Unit tests for ProcessRunner, stream capturing, and process lifecycle.
 */

namespace Daemonette.Tests {

    public void register_process_runner_tests () {
        GLib.Test.add_func ("/core/process_runner/start_and_capture_output", test_start_and_capture_output);
        GLib.Test.add_func ("/core/process_runner/stop_terminates_pgid", test_stop_terminates_pgid);
        GLib.Test.add_func ("/core/process_runner/shell_and_path_resolution", test_shell_and_path_resolution);
        GLib.Test.add_func ("/core/process_runner/project_local_bins", test_project_local_bins);
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

    private void test_shell_and_path_resolution () {
        string shell = ProcessRunner.resolve_user_shell ();
        assert_true (shell != "");
        assert_true (GLib.FileUtils.test (shell, GLib.FileTest.IS_EXECUTABLE));

        string merged = ProcessRunner.merge_paths ({ "/bin:/usr/bin", "/usr/bin:/usr/local/bin", "/bin" });
        assert_true (merged == "/bin:/usr/bin:/usr/local/bin");

        string cached_path = ProcessRunner.get_cached_user_shell_path ();
        assert_true (cached_path != "");
    }

    private void test_project_local_bins () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_local_bins_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);
        var runner = new ProcessRunner (mgr);

        // Create mock node_modules/.bin and .venv/bin
        string node_bin_dir = GLib.Path.build_filename (tmp_dir, "node_modules", ".bin");
        string venv_bin_dir = GLib.Path.build_filename (tmp_dir, ".venv", "bin");
        GLib.DirUtils.create_with_parents (node_bin_dir, 0755);
        GLib.DirUtils.create_with_parents (venv_bin_dir, 0755);

        var service = new ServiceDefinition ("srv_test_bins", "Test Bins", tmp_dir, "quasar dev");
        service.use_shell = true;
        mgr.add_service (service);

        string[] envp = runner.build_effective_environment (service);
        string? path = GLib.Environ.get_variable (envp, "PATH");
        assert_true (path != null);
        assert_true (path.contains (node_bin_dir));
        assert_true (path.contains (venv_bin_dir));

        // Ensure node_bin_dir precedes standard directories
        int node_idx = path.index_of (node_bin_dir);
        int venv_idx = path.index_of (venv_bin_dir);
        int usr_bin_idx = path.index_of ("/usr/bin");
        assert_true (node_idx < usr_bin_idx);
        assert_true (venv_idx < usr_bin_idx);

        // Verify argv uses resolved user shell instead of hardcoded /bin/sh
        string[]? argv = runner.resolve_command_argv (service.command, service.use_shell, service.name);
        assert_true (argv != null);
        assert_true (argv.length == 3);
        assert_true (argv[0] == ProcessRunner.resolve_user_shell ());
        assert_true (argv[1] == "-c");
        assert_true (argv[2] == "quasar dev");

        // Cleanup
        TestUtils.remove_test_directory_and_contents (node_bin_dir);
        TestUtils.remove_test_directory_and_contents (venv_bin_dir);
        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }
}
