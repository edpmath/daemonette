/* tests/test_log_buffer.vala
 * Unit tests for LogRingBuffer and LogEntry.
 */

namespace Daemonette.Tests {

    public void register_log_buffer_tests () {
        GLib.Test.add_func ("/core/log_buffer/entry_formatting", test_log_entry_formatting);
        GLib.Test.add_func ("/core/log_buffer/ring_capacity", test_ring_buffer_capacity);
        GLib.Test.add_func ("/core/log_buffer/overflow_eviction", test_ring_buffer_overflow_eviction);
        GLib.Test.add_func ("/core/log_buffer/clear", test_ring_buffer_clear);
        GLib.Test.add_func ("/core/log_buffer/signals", test_ring_buffer_signals);
    }

    private void test_log_entry_formatting () {
        var entry = new LogEntry ("Build finished successfully", false);
        assert_true (entry.text == "Build finished successfully");
        assert_true (entry.is_stderr == false);

        string formatted = entry.format_line ();
        assert_true (formatted.has_prefix ("["));
        assert_true (formatted.contains ("] Build finished successfully"));

        var err_entry = new LogEntry ("Error: syntax error", true);
        assert_true (err_entry.is_stderr == true);
    }

    private void test_ring_buffer_capacity () {
        var ring = new LogRingBuffer (100);
        assert_true (ring.max_lines == 100);
        assert_true (ring.size () == 0);

        ring.append ("Line 1");
        ring.append ("Line 2");
        assert_true (ring.size () == 2);

        var entries = ring.get_entries ();
        assert_true (entries.size == 2);
        assert_true (entries.get (0).text == "Line 1");
        assert_true (entries.get (1).text == "Line 2");
    }

    private void test_ring_buffer_overflow_eviction () {
        int max = 60;
        var ring = new LogRingBuffer (max);

        for (int i = 0; i < 100; i++) {
            ring.append ("Message %d".printf (i));
        }

        assert_true (ring.size () == max);

        var entries = ring.get_entries ();
        // First item must be message 40 (100 - 60 = 40)
        assert_true (entries.get (0).text == "Message 40");
        // Last item must be message 99
        assert_true (entries.get (max - 1).text == "Message 99");
    }

    private void test_ring_buffer_clear () {
        var ring = new LogRingBuffer (50);
        ring.append ("Test 1");
        ring.append ("Test 2");
        assert_true (ring.size () == 2);

        ring.clear ();
        assert_true (ring.size () == 0);
        assert_true (ring.get_entries ().size == 0);
    }

    private void test_ring_buffer_signals () {
        var ring = new LogRingBuffer (50);
        int added_count = 0;
        bool cleared_emitted = false;

        ring.entry_added.connect ((entry) => {
            added_count++;
        });

        ring.cleared.connect (() => {
            cleared_emitted = true;
        });

        ring.append ("Hello");
        ring.append ("World");
        assert_true (added_count == 2);

        ring.clear ();
        assert_true (cleared_emitted == true);
    }
}
