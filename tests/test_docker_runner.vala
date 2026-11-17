/* tests/test_docker_runner.vala
 * Unit tests for DockerRunner (command construction, compose file resolution, container targets).
 */

namespace Daemonette.Tests {

    public void register_docker_runner_tests () {
        GLib.Test.add_func ("/core/docker_runner/availability", test_docker_availability);
        GLib.Test.add_func ("/core/docker_runner/resolve_compose_file", test_resolve_compose_file);
        GLib.Test.add_func ("/core/docker_runner/build_compose_argv", test_build_compose_argv);
        GLib.Test.add_func ("/core/docker_runner/build_docker_argv", test_build_docker_argv);
        GLib.Test.add_func ("/core/docker_runner/build_docker_start_argv", test_build_docker_start_argv);
        GLib.Test.add_func ("/core/docker_runner/parse_byte_size_and_cpu", test_parse_byte_size_and_cpu);
        GLib.Test.add_func ("/core/docker_runner/parse_compose_ps_json", test_parse_compose_ps_json);
        GLib.Test.add_func ("/core/docker_runner/apply_stats_json", test_apply_stats_json);
        GLib.Test.add_func ("/core/docker_runner/line_matches_container_filter", test_line_matches_container_filter);
        GLib.Test.add_func ("/core/docker_runner/query_declared_compose_services", test_query_declared_compose_services);
        GLib.Test.add_func ("/core/docker_runner/live_compose_query", test_live_compose_query);
    }

    private void test_docker_availability () {
        bool available = DockerRunner.is_docker_available ();
        string? bin = DockerRunner.get_docker_binary ();
        if (available) {
            assert_true (bin != null && bin != "");
        } else {
            assert_true (bin == null);
        }
    }

    private void test_resolve_compose_file () {
        // 1. Absolute path
        var s_abs = new ServiceDefinition ("s1", "Abs", "/home/app", "", "", "", ServiceType.COMPOSE, "/etc/docker/compose.yml");
        assert_true (DockerRunner.resolve_compose_file (s_abs) == "/etc/docker/compose.yml");

        // 2. Relative path with working directory
        var s_rel = new ServiceDefinition ("s2", "Rel", "/home/app", "", "", "", ServiceType.COMPOSE, "deploy/docker-compose.prod.yml");
        assert_true (DockerRunner.resolve_compose_file (s_rel) == "/home/app/deploy/docker-compose.prod.yml");

        // 3. Auto-discovery in working directory
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_compose_XXXXXX");
        string compose_path = GLib.Path.build_filename (tmp_dir, "docker-compose.yml");
        try {
            GLib.FileUtils.set_contents (compose_path, "services:\n  test:\n    image: alpine\n");
        } catch (GLib.Error e) {
            GLib.error ("Failed to write test compose file: %s", e.message);
        }

        var s_auto = new ServiceDefinition ("s3", "Auto", tmp_dir, "", "", "", ServiceType.COMPOSE, "");
        string resolved = DockerRunner.resolve_compose_file (s_auto);
        assert_true (resolved == compose_path);

        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_build_compose_argv () {
        var s_all = new ServiceDefinition ("s_all", "Full Stack", "/app", "", "", "Stack1", ServiceType.COMPOSE, "/app/docker-compose.yml");
        string[] argv_up = DockerRunner.build_compose_argv (s_all, "up", { "-d" });

        assert_true (argv_up.length == 6);
        assert_true (argv_up[1] == "compose");
        assert_true (argv_up[2] == "-f");
        assert_true (argv_up[3] == "/app/docker-compose.yml");
        assert_true (argv_up[4] == "up");
        assert_true (argv_up[5] == "-d");

        // Targeted compose service
        var s_sub = new ServiceDefinition ("s_sub", "Web Service", "/app", "", "", "Stack1", ServiceType.COMPOSE, "/app/docker-compose.yml", "web");
        string[] argv_sub = DockerRunner.build_compose_argv (s_sub, "stop");

        assert_true (argv_sub.length == 6);
        assert_true (argv_sub[1] == "compose");
        assert_true (argv_sub[2] == "-f");
        assert_true (argv_sub[3] == "/app/docker-compose.yml");
        assert_true (argv_sub[4] == "stop");
        assert_true (argv_sub[5] == "web");

        // Logs
        string[] argv_logs = DockerRunner.build_compose_argv (s_sub, "logs", { "-f", "--tail", "50" });
        assert_true (argv_logs.length == 9);
        assert_true (argv_logs[4] == "logs");
        assert_true (argv_logs[5] == "-f");
        assert_true (argv_logs[6] == "--tail");
        assert_true (argv_logs[7] == "50");
        assert_true (argv_logs[8] == "web");
    }

    private void test_build_docker_argv () {
        var s_cnt = new ServiceDefinition ("s_db", "Postgres", "", "", "", "", ServiceType.DOCKER, "", "", "postgres-dev");
        string[]? argv = DockerRunner.build_docker_argv (s_cnt, "stop", { "-t", "5" });

        assert_true (argv != null);
        assert_true (argv.length == 5);
        assert_true (argv[1] == "stop");
        assert_true (argv[2] == "-t");
        assert_true (argv[3] == "5");
        assert_true (argv[4] == "postgres-dev");

        // Empty container name returns null
        var s_empty = new ServiceDefinition ("s_empty", "Empty", "", "", "", "", ServiceType.DOCKER, "", "", "");
        assert_true (DockerRunner.build_docker_argv (s_empty, "stop") == null);
    }

    private void test_build_docker_start_argv () {
        // 1. Container name only -> docker start <container>
        var s_named = new ServiceDefinition ("s_n", "Redis", "", "", "", "", ServiceType.DOCKER, "", "", "redis-cache");
        string[]? argv_named = DockerRunner.build_docker_start_argv (s_named);
        assert_true (argv_named != null);
        assert_true (argv_named.length == 3);
        assert_true (argv_named[1] == "start");
        assert_true (argv_named[2] == "redis-cache");

        // 2. Custom docker run command
        var s_run = new ServiceDefinition ("s_r", "Custom Nginx", "", "docker run --rm -p 8080:80 nginx:alpine", "", "", ServiceType.DOCKER, "", "", "nginx-tmp");
        string[]? argv_run = DockerRunner.build_docker_start_argv (s_run);
        assert_true (argv_run != null);
        assert_true (argv_run[0] == "docker");
        assert_true (argv_run[1] == "run");
        assert_true (argv_run[2] == "--rm");
        assert_true (argv_run[3] == "-p");
        assert_true (argv_run[4] == "8080:80");
        assert_true (argv_run[5] == "nginx:alpine");
    }

    private void test_parse_byte_size_and_cpu () {
        // Bytes and units
        assert_true (DockerRunner.parse_byte_size ("0B") == 0ULL);
        assert_true (DockerRunner.parse_byte_size ("512B") == 512ULL);
        assert_true (DockerRunner.parse_byte_size ("10KiB") == 10240ULL);
        assert_true (DockerRunner.parse_byte_size ("2MB") == 2ULL * 1024ULL * 1024ULL);
        assert_true (DockerRunner.parse_byte_size ("14.52MiB") > 14ULL * 1024ULL * 1024ULL);
        assert_true (DockerRunner.parse_byte_size ("1.5GiB") == (uint64)(1.5 * 1024.0 * 1024.0 * 1024.0));

        // Memory usage string: "37.62MiB / 7.569GiB"
        uint64 mem = DockerRunner.parse_mem_usage_string ("20.5MiB / 31.2GiB");
        assert_true (mem > 20ULL * 1024ULL * 1024ULL);

        // CPU percentage: "0.14%" -> 0.14
        double cpu = DockerRunner.parse_cpu_percentage ("0.14%");
        assert_true (cpu >= 0.13 && cpu <= 0.15);

        double cpu_zero = DockerRunner.parse_cpu_percentage ("0.00%");
        assert_true (cpu_zero == 0.0);
    }

    private void test_parse_compose_ps_json () {
        string sample_json = """
        {"ID":"79ece75e47cb","Name":"calendar-engine","Service":"calendar-engine","Image":"digicloud-calendar","State":"running","Status":"Up 8 minutes","Health":"healthy","Ports":"0.0.0.0:7004->7004/tcp"}
        {"ID":"ca3d378f4a70","Name":"postgres-db","Service":"postgres","Image":"postgres:18","State":"running","Status":"Up 8 minutes","Health":"healthy","Ports":"0.0.0.0:5432->5432/tcp"}
        {"ID":"f82f942987ed","Name":"failing-worker","Service":"worker","Image":"alpine","State":"exited","Status":"Exited (1) 2 seconds ago","ExitCode":1}
        {"ID":"113d5e5f857b","Name":"stopped-job","Service":"job","Image":"alpine","State":"exited","Status":"Exited (0) 10 minutes ago","ExitCode":0}
        """;

        var list = DockerRunner.parse_compose_ps_json (sample_json);
        assert_true (list.size == 4);

        var c1 = list.get (0);
        assert_true (c1.id == "79ece75e47cb");
        assert_true (c1.name == "calendar-engine");
        assert_true (c1.service_name == "calendar-engine");
        assert_true (c1.state == "running");
        assert_true (c1.health == "healthy");
        assert_true (c1.ports.contains ("7004"));
        assert_true (c1.is_running () == true);
        assert_true (c1.is_failed () == false);
        assert_true (c1.get_status_bullet () == "🟢");

        var c2 = list.get (1);
        assert_true (c2.id == "ca3d378f4a70");
        assert_true (c2.name == "postgres-db");
        assert_true (c2.service_name == "postgres");
        assert_true (c2.state == "running");

        var c3 = list.get (2);
        assert_true (c3.name == "failing-worker");
        assert_true (c3.state == "exited");
        assert_true (c3.exit_code == 1);
        assert_true (c3.is_failed () == true);
        assert_true (c3.get_status_bullet () == "🔴");

        var c4 = list.get (3);
        assert_true (c4.name == "stopped-job");
        assert_true (c4.state == "exited");
        assert_true (c4.exit_code == 0);
        assert_true (c4.is_failed () == false);
        assert_true (c4.get_status_bullet () == "⚪");

        // Test exit code extraction from status string
        assert_true (DockerRunner.extract_exit_code_from_status ("Exited (1) 2s ago") == 1);
        assert_true (DockerRunner.extract_exit_code_from_status ("Exited (137) 1m ago") == 137);
        assert_true (DockerRunner.extract_exit_code_from_status ("Up 5 minutes") == 0);
    }

    private void test_apply_stats_json () {
        var containers = new Gee.ArrayList<DockerContainerInfo> ();
        var c1 = new DockerContainerInfo ("79ece75e47cb", "calendar-engine", "calendar-engine", "digicloud-calendar", "running", "Up");
        var c2 = new DockerContainerInfo ("ca3d378f4a70", "postgres-db", "postgres", "postgres:18", "running", "Up");
        containers.add (c1);
        containers.add (c2);

        string sample_stats = """
        {"CPUPerc":"0.05%","Container":"79ece75e47cb6686e","ID":"79ece75e47cb","MemUsage":"22.5MiB / 31.27GiB","Name":"calendar-engine"}
        {"CPUPerc":"1.20%","Container":"ca3d378f4a708df03","ID":"ca3d378f4a70","MemUsage":"104.4MiB / 31.27GiB","Name":"postgres-db"}
        """;

        DockerRunner.apply_stats_json_to_containers (sample_stats, containers);

        assert_true (c1.memory_bytes > 22ULL * 1024ULL * 1024ULL);
        assert_true (c1.cpu_percent >= 0.04 && c1.cpu_percent <= 0.06);

        assert_true (c2.memory_bytes > 100ULL * 1024ULL * 1024ULL);
        assert_true (c2.cpu_percent >= 1.19 && c2.cpu_percent <= 1.21);
    }

    private void test_line_matches_container_filter () {
        // Universal match
        assert_true (LogViewerWindow.line_matches_container_filter ("postgres-db | ready", ""));
        assert_true (LogViewerWindow.line_matches_container_filter ("postgres-db | ready", "__all__"));

        // Matching container prefix
        assert_true (LogViewerWindow.line_matches_container_filter ("postgres-db | ready", "postgres-db"));
        assert_true (LogViewerWindow.line_matches_container_filter ("postgres-db-1 | ready", "postgres-db"));

        // Non-matching container prefix
        assert_true (!LogViewerWindow.line_matches_container_filter ("postgres-db | ready", "valkey-cache"));
        assert_true (!LogViewerWindow.line_matches_container_filter ("valkey-cache-1 | 1:M ready", "traefik"));

        // System headers mentioning target
        assert_true (LogViewerWindow.line_matches_container_filter ("--- [Restarting container: valkey-cache] ---", "valkey-cache"));

        // ANSI colored prefix from docker compose
        assert_true (LogViewerWindow.line_matches_container_filter ("\x1b[36mpostgres-db-1\x1b[0m | ready to accept connections", "postgres-db"));
        assert_true (!LogViewerWindow.line_matches_container_filter ("\x1b[36mpostgres-db-1\x1b[0m | ready to accept connections", "valkey-cache"));
    }

    private void test_query_declared_compose_services () {
        if (!DockerRunner.is_docker_available ()) return;

        string tmp_dir = TestUtils.make_test_directory ("daemonette_decl_XXXXXX");
        string compose_path = GLib.Path.build_filename (tmp_dir, "docker-compose.yml");
        try {
            GLib.FileUtils.set_contents (compose_path, "services:\n  alpha:\n    image: alpine\n  beta:\n    image: alpine\n");
        } catch (GLib.Error e) {
            GLib.error ("Failed to write test compose file: %s", e.message);
        }

        var s = new ServiceDefinition ("s_decl", "Declared Test", tmp_dir, "", "", "", ServiceType.COMPOSE, compose_path);
        var loop = new GLib.MainLoop ();
        bool queried = false;

        DockerRunner.query_compose_containers_async.begin (s, (obj, res) => {
            var containers = DockerRunner.query_compose_containers_async.end (res);
            assert_true (containers.size == 2);

            bool found_alpha = false;
            bool found_beta = false;
            foreach (var c in containers) {
                if (c.service_name == "alpha") {
                    found_alpha = true;
                    assert_true (c.state == "stopped");
                    assert_true (c.get_status_bullet () == "⚪");
                }
                if (c.service_name == "beta") {
                    found_beta = true;
                    assert_true (c.state == "stopped");
                    assert_true (c.get_status_bullet () == "⚪");
                }
            }
            assert_true (found_alpha && found_beta);
            queried = true;
            loop.quit ();
        });

        GLib.Timeout.add_seconds (3, () => {
            loop.quit ();
            return GLib.Source.REMOVE;
        });
        loop.run ();

        assert_true (queried);
        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_live_compose_query () {
        if (!DockerRunner.is_docker_available ()) return;

        string digicloud_compose = "/home/shared/Projects/digicloud/docker-compose.yml";
        if (!GLib.FileUtils.test (digicloud_compose, GLib.FileTest.EXISTS)) return;

        var s = new ServiceDefinition ("dc_test", "DC Backend", "/home/shared/Projects/digicloud", "", "", "DigiCloud", ServiceType.COMPOSE, digicloud_compose);
        var main_loop = new GLib.MainLoop ();
        bool queried = false;

        DockerRunner.query_compose_containers_async.begin (s, (obj, res) => {
            var containers = DockerRunner.query_compose_containers_async.end (res);
            assert_true (containers.size >= 1);

            DockerRunner.update_compose_metrics_async.begin (s, (obj2, res2) => {
                DockerRunner.update_compose_metrics_async.end (res2);
                assert_true (s.docker_containers.size >= 1);
                assert_true (s.metrics.memory_rss_bytes > 0);
                queried = true;
                main_loop.quit ();
            });
        });

        GLib.Timeout.add_seconds (3, () => {
            main_loop.quit ();
            return GLib.Source.REMOVE;
        });
        main_loop.run ();
        assert_true (queried);
    }
}
