/* src/core/i18n.vala
 * Internationalization (i18n) manager for Daemonette.
 * Supports automatic system locale detection (English primary, Spanish if OS is in Spanish)
 * and persistent manual configuration.
 */

namespace Daemonette {

    public class I18n : Object {
        private static I18n? instance = null;

        public enum Language {
            EN,
            ES
        }

        private Language current_language = Language.EN;
        private string current_mode = "system"; // "system", "en", "es"
        private Gee.HashMap<string, string> es_dict;

        public signal void language_changed (Language new_language);

        public static I18n get_instance () {
            if (instance == null) {
                instance = new I18n ();
            }
            return instance;
        }

        private I18n () {
            es_dict = new Gee.HashMap<string, string> ();
            init_spanish_dictionary ();
            set_language_mode ("system");
        }

        public string get_language_mode () {
            return current_mode;
        }

        public Language get_active_language () {
            return current_language;
        }

        public bool is_spanish () {
            return current_language == Language.ES;
        }

        public void set_language_mode (string mode) {
            bool mode_changed = (this.current_mode != mode);
            this.current_mode = mode;
            Language target_lang;

            if (mode == "es") {
                target_lang = Language.ES;
            } else if (mode == "en") {
                target_lang = Language.EN;
            } else {
                target_lang = detect_system_language ();
            }

            if (target_lang != current_language || mode_changed) {
                current_language = target_lang;
                language_changed (current_language);
            }
        }

        public Language detect_system_language () {
            string? lang = GLib.Environment.get_variable ("LC_ALL");
            if (lang == null || lang == "") {
                lang = GLib.Environment.get_variable ("LC_MESSAGES");
            }
            if (lang == null || lang == "") {
                lang = GLib.Environment.get_variable ("LANG");
            }

            if (lang != null) {
                string down = lang.down ();
                if (down.has_prefix ("es") || down.contains ("es_") || down.contains ("es-")) {
                    return Language.ES;
                }
            }

            return Language.EN;
        }

        public string translate (string msgid) {
            if (current_language == Language.ES) {
                if (es_dict.has_key (msgid)) {
                    return es_dict.get (msgid);
                }
            }
            return msgid;
        }

        private void init_spanish_dictionary () {
            // Service Status
            es_dict.set ("Starting...", "Iniciando...");
            es_dict.set ("Running", "En ejecución");
            es_dict.set ("Stopping...", "Deteniendo...");
            es_dict.set ("Error / Stopped", "Error / Detenido");
            es_dict.set ("Error / Crashed", "Error / Caído");
            es_dict.set ("Stopped", "Detenido");
            es_dict.set ("Inactive", "Inactivo");

            // Tray Indicator Menu
            es_dict.set ("[●] %d active | Total RAM: %s", "[●] %d activo(s) | RAM total: %s");
            es_dict.set ("[○] 0 active (Idle)", "[○] 0 activos (Inactivo)");
            es_dict.set ("Daemonette - Service error", "Daemonette - Error en servicio");
            es_dict.set ("(No registered services)", "(Sin servicios registrados)");
            es_dict.set ("➕ Register new service...", "➕ Registrar nuevo servicio...");
            es_dict.set ("🛑 Stop all services", "🛑 Detener todos los servicios");
            es_dict.set ("📋 Global Log Viewer...", "📋 Visor global de logs...");
            es_dict.set ("Start Daemonette on boot", "Iniciar Daemonette con el sistema");
            es_dict.set ("🚪 Quit Daemonette", "🚪 Salir de Daemonette");

            es_dict.set ("(Starting...)", "(Iniciando...)");
            es_dict.set ("(Stopping...)", "(Deteniendo...)");
            es_dict.set ("(Error)", "(Error)");
            es_dict.set ("(Stopped)", "(Detenido)");

            es_dict.set ("⏹ Stop", "⏹ Detener");
            es_dict.set ("🔄 Restart", "🔄 Reiniciar");
            es_dict.set ("🌐 Open in Browser (%s)", "🌐 Abrir en navegador (%s)");
            es_dict.set ("▶ Start Default (%s)", "▶ Iniciar por defecto (%s)");
            es_dict.set ("⚡ Variant: %s", "⚡ Variante: %s");
            es_dict.set ("💻 Open Terminal in Folder", "💻 Abrir terminal en carpeta");
            es_dict.set ("📋 View Logs & Resources...", "📋 Ver logs y recursos...");
            es_dict.set ("📋 View Previous Logs...", "📋 Ver logs anteriores...");
            es_dict.set ("⚙️ Configure Service...", "⚙️ Configurar servicio...");

            // Language Submenu
            es_dict.set ("🌐 Language", "🌐 Idioma");
            es_dict.set ("System Default (Auto)", "Predeterminado del sistema (Auto)");

            // Log Viewer Window
            es_dict.set ("Daemonette - Log Viewer & Resource Monitor", "Daemonette - Visor de Logs y Monitor de Recursos");
            es_dict.set ("Services", "Servicios");
            es_dict.set ("Select a service", "Selecciona un servicio");
            es_dict.set ("No service selected", "Ningún servicio seleccionado");
            es_dict.set ("RAM: %s | CPU: %.1f%% | Uptime: %s", "RAM: %s | CPU: %.1f%% | Activo: %s");
            es_dict.set ("RAM: 0 KB | CPU: 0.0% | Uptime: 0s", "RAM: 0 KB | CPU: 0.0% | Activo: 0s");
            es_dict.set ("▶ Start", "▶ Iniciar");
            es_dict.set ("Restart service", "Reiniciar servicio");
            es_dict.set ("Open in browser", "Abrir en navegador");
            es_dict.set ("Open terminal in folder", "Abrir terminal en carpeta");
            es_dict.set ("Clear", "Limpiar");
            es_dict.set ("Clear log display", "Limpiar visualización de logs");
            es_dict.set ("Copy", "Copiar");
            es_dict.set ("Copy logs to clipboard", "Copiar logs al portapapeles");
            es_dict.set ("⬇ Auto-scroll", "⬇ Auto-scroll");

            // Service Editor Dialog
            es_dict.set ("Register New Service", "Registrar Nuevo Servicio");
            es_dict.set ("Configure Service", "Configurar Servicio");
            es_dict.set ("Service Name:", "Nombre del servicio:");
            es_dict.set ("e.g. Quasar Frontend, Backend API...", "ej. Frontend Web, Backend API...");
            es_dict.set ("Working Directory:", "Directorio de trabajo:");
            es_dict.set ("Select project directory", "Seleccionar directorio del proyecto");
            es_dict.set ("Main Command:", "Comando principal:");
            es_dict.set ("e.g. quasar dev, npm run dev, python main.py", "ej. npm run dev, fastapi dev, python main.py");
            es_dict.set ("Local URL (Optional):", "URL local (Opcional):");
            es_dict.set ("e.g. http://localhost:9000", "ej. http://localhost:8000");
            es_dict.set ("Execution Options", "Opciones de Ejecución");
            es_dict.set ("Run via shell (/bin/sh - supports pipes and variables)", "Ejecutar vía shell (/bin/sh - soporta pipes y variables)");
            es_dict.set ("Automatically load local .env variables", "Cargar variables locales de .env automáticamente");
            es_dict.set ("Automatically restart if process crashes", "Reiniciar automáticamente si el proceso falla");
            es_dict.set ("Automatically start service when opening Daemonette", "Iniciar servicio automáticamente al abrir Daemonette");
            es_dict.set ("General", "General");
            es_dict.set ("Variants", "Variantes");
            es_dict.set ("Command variants (e.g. test mode, watchers, etc.):", "Variantes de comando (ej. modo pruebas, watchers, etc.):");
            es_dict.set ("➕ Add Variant", "➕ Agregar Variante");
            es_dict.set ("No variants added.", "Sin variantes agregadas.");
            es_dict.set ("Delete this variant", "Eliminar esta variante");
            es_dict.set ("Cancel", "Cancelar");
            es_dict.set ("Save", "Guardar");
            es_dict.set ("Duplicate", "Duplicar");
            es_dict.set ("Create a copy of this service", "Crear una copia de este servicio");
            es_dict.set ("Delete", "Eliminar");
            es_dict.set ("Add Variant", "Agregar Variante");
            es_dict.set ("Add", "Agregar");
            es_dict.set ("Variant name:", "Nombre de la variante:");
            es_dict.set ("Name (e.g. E2E Mode)", "Nombre (ej. Modo E2E)");
            es_dict.set ("Command:", "Comando:");
            es_dict.set ("Alternative command", "Comando alternativo");
            es_dict.set ("Local URL (optional):", "URL local (opcional):");
            es_dict.set ("Specific URL (optional)", "URL específica (opcional)");
            es_dict.set ("Run via shell (/bin/sh)", "Ejecutar vía shell (/bin/sh)");
            es_dict.set ("Are you sure you want to delete service '%s'?", "¿Estás seguro de que deseas eliminar el servicio '%s'?");
            es_dict.set ("This action cannot be undone.", "Esta acción no se puede deshacer.");
            es_dict.set ("Delete Permanently", "Eliminar permanentemente");
            es_dict.set ("Please specify at least the service name and command.", "Por favor especifica al menos el nombre y el comando del servicio.");

            // Notifications
            es_dict.set ("Service Crashed: %s", "Servicio caído: %s");
            es_dict.set ("Process exited with code %d", "El proceso terminó con código %d");

            // Duplication
            es_dict.set ("Copy", "Copia");
        }
    }

    public static string tr (string text) {
        return I18n.get_instance ().translate (text);
    }
}
