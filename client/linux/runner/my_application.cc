#include "my_application.h"

#include <glib-unix.h>

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)


// Set the window and taskbar icon from the bundled asset.
//
// GTK normally resolves an icon by name out of the desktop icon theme, which
// only works once a .desktop file and icons are installed system wide. This app
// is run straight out of its build directory as often as not, so the icon is
// loaded from the bundle beside the executable instead. That way alt-tab and
// the taskbar show the tiger whether or not anything has been installed.
//
// Several sizes are offered rather than one, so the compositor picks the right
// one instead of scaling a 512 down to 24 and turning the clock face to mush.
static void set_window_icon(GtkWindow* window) {
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe == nullptr) return;
  g_autofree gchar* dir = g_path_get_dirname(exe);

  static const char* sizes[] = {"48", "64", "96", "128", "192", "256", "512"};
  GList* icons = nullptr;

  for (size_t i = 0; i < G_N_ELEMENTS(sizes); i++) {
    g_autofree gchar* name = g_strdup_printf("app-icon-%s.png", sizes[i]);
    g_autofree gchar* path = g_build_filename(
        dir, "data", "flutter_assets", "assets", "icons", name, nullptr);
    GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file(path, nullptr);
    if (pixbuf != nullptr) icons = g_list_prepend(icons, pixbuf);
  }

  if (icons == nullptr) return;
  gtk_window_set_icon_list(window, icons);
  g_list_free_full(icons, g_object_unref);
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.

// Remember the window size across launches.
//
// The app opened at 1280x720 every single time, whatever you had resized it
// to, which is one of the clearest tells that something is a build directory
// rather than an installed app.
//
// Size and maximised state only, deliberately no position: this runs under
// Wayland, where a client cannot place its own window, and asking would either
// be ignored or fight the compositor.
//
// Stored as a two line key file in the XDG config dir, written on close. If it
// is missing or unreadable the defaults apply, so a first run and a corrupt
// file behave the same way.
// The window whose size we persist. Single window app, so a static is enough,
// and the signal handlers below have no other way to reach it.
static GtkWindow* g_tracked_window = nullptr;

// The last size the window had while it was not maximised.
//
// gtk_window_get_size on a maximised window reports the screen, so storing
// that and restoring it later would leave an unmaximised window filling the
// display. Tracking it as it changes is the only way to know the size to come
// back to.
static gint g_restore_width = 0;
static gint g_restore_height = 0;

static gchar* window_state_path() {
  return g_build_filename(g_get_user_config_dir(), "dev.colewiz.tigerhub",
                          "window.ini", nullptr);
}

static void restore_window_state(GtkWindow* window) {
  gint width = 1280;
  gint height = 720;
  gboolean maximized = FALSE;

  g_autofree gchar* path = window_state_path();
  g_autoptr(GKeyFile) state = g_key_file_new();
  if (g_key_file_load_from_file(state, path, G_KEY_FILE_NONE, nullptr)) {
    g_autoptr(GError) error = nullptr;
    gint stored_width = g_key_file_get_integer(state, "window", "width", &error);
    if (error == nullptr && stored_width > 400) width = stored_width;
    g_clear_error(&error);
    gint stored_height = g_key_file_get_integer(state, "window", "height", &error);
    if (error == nullptr && stored_height > 300) height = stored_height;
    g_clear_error(&error);
    maximized = g_key_file_get_boolean(state, "window", "maximized", nullptr);
  }

  gtk_window_set_default_size(window, width, height);
  if (maximized) gtk_window_maximize(window);
}

static void write_window_state(GtkWindow* window) {
  if (window == nullptr) return;
  g_autoptr(GKeyFile) state = g_key_file_new();

  gboolean maximized = gtk_window_is_maximized(window);
  g_key_file_set_boolean(state, "window", "maximized", maximized);

  if (g_restore_width > 400 && g_restore_height > 300) {
    g_key_file_set_integer(state, "window", "width", g_restore_width);
    g_key_file_set_integer(state, "window", "height", g_restore_height);
  }

  g_autofree gchar* path = window_state_path();
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0755);
  g_key_file_save_to_file(state, path, nullptr);
}

static gboolean on_window_configured(GtkWidget* widget, GdkEvent* event,
                                     gpointer user_data) {
  GtkWindow* window = GTK_WINDOW(widget);
  if (!gtk_window_is_maximized(window)) {
    gtk_window_get_size(window, &g_restore_width, &g_restore_height);
  }
  return FALSE;
}

static gboolean on_window_deleted(GtkWidget* widget, GdkEvent* event,
                                  gpointer user_data) {
  write_window_state(GTK_WINDOW(widget));
  // Never swallow the close.
  return FALSE;
}

// delete-event only fires when the window is closed the normal way. A logout,
// a session restart, or anything that sends SIGTERM would otherwise lose the
// size, and a terminated app losing your layout is exactly the kind of thing
// that makes something feel unfinished. Saving here also means the app exits
// cleanly rather than being cut down mid frame.
static gboolean on_terminate(gpointer user_data) {
  write_window_state(g_tracked_window);
  GApplication* application = G_APPLICATION(user_data);
  if (g_tracked_window != nullptr) {
    gtk_widget_destroy(GTK_WIDGET(g_tracked_window));
    g_tracked_window = nullptr;
  }
  g_application_quit(application);
  return G_SOURCE_REMOVE;
}

static void my_application_activate(GApplication* application) {
  // A second launch activates the instance that is already running rather
  // than building another window into the same process.
  if (g_tracked_window != nullptr) {
    gtk_window_present(g_tracked_window);
    return;
  }

  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif

  // A GTK header bar is client side decoration. Under a tiling compositor the
  // window manager already frames the window, so the header bar is a second
  // title bar stacked on the first and just eats vertical space. Detect the
  // tiling compositors we care about and drop it.
  const gchar* desktop = g_getenv("XDG_CURRENT_DESKTOP");
  const gchar* session = g_getenv("XDG_SESSION_DESKTOP");
  const gchar* tiling[] = {"Hyprland", "sway", "river", "niri", "Wayfire", nullptr};
  for (int i = 0; tiling[i] != nullptr; i++) {
    if ((desktop != nullptr && g_ascii_strcasecmp(desktop, tiling[i]) == 0) ||
        (session != nullptr && g_ascii_strcasecmp(session, tiling[i]) == 0)) {
      use_header_bar = FALSE;
      break;
    }
  }
  // Hyprland does not always set XDG_CURRENT_DESKTOP, but it always exports
  // this, so it is the more reliable signal.
  if (g_getenv("HYPRLAND_INSTANCE_SIGNATURE") != nullptr) {
    use_header_bar = FALSE;
  }

  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "TigerHub");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "TigerHub");
  }

  set_window_icon(window);
  restore_window_state(window);
  g_tracked_window = window;
  g_signal_connect(window, "delete-event", G_CALLBACK(on_window_deleted),
                   nullptr);
  g_signal_connect(window, "configure-event",
                   G_CALLBACK(on_window_configured), nullptr);
  g_unix_signal_add(SIGTERM, on_terminate, application);
  g_unix_signal_add(SIGINT, on_terminate, application);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Single instance, deliberately.
  //
  // The Flutter template ships G_APPLICATION_NON_UNIQUE, so every launch got
  // its own process and its own window. Opening the app from the launcher
  // while it was already running left you with two of them, both scraping on
  // their own two minute tickers and both writing the same snapshot files.
  //
  // With uniqueness on, a second launch hands its activation to the running
  // instance over D-Bus and exits, and my_application_activate presents the
  // window that already exists.
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_DEFAULT_FLAGS, nullptr));
}
