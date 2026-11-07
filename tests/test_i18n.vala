/* tests/test_i18n.vala
 * Unit tests for Daemonette internationalization (I18n).
 */

namespace Daemonette.Tests {

    public void register_i18n_tests () {
        GLib.Test.add_func ("/core/i18n/english_fallback", test_english_fallback);
        GLib.Test.add_func ("/core/i18n/spanish_translation", test_spanish_translation);
        GLib.Test.add_func ("/core/i18n/system_auto_detection", test_system_auto_detection);
        GLib.Test.add_func ("/core/i18n/language_switching_signal", test_language_switching_signal);
    }

    private void test_english_fallback () {
        var i18n = I18n.get_instance ();
        i18n.set_language_mode ("en");

        assert_true (i18n.get_active_language () == I18n.Language.EN);
        assert_true (!i18n.is_spanish ());
        assert_true (tr ("Running") == "Running");
        assert_true (tr ("Stopped") == "Stopped");
        assert_true (tr ("Nonexistent string key") == "Nonexistent string key");
    }

    private void test_spanish_translation () {
        var i18n = I18n.get_instance ();
        i18n.set_language_mode ("es");

        assert_true (i18n.get_active_language () == I18n.Language.ES);
        assert_true (i18n.is_spanish ());
        assert_true (tr ("Running") == "En ejecución");
        assert_true (tr ("Stopped") == "Detenido");
        assert_true (tr ("Save") == "Guardar");
        assert_true (tr ("Cancel") == "Cancelar");
        assert_true (tr ("Copy") == "Copiar");
        assert_true (tr ("➕ Register new service...") == "➕ Registrar nuevo servicio...");
    }

    private void test_system_auto_detection () {
        var i18n = I18n.get_instance ();

        string? orig_lc_all = GLib.Environment.get_variable ("LC_ALL");
        string? orig_lc_messages = GLib.Environment.get_variable ("LC_MESSAGES");
        string? orig_lang = GLib.Environment.get_variable ("LANG");

        // Force Spanish
        GLib.Environment.set_variable ("LC_ALL", "es_ES.UTF-8", true);
        assert_true (i18n.detect_system_language () == I18n.Language.ES);

        // Force English
        GLib.Environment.set_variable ("LC_ALL", "en_US.UTF-8", true);
        assert_true (i18n.detect_system_language () == I18n.Language.EN);

        // Force German / Other (should default to English)
        GLib.Environment.set_variable ("LC_ALL", "de_DE.UTF-8", true);
        assert_true (i18n.detect_system_language () == I18n.Language.EN);

        // Restore
        if (orig_lc_all != null) {
            GLib.Environment.set_variable ("LC_ALL", orig_lc_all, true);
        } else {
            GLib.Environment.unset_variable ("LC_ALL");
        }
        if (orig_lc_messages != null) {
            GLib.Environment.set_variable ("LC_MESSAGES", orig_lc_messages, true);
        }
        if (orig_lang != null) {
            GLib.Environment.set_variable ("LANG", orig_lang, true);
        }
    }

    private void test_language_switching_signal () {
        var i18n = I18n.get_instance ();
        i18n.set_language_mode ("en");

        bool signal_received = false;
        I18n.Language received_lang = I18n.Language.EN;

        ulong handler_id = i18n.language_changed.connect ((new_lang) => {
            signal_received = true;
            received_lang = new_lang;
        });

        i18n.set_language_mode ("es");
        assert_true (signal_received);
        assert_true (received_lang == I18n.Language.ES);

        signal_received = false;
        i18n.set_language_mode ("en");
        assert_true (signal_received);
        assert_true (received_lang == I18n.Language.EN);

        i18n.disconnect (handler_id);

        // Reset to system
        i18n.set_language_mode ("system");
    }
}
