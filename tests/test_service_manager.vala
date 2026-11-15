/* tests/test_service_manager.vala
 * Unit tests for ServiceManager, .env parsing, and JSON serialization.
 */

namespace Daemonette.Tests {

    public void register_service_manager_tests () {
        GLib.Test.add_func ("/core/service_manager/parse_dotenv", test_parse_dotenv);
        GLib.Test.add_func ("/core/service_manager/crud_and_json_roundtrip", test_crud_and_json_roundtrip);
        GLib.Test.add_func ("/core/service_manager/duplicate_service", test_duplicate_service);
        GLib.Test.add_func ("/core/service_manager/stacks_query_and_persistence", test_stacks_query_and_persistence);
        GLib.Test.add_func ("/core/service_manager/legacy_group_deserialization", test_legacy_group_deserialization);
        GLib.Test.add_func ("/core/service_manager/docker_and_compose_persistence", test_docker_and_compose_persistence);
        GLib.Test.add_func ("/ui/service_editor_dialog/instantiation", test_service_editor_dialog_instantiation);
    }

    private void test_parse_dotenv () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_dotenv_XXXXXX");
        string env_file_path = GLib.Path.build_filename (tmp_dir, ".env");

        string env_content = """
# Test comment
PORT=8000
NODE_ENV="development"
API_SECRET='secret_token_123'
EMPTY_VAL=

# Another section
DATABASE_URL=postgres://localhost:5432/test
""";

        try {
            GLib.FileUtils.set_contents (env_file_path, env_content);
        } catch (GLib.Error e) {
            GLib.error ("No se pudo escribir .env de prueba: %s", e.message);
        }

        var mgr = new ServiceManager (tmp_dir);
        var parsed = mgr.parse_dotenv (tmp_dir);

        assert_true (parsed.get ("PORT") == "8000");
        assert_true (parsed.get ("NODE_ENV") == "development");
        assert_true (parsed.get ("API_SECRET") == "secret_token_123");
        assert_true (parsed.get ("EMPTY_VAL") == "");
        assert_true (parsed.get ("DATABASE_URL") == "postgres://localhost:5432/test");
        assert_true (!parsed.has_key ("# Test comment"));

        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_crud_and_json_roundtrip () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_crud_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);

        // 1. Add service
        var s1 = new ServiceDefinition ("srv_api", "Backend API", "/api", "npm run dev", "http://localhost:4000");
        s1.use_shell = true;
        s1.load_dotenv = true;
        s1.auto_restart = true;
        s1.autostart = true;
        s1.environment.set ("PORT", "4000");

        var v1 = new ServiceVariant ("var_worker", "Worker Mode", "npm run worker", "http://localhost:4001", true, "🧪");
        s1.variants.add (v1);

        mgr.add_service (s1);
        assert_true (mgr.services.size == 1);
        assert_true (mgr.get_service ("srv_api") != null);

        // 2. Modify service
        s1.name = "Backend API Updated";
        bool updated = mgr.update_service (s1);
        assert_true (updated);
        assert_true (mgr.get_service ("srv_api").name == "Backend API Updated");

        // 3. Create a new manager instance over the same directory to verify persistence on disk
        var mgr_reloaded = new ServiceManager (tmp_dir);
        bool loaded = mgr_reloaded.load_from_json ();
        assert_true (loaded);
        assert_true (mgr_reloaded.services.size == 1);

        var restored_service = mgr_reloaded.get_service ("srv_api");
        assert_true (restored_service != null);
        assert_true (restored_service.name == "Backend API Updated");
        assert_true (restored_service.command == "npm run dev");
        assert_true (restored_service.url == "http://localhost:4000");
        assert_true (restored_service.auto_restart == true);
        assert_true (restored_service.autostart == true);
        assert_true (restored_service.environment.get ("PORT") == "4000");
        assert_true (restored_service.variants.size == 1);
        assert_true (restored_service.variants.get (0).name == "Worker Mode");
        assert_true (restored_service.variants.get (0).url == "http://localhost:4001");
        assert_true (restored_service.variants.get (0).icon == "🧪");

        // 4. Delete service
        bool deleted = mgr_reloaded.delete_service ("srv_api");
        assert_true (deleted);
        assert_true (mgr_reloaded.services.size == 0);
        assert_true (mgr_reloaded.get_service ("srv_api") == null);

        // Cleanup
        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_duplicate_service () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_dup_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);

        var original = new ServiceDefinition ("srv_orig", "Database Microservice", "/db", "docker compose up");
        original.environment.set ("DB_PORT", "5432");
        original.variants.add (new ServiceVariant ("var_test", "Test DB", "docker compose -f test.yml up", "", true, "🗄️"));
        mgr.add_service (original);

        I18n.get_instance ().set_language_mode ("en");
        var duplicated = mgr.duplicate_service ("srv_orig");
        assert_true (duplicated != null);
        assert_true (mgr.services.size == 2);
        assert_true (duplicated.id != "srv_orig");
        assert_true (duplicated.name == "Database Microservice (Copy)");
        assert_true (duplicated.command == "docker compose up");
        assert_true (duplicated.environment.get ("DB_PORT") == "5432");
        assert_true (duplicated.variants.size == 1);
        assert_true (duplicated.variants.get (0).id != "var_test");
        assert_true (duplicated.variants.get (0).icon == "🗄️");

        I18n.get_instance ().set_language_mode ("system");

        // Cleanup
        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_stacks_query_and_persistence () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_stacks_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);

        var s_pg = new ServiceDefinition ("srv_pg", "Postgres", "/db", "pg_ctl start", "", "Ecommerce");
        var s_api = new ServiceDefinition ("srv_api", "API", "/api", "npm run dev", "http://localhost:3000", "Ecommerce");
        var s_web = new ServiceDefinition ("srv_web", "Frontend", "/web", "npm start", "http://localhost:8080", "Ecommerce");
        var s_auth = new ServiceDefinition ("srv_auth", "Auth Svc", "/auth", "cargo run", "", "Platform");
        var s_tool = new ServiceDefinition ("srv_tool", "Global Watcher", "/tools", "watch.sh");

        mgr.add_service (s_pg);
        mgr.add_service (s_api);
        mgr.add_service (s_web);
        mgr.add_service (s_auth);
        mgr.add_service (s_tool);

        // Verify get_stacks
        var stacks = mgr.get_stacks ();
        assert_true (stacks.size == 2);
        assert_true (stacks.contains ("Ecommerce"));
        assert_true (stacks.contains ("Platform"));

        // Verify get_services_by_stack
        var ecom_services = mgr.get_services_by_stack ("Ecommerce");
        assert_true (ecom_services.size == 3);
        assert_true (ecom_services.get (0).name == "Postgres");
        assert_true (ecom_services.get (1).name == "API");
        assert_true (ecom_services.get (2).name == "Frontend");

        var plat_services = mgr.get_services_by_stack ("Platform");
        assert_true (plat_services.size == 1);
        assert_true (plat_services.get (0).name == "Auth Svc");

        // Verify get_ungrouped_services
        var ungrouped = mgr.get_ungrouped_services ();
        assert_true (ungrouped.size == 1);
        assert_true (ungrouped.get (0).name == "Global Watcher");

        // Reload from disk to verify JSON persistence of stack
        var mgr_reload = new ServiceManager (tmp_dir);
        bool loaded = mgr_reload.load_from_json ();
        assert_true (loaded);
        assert_true (mgr_reload.get_stacks ().size == 2);
        assert_true (mgr_reload.get_services_by_stack ("Ecommerce").size == 3);
        assert_true (mgr_reload.get_services_by_stack ("Platform").size == 1);
        assert_true (mgr_reload.get_ungrouped_services ().size == 1);

        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_legacy_group_deserialization () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_legacy_XXXXXX");
        string json_path = GLib.Path.build_filename (tmp_dir, "services.json");

        string json_content = """{
  "version": 1,
  "services": [
    {
      "id": "srv_legacy",
      "name": "Legacy DB",
      "working_directory": "/tmp",
      "command": "true",
      "group": "LegacyStack"
    }
  ]
}""";

        try {
            GLib.FileUtils.set_contents (json_path, json_content);
        } catch (GLib.Error e) {
            GLib.error ("No se pudo escribir JSON de prueba: %s", e.message);
        }

        var mgr = new ServiceManager (tmp_dir);
        bool loaded = mgr.load_from_json ();
        assert_true (loaded);
        assert_true (mgr.services.size == 1);

        var s = mgr.get_service ("srv_legacy");
        assert_true (s != null);
        assert_true (s.stack == "LegacyStack");
        assert_true (s.service_type == ServiceType.PROCESS);
        assert_true (mgr.get_stacks ().size == 1);
        assert_true (mgr.get_stacks ().get (0) == "LegacyStack");

        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_docker_and_compose_persistence () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_docker_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);

        // 1. Compose service
        var s_compose = new ServiceDefinition (
            "srv_compose_db",
            "Database & Cache",
            "/home/app",
            "",
            "http://localhost:8080",
            "FullstackApp",
            ServiceType.COMPOSE,
            "docker-compose.yml",
            "db",
            ""
        );

        // 2. Standalone Docker container
        var s_docker = new ServiceDefinition (
            "srv_docker_worker",
            "Background Worker",
            "",
            "docker run -d worker:latest",
            "",
            "FullstackApp",
            ServiceType.DOCKER,
            "",
            "",
            "app-worker-prod"
        );

        // 3. Native process in same stack
        var s_proc = new ServiceDefinition (
            "srv_proc_web",
            "Frontend Web",
            "/home/app/frontend",
            "npm run dev",
            "http://localhost:5173",
            "FullstackApp",
            ServiceType.PROCESS
        );

        mgr.add_service (s_compose);
        mgr.add_service (s_docker);
        mgr.add_service (s_proc);

        assert_true (mgr.services.size == 3);
        assert_true (mgr.get_services_by_stack ("FullstackApp").size == 3);

        // 4. Reload from disk
        var mgr_reload = new ServiceManager (tmp_dir);
        bool loaded = mgr_reload.load_from_json ();
        assert_true (loaded);
        assert_true (mgr_reload.services.size == 3);

        var loaded_compose = mgr_reload.get_service ("srv_compose_db");
        assert_true (loaded_compose != null);
        assert_true (loaded_compose.service_type == ServiceType.COMPOSE);
        assert_true (loaded_compose.compose_file == "docker-compose.yml");
        assert_true (loaded_compose.compose_service == "db");
        assert_true (loaded_compose.stack == "FullstackApp");

        var loaded_docker = mgr_reload.get_service ("srv_docker_worker");
        assert_true (loaded_docker != null);
        assert_true (loaded_docker.service_type == ServiceType.DOCKER);
        assert_true (loaded_docker.container_name == "app-worker-prod");
        assert_true (loaded_docker.stack == "FullstackApp");

        var loaded_proc = mgr_reload.get_service ("srv_proc_web");
        assert_true (loaded_proc != null);
        assert_true (loaded_proc.service_type == ServiceType.PROCESS);
        assert_true (loaded_proc.stack == "FullstackApp");

        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }

    private void test_service_editor_dialog_instantiation () {
        string tmp_dir = TestUtils.make_test_directory ("daemonette_test_diag_XXXXXX");
        var mgr = new ServiceManager (tmp_dir);

        // Test creating new service dialog
        var new_diag = new ServiceEditorDialog (null, mgr, null);
        assert_true (new_diag != null);
        new_diag.destroy ();

        // Test editing a Compose service
        var s_compose = new ServiceDefinition ("s_c", "Compose Svc", tmp_dir, "", "", "Stack", ServiceType.COMPOSE, "docker-compose.yml", "api");
        mgr.add_service (s_compose);

        var edit_diag = new ServiceEditorDialog (null, mgr, "s_c");
        assert_true (edit_diag != null);
        edit_diag.destroy ();

        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }
}
