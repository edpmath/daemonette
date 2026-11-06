/* tests/test_ansi_parser.vala
 * Unit tests for AnsiParser and Pango/Gtk.TextBuffer text tags.
 */

namespace Daemonette.Tests {

    public void register_ansi_parser_tests () {
        GLib.Test.add_func ("/core/ansi_parser/setup_tags", test_ansi_parser_setup_tags);
        GLib.Test.add_func ("/core/ansi_parser/insert_formatted", test_ansi_parser_insert_formatted);
        GLib.Test.add_func ("/core/ansi_parser/malformed_escape", test_ansi_parser_malformed_escape);
    }

    private void test_ansi_parser_setup_tags () {
        var buffer = new Gtk.TextBuffer (null);
        AnsiParser.setup_tags (buffer);

        var table = buffer.tag_table;
        assert_true (table.lookup ("ansi_bold") != null);
        assert_true (table.lookup ("ansi_dim") != null);
        assert_true (table.lookup ("ansi_fg_31") != null);
        assert_true (table.lookup ("ansi_fg_32") != null);
        assert_true (table.lookup ("ansi_fg_91") != null);
    }

    private void test_ansi_parser_insert_formatted () {
        var buffer = new Gtk.TextBuffer (null);
        AnsiParser.setup_tags (buffer);

        string raw = "\x1b[1mReady\x1b[0m \x1b[32mSuccess\x1b[39m";
        AnsiParser.insert_formatted (buffer, raw);

        string text = buffer.text;
        // Raw escape sequence should have been stripped from visible text
        assert_true (!text.contains ("\x1b["));
        assert_true (text.contains ("Ready Success"));
        assert_true (text.has_suffix ("\n"));
    }

    private void test_ansi_parser_malformed_escape () {
        var buffer = new Gtk.TextBuffer (null);
        AnsiParser.setup_tags (buffer);

        // Malformed or incomplete sequence missing 'm' terminator
        string malformed = "Prefix \x1b[31 Broken sequence without ending";
        AnsiParser.insert_formatted (buffer, malformed);

        string text = buffer.text;
        assert_true (text.contains ("Prefix"));
        assert_true (text.contains ("Broken sequence"));
    }
}
