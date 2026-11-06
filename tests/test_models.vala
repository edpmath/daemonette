/* tests/test_models.vala
 * Unit tests for models: ServiceDefinition, ServiceVariant, ProcessMetrics, AppSettings.
 */

namespace Daemonette.Tests {

    public void register_models_tests () {
        GLib.Test.add_func ("/models/service_definition/defaults", test_service_definition_defaults);
        GLib.Test.add_func ("/models/service_definition/find_variant", test_find_variant);
        GLib.Test.add_func ("/models/service_definition/clone_as_new", test_clone_as_new);
        GLib.Test.add_func ("/models/process_metrics/formatting", test_process_metrics_formatting);
        GLib.Test.add_func ("/models/process_metrics/reset", test_process_metrics_reset);
        GLib.Test.add_func ("/models/service_status/display_string", test_service_status_display_string);
        GLib.Test.add_func ("/models/app_settings/defaults", test_app_settings_defaults);
    }

    private void test_service_definition_defaults () {
        var s = new ServiceDefinition ("srv_test", "API Server", "/var/www", "npm start", "http://localhost:3000");

        assert_true (s.id == "srv_test");
        assert_true (s.name == "API Server");
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
        var s = new ServiceDefinition ("srv_original", "Worker", "/worker", "python run.py");
        s.environment.set ("PORT", "8080");
        s.variants.add (new ServiceVariant ("var_orig", "Debug", "python run.py --debug"));

        var clone = s.clone_as_new ("Worker Copy");

        assert_true (clone.id != s.id);
        assert_true (clone.id.has_prefix ("srv_"));
        assert_true (clone.name == "Worker Copy");
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

    private void test_app_settings_defaults () {
        var settings = new AppSettings ();
        assert_true (settings.poll_interval_seconds == 2);
        assert_true (settings.max_log_lines == 2000);
        assert_true (settings.enable_notifications == true);
        assert_true (settings.autostart_on_login == false);
        assert_true (settings.language == "system");
    }
}
