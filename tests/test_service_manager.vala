/* tests/test_service_manager.vala
 * Unit tests for ServiceManager, .env parsing, and JSON serialization.
 */

namespace Daemonette.Tests {

    public void register_service_manager_tests () {
        GLib.Test.add_func ("/core/service_manager/parse_dotenv", test_parse_dotenv);
        GLib.Test.add_func ("/core/service_manager/crud_and_json_roundtrip", test_crud_and_json_roundtrip);
        GLib.Test.add_func ("/core/service_manager/duplicate_service", test_duplicate_service);
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

        var v1 = new ServiceVariant ("var_worker", "Worker Mode", "npm run worker");
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
        original.variants.add (new ServiceVariant ("var_test", "Test DB", "docker compose -f test.yml up"));
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

        I18n.get_instance ().set_language_mode ("system");

        // Cleanup
        TestUtils.remove_test_directory_and_contents (tmp_dir);
    }
}
