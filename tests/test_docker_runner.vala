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
}
