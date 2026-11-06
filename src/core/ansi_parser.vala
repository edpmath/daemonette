/* src/core/ansi_parser.vala
 * Lightweight ANSI escape sequence parser for formatting and coloring Gtk.TextBuffer.
 */

namespace Daemonette {

    public class AnsiParser : Object {

        public static void setup_tags (Gtk.TextBuffer buffer) {
            var tag_table = buffer.tag_table;

            if (tag_table.lookup ("ansi_bold") == null) {
                buffer.create_tag ("ansi_bold", "weight", Pango.Weight.BOLD);
            }
            if (tag_table.lookup ("ansi_dim") == null) {
                buffer.create_tag ("ansi_dim", "foreground", "#888888");
            }

            // Standard terminal colors (modern high-contrast palette for dark backgrounds)
            create_color_tag (buffer, "ansi_fg_30", "#5c6370"); // Black / Dark Grey
            create_color_tag (buffer, "ansi_fg_31", "#e06c75"); // Red
            create_color_tag (buffer, "ansi_fg_32", "#98c379"); // Green
            create_color_tag (buffer, "ansi_fg_33", "#e5c07b"); // Yellow
            create_color_tag (buffer, "ansi_fg_34", "#61afef"); // Blue
            create_color_tag (buffer, "ansi_fg_35", "#c678dd"); // Magenta
            create_color_tag (buffer, "ansi_fg_36", "#56b6c2"); // Cyan
            create_color_tag (buffer, "ansi_fg_37", "#abb2bf"); // White

            // Bright / high-intensity colors
            create_color_tag (buffer, "ansi_fg_90", "#7f848e");
            create_color_tag (buffer, "ansi_fg_91", "#ff6c6b");
            create_color_tag (buffer, "ansi_fg_92", "#98be65");
            create_color_tag (buffer, "ansi_fg_93", "#ecbe7b");
            create_color_tag (buffer, "ansi_fg_94", "#51afef");
            create_color_tag (buffer, "ansi_fg_95", "#a9a1e1");
            create_color_tag (buffer, "ansi_fg_96", "#46d9ff");
            create_color_tag (buffer, "ansi_fg_97", "#bbc2cf");
        }

        private static void create_color_tag (Gtk.TextBuffer buffer, string name, string hex_color) {
            if (buffer.tag_table.lookup (name) != null) {
                return;
            }
            buffer.create_tag (name, "foreground", hex_color);
        }

        /**
         * Inserts a line of text, interpreting ANSI escape codes and applying TextTags.
         */
        public static void insert_formatted (Gtk.TextBuffer buffer, string raw_text) {
            Gtk.TextIter end_iter;
            buffer.get_end_iter (out end_iter);

            string current_color_tag = "";
            bool is_bold = false;

            int i = 0;
            int len = raw_text.length;

            while (i < len) {
                int esc_idx = raw_text.index_of ("\x1b[", i);
                if (esc_idx < 0) {
                    insert_with_style (buffer, ref end_iter, raw_text.substring (i), current_color_tag, is_bold);
                    break;
                }

                if (esc_idx > i) {
                    insert_with_style (buffer, ref end_iter, raw_text.substring (i, esc_idx - i), current_color_tag, is_bold);
                }

                // Parse ANSI sequence: \x1b[ ... m
                int m_idx = raw_text.index_of_char ('m', esc_idx);
                if (m_idx <= esc_idx) {
                    // Malformed sequence, skip marker
                    i = esc_idx + 2;
                    continue;
                }

                string params_str = raw_text.substring (esc_idx + 2, m_idx - (esc_idx + 2));
                parse_and_apply_codes (params_str, ref current_color_tag, ref is_bold);
                i = m_idx + 1;
            }

            buffer.get_end_iter (out end_iter);
            buffer.insert (ref end_iter, "\n", -1);
        }

        private static void parse_and_apply_codes (string params_str, ref string current_color_tag, ref bool is_bold) {
            string[] codes = params_str.split (";");
            foreach (var code in codes) {
                int code_num = int.parse (code.strip ());
                apply_ansi_code (code_num, ref current_color_tag, ref is_bold);
            }
        }

        private static void apply_ansi_code (int code_num, ref string current_color_tag, ref bool is_bold) {
            if (code_num == 0) {
                current_color_tag = "";
                is_bold = false;
                return;
            }

            if (code_num == 1) {
                is_bold = true;
                return;
            }

            if (code_num == 22) {
                is_bold = false;
                return;
            }

            if (code_num == 39) {
                current_color_tag = "";
                return;
            }

            if (is_valid_color_code (code_num)) {
                current_color_tag = "ansi_fg_%d".printf (code_num);
                return;
            }
        }

        private static bool is_valid_color_code (int code_num) {
            if (code_num >= 30 && code_num <= 37) {
                return true;
            }
            return code_num >= 90 && code_num <= 97;
        }

        private static void insert_with_style (Gtk.TextBuffer buffer, ref Gtk.TextIter iter, string text, string color_tag, bool is_bold) {
            if (text == "") return;

            Gtk.TextMark start_mark = buffer.create_mark (null, iter, true);
            buffer.insert (ref iter, text, -1);

            Gtk.TextIter start_iter;
            buffer.get_iter_at_mark (out start_iter, start_mark);

            if (color_tag != "") {
                buffer.apply_tag_by_name (color_tag, start_iter, iter);
            }
            if (is_bold) {
                buffer.apply_tag_by_name ("ansi_bold", start_iter, iter);
            }

            buffer.delete_mark (start_mark);
        }
    }
}
