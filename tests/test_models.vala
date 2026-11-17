/* tests/test_models.vala
 * Unit tests for models: ServiceDefinition, ServiceVariant, ProcessMetrics, AppSettings.
 */

namespace Daemonette.Tests {

    public void register_models_tests () {
        GLib.Test.add_func ("/models/service_definition/defaults", test_service_definition_defaults);
        GLib.Test.add_func ("/models/service_definition/stack_property", test_service_definition_stack_property);
        GLib.Test.add_func ("/models/service_definition/docker_properties", test_service_definition_docker_properties);
        GLib.Test.add_func ("/models/service_variant/editing_and_icons", test_service_variant_editing_and_icons);
        GLib.Test.add_func ("/models/docker_container_info/properties_and_formatting", test_docker_container_info);
        GLib.Test.add_func ("/models/service_definition/find_variant", test_find_variant);
        GLib.Test.add_func ("/models/service_definition/clone_as_new", test_clone_as_new);
        GLib.Test.add_func ("/models/service_type/enum_conversion", test_service_type_enum);
        GLib.Test.add_func ("/models/process_metrics/formatting", test_process_metrics_formatting);
        GLib.Test.add_func ("/models/process_metrics/reset", test_process_metrics_reset);
        GLib.Test.add_func ("/models/service_status/display_string", test_service_status_display_string);
        GLib.Test.add_func ("/models/stack_status/display_string", test_stack_status_display_string);
        GLib.Test.add_func ("/models/app_settings/defaults", test_app_settings_defaults);
    }

    private void test_service_definition_defaults () {
        var s = new ServiceDefinition ("srv_test", "API Server", "/var/www", "npm start", "http://localhost:3000");

        assert_true (s.id == "srv_test");
        assert_true (s.name == "API Server");
        assert_true (s.stack == "");
        assert_true (s.working_directory == "/var/www");
        assert_true (s.command == "npm start");
        assert_true (s.url == "http://localhost:3000");
        assert_true (s.use_shell == true);
        assert_true (s.load_dotenv == true);
        assert_true (s.auto_restart == false);
        assert_true (s.autostart == false);
        assert_true (s.status == ServiceStatus.STOPPED);
        assert_true (s.active_variant_id == null);
        assert_true (s.variants.size == 0);
        assert_true (s.environment.size == 0);
        assert_true (s.service_type == ServiceType.PROCESS);
        assert_true (s.compose_file == "");
        assert_true (s.compose_service == "");
        assert_true (s.container_name == "");
    }

    private void test_service_definition_docker_properties () {
        var s = new ServiceDefinition ("srv_compose", "Infra Stack", "/home/app", "", "", "MyStack", ServiceType.COMPOSE, "docker-compose.yml", "db", "app-db");
        assert_true (s.service_type == ServiceType.COMPOSE);
        assert_true (s.compose_file == "docker-compose.yml");
        assert_true (s.compose_service == "db");
        assert_true (s.container_name == "app-db");

        s.service_type = ServiceType.DOCKER;
        assert_true (s.service_type == ServiceType.DOCKER);
    }

    private void test_service_type_enum () {
        assert_true (ServiceType.PROCESS.to_string_id () == "process");
        assert_true (ServiceType.DOCKER.to_string_id () == "docker");
        assert_true (ServiceType.COMPOSE.to_string_id () == "compose");

        assert_true (ServiceType.from_string_id ("docker") == ServiceType.DOCKER);
        assert_true (ServiceType.from_string_id ("container") == ServiceType.DOCKER);
        assert_true (ServiceType.from_string_id ("compose") == ServiceType.COMPOSE);
        assert_true (ServiceType.from_string_id ("docker-compose") == ServiceType.COMPOSE);
        assert_true (ServiceType.from_string_id ("docker_compose") == ServiceType.COMPOSE);
        assert_true (ServiceType.from_string_id ("process") == ServiceType.PROCESS);
        assert_true (ServiceType.from_string_id ("native") == ServiceType.PROCESS);
        assert_true (ServiceType.from_string_id (null) == ServiceType.PROCESS);
        assert_true (ServiceType.from_string_id ("random_invalid") == ServiceType.PROCESS);

        assert_true (ServiceType.PROCESS.to_display_string () != "");
        assert_true (ServiceType.DOCKER.to_display_string () != "");
        assert_true (ServiceType.COMPOSE.to_display_string () != "");
    }

    private void test_service_definition_stack_property () {
        var s = new ServiceDefinition ("srv_pg", "Postgres", "/db", "pg_ctl start", "", "Ecommerce");
        assert_true (s.stack == "Ecommerce");
        s.stack = "Fullstack";
        assert_true (s.stack == "Fullstack");
    }

    private void test_service_variant_editing_and_icons () {
        var v = new ServiceVariant ("var_1", "Test Mode", "npm test");
        assert_true (v.icon == "⚡");
        assert_true (v.name == "Test Mode");
        assert_true (v.command == "npm test");

        // Test editing variant properties
        v.name = "Unit Testing";
        v.command = "npm run test:unit";
        v.icon = "🧪";
        v.url = "http://localhost:8080/coverage";
        v.use_shell = false;

        assert_true (v.name == "Unit Testing");
        assert_true (v.command == "npm run test:unit");
        assert_true (v.icon == "🧪");
        assert_true (v.url == "http://localhost:8080/coverage");
        assert_true (v.use_shell == false);

        // Test cloning retains edited properties including custom icon
        var clone = v.clone ();
        assert_true (clone.id == v.id);
        assert_true (clone.name == "Unit Testing");
        assert_true (clone.command == "npm run test:unit");
        assert_true (clone.icon == "🧪");
        assert_true (clone.url == "http://localhost:8080/coverage");
        assert_true (clone.use_shell == false);
    }

    private void test_docker_container_info () {
        var info = new DockerContainerInfo ("cnt_123", "postgres-db", "postgres", "postgres:16", "running", "Up 10 minutes", "healthy", "0.0.0.0:5432->5432/tcp");
        assert_true (info.id == "cnt_123");
        assert_true (info.name == "postgres-db");
        assert_true (info.service_name == "postgres");
        assert_true (info.image == "postgres:16");
        assert_true (info.state == "running");
        assert_true (info.status_text == "Up 10 minutes");
        assert_true (info.health == "healthy");
        assert_true (info.ports == "0.0.0.0:5432->5432/tcp");
        assert_true (info.exit_code == 0);
        assert_true (info.is_running () == true);
        assert_true (info.is_failed () == false);
        assert_true (info.get_status_bullet () == "🟢");
        assert_true (info.format_memory () == "0 KB");

        // Stopped container (exit code 0)
        var stopped = new DockerContainerInfo ("cnt_stop", "redis-cache", "redis", "redis:alpine", "exited", "Exited (0) 5m ago", "", "", 0);
        assert_true (stopped.is_running () == false);
        assert_true (stopped.is_failed () == false);
        assert_true (stopped.get_status_bullet () == "⚪");

        // Failed container (non-zero exit code)
        var failed_code = new DockerContainerInfo ("cnt_fail", "worker", "worker", "app:latest", "exited", "Exited (1) 2s ago", "", "", 1);
        assert_true (failed_code.is_running () == false);
        assert_true (failed_code.is_failed () == true);
        assert_true (failed_code.get_status_bullet () == "🔴");

        // Unhealthy container
        var unhealthy = new DockerContainerInfo ("cnt_unh", "api", "api", "app:latest", "running", "Up 1m", "unhealthy", "", 0);
        assert_true (unhealthy.is_failed () == true);
        assert_true (unhealthy.get_status_bullet () == "🔴");

        // Dead container
        var dead = new DockerContainerInfo ("cnt_dead", "crash", "crash", "app:latest", "dead", "Dead", "", "", 0);
        assert_true (dead.is_failed () == true);
        assert_true (dead.get_status_bullet () == "🔴");

        info.memory_bytes = 104857600ULL; // 100 MB
        info.cpu_percent = 1.5;
        string mem_mb = info.format_memory ();
        assert_true (mem_mb.contains ("100") && mem_mb.has_suffix ("MB"));

        info.memory_bytes = 2147483648ULL; // 2 GB
        string mem_gb = info.format_memory ();
        assert_true (mem_gb.contains ("2") && mem_gb.has_suffix ("GB"));

        var copy = info.clone ();
        assert_true (copy.id == info.id);
        assert_true (copy.name == info.name);
        assert_true (copy.memory_bytes == info.memory_bytes);
        assert_true (copy.cpu_percent == info.cpu_percent);
        assert_true (copy.exit_code == info.exit_code);
    }

    private void test_find_variant () {
        var s = new ServiceDefinition ("srv_test", "App", "/app", "start");
        var v1 = new ServiceVariant ("var_1", "Production", "start:prod");
        var v2 = new ServiceVariant ("var_2", "Development", "start:dev");

        s.variants.add (v1);
        s.variants.add (v2);

        var found1 = s.find_variant ("var_1");
        assert_true (found1 != null);
        assert_true (found1.name == "Production");

        var found2 = s.find_variant ("var_2");
        assert_true (found2 != null);
        assert_true (found2.name == "Development");

        var not_found = s.find_variant ("var_nonexistent");
        assert_true (not_found == null);
    }

    private void test_clone_as_new () {
        var s = new ServiceDefinition ("srv_original", "Worker", "/worker", "python run.py", "", "DataPipeline", ServiceType.COMPOSE, "compose.yml", "worker", "worker-cnt");
        s.environment.set ("PORT", "8080");
        s.variants.add (new ServiceVariant ("var_orig", "Debug", "python run.py --debug"));

        var clone = s.clone_as_new ("Worker Copy");

        assert_true (clone.id != s.id);
        assert_true (clone.id.has_prefix ("srv_"));
        assert_true (clone.name == "Worker Copy");
        assert_true (clone.stack == "DataPipeline");
        assert_true (clone.service_type == ServiceType.COMPOSE);
        assert_true (clone.compose_file == "compose.yml");
        assert_true (clone.compose_service == "worker");
        assert_true (clone.container_name == "worker-cnt");
        assert_true (clone.working_directory == s.working_directory);
        assert_true (clone.command == s.command);
        assert_true (clone.environment.get ("PORT") == "8080");
        assert_true (clone.variants.size == 1);

        var cloned_variant = clone.variants.get (0);
        assert_true (cloned_variant.id != "var_orig");
        assert_true (cloned_variant.name == "Debug");
        assert_true (cloned_variant.command == "python run.py --debug");
    }

    private void test_process_metrics_formatting () {
        var m = new ProcessMetrics ();

        // Memory formatting in KB (< 1 MB)
        m.memory_rss_bytes = 512 * 1024;
        assert_true (m.format_memory () == "512 KB");

        // Memory formatting in MB (locale agnostic)
        m.memory_rss_bytes = 16 * 1024 * 1024;
        string mem_mb = m.format_memory ();
        assert_true (mem_mb.contains ("16") && mem_mb.has_suffix ("MB"));

        // Memory formatting in GB (>= 1 GB)
        m.memory_rss_bytes = 2ULL * 1024ULL * 1024ULL * 1024ULL;
        string mem_gb = m.format_memory ();
        assert_true (mem_gb.contains ("2") && mem_gb.has_suffix ("GB"));

        // Null / zero uptime
        assert_true (m.format_uptime () == "0s");

        // Uptime with started_at set 45 seconds ago
        var now = new GLib.DateTime.now_local ();
        m.started_at = now.add_seconds (-45);
        string uptime_sec = m.format_uptime ();
        assert_true (uptime_sec.has_suffix ("s"));

        // Uptime greater than 1 hour (3700 seconds ago)
        m.started_at = now.add_seconds (-3700);
        string uptime_hour = m.format_uptime ();
        assert_true (uptime_hour.contains ("h"));
    }

    private void test_process_metrics_reset () {
        var m = new ProcessMetrics ();
        m.pid = 1234;
        m.pgid = 1234;
        m.cpu_percent = 25.5;
        m.memory_rss_bytes = 2048000;
        m.started_at = new GLib.DateTime.now_local ();

        m.reset ();

        assert_true (m.pid == 0);
        assert_true (m.pgid == 0);
        assert_true (m.cpu_percent == 0.0);
        assert_true (m.memory_rss_bytes == 0);
        assert_true (m.started_at == null);
    }

    private void test_service_status_display_string () {
        I18n.get_instance ().set_language_mode ("en");
        assert_true (ServiceStatus.STOPPED.to_display_string () == "Stopped");
        assert_true (ServiceStatus.STARTING.to_display_string () == "Starting...");
        assert_true (ServiceStatus.RUNNING.to_display_string () == "Running");
        assert_true (ServiceStatus.STOPPING.to_display_string () == "Stopping...");
        assert_true (ServiceStatus.FAILED.to_display_string () == "Error / Stopped");

        I18n.get_instance ().set_language_mode ("es");
        assert_true (ServiceStatus.STOPPED.to_display_string () == "Detenido");
        assert_true (ServiceStatus.STARTING.to_display_string () == "Iniciando...");
        assert_true (ServiceStatus.RUNNING.to_display_string () == "En ejecución");
        assert_true (ServiceStatus.STOPPING.to_display_string () == "Deteniendo...");
        assert_true (ServiceStatus.FAILED.to_display_string () == "Error / Detenido");

        I18n.get_instance ().set_language_mode ("system");
    }

    private void test_stack_status_display_string () {
        I18n.get_instance ().set_language_mode ("en");
        assert_true (StackStatus.STOPPED.to_display_string () == "Stopped");
        assert_true (StackStatus.STARTING.to_display_string () == "Starting...");
        assert_true (StackStatus.RUNNING.to_display_string () == "Running");
        assert_true (StackStatus.PARTIALLY_RUNNING.to_display_string () == "Partially Running");
        assert_true (StackStatus.STOPPING.to_display_string () == "Stopping...");
        assert_true (StackStatus.FAILED.to_display_string () == "Error / Stopped");

        I18n.get_instance ().set_language_mode ("es");
        assert_true (StackStatus.STOPPED.to_display_string () == "Detenido");
        assert_true (StackStatus.STARTING.to_display_string () == "Iniciando...");
        assert_true (StackStatus.RUNNING.to_display_string () == "En ejecución");
        assert_true (StackStatus.PARTIALLY_RUNNING.to_display_string () == "Parcialmente en ejecución");
        assert_true (StackStatus.STOPPING.to_display_string () == "Deteniendo...");
        assert_true (StackStatus.FAILED.to_display_string () == "Error / Detenido");

        I18n.get_instance ().set_language_mode ("system");
    }

    private void test_app_settings_defaults () {
        var settings = new AppSettings ();
        assert_true (settings.poll_interval_seconds == 2);
        assert_true (settings.max_log_lines == 2000);
        assert_true (settings.enable_notifications == true);
        assert_true (settings.autostart_on_login == false);
        assert_true (settings.language == "system");
    }
}
