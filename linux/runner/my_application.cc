#include "my_application.h"

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

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
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
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "PDF Translate");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "PDF Translate");
  }

  gtk_window_set_default_size(window, 1280, 720);
  gtk_window_set_icon_name(window, "pdf-translate");
  gtk_window_set_default_icon_name("pdf-translate");
  // Fallback: carrega pixbuf se o tema ainda não tem o ícone (flutter run / bundle sem install)
  {
    g_autoptr(GError) err = nullptr;
    g_autoptr(GdkPixbuf) pixbuf = nullptr;
    gchar *home_icon = g_build_filename(g_get_home_dir(), ".local/share/icons/hicolor/512x512/apps/pdf-translate.png", nullptr);
    // tenta achar o executável para montar caminho do bundle
    gchar *exe_path = nullptr;
    gchar *exe_link = g_file_read_link("/proc/self/exe", &err);
    if (exe_link != nullptr) exe_path = g_path_get_dirname(exe_link);
    gchar *bundle_icon = nullptr;
    gchar *project_icon = nullptr;
    if (exe_path != nullptr) {
      bundle_icon = g_build_filename(exe_path, "data/flutter_assets/assets/icon/app_icon.png", nullptr);
      // exe_path = .../build/linux/x64/debug/bundle -> sobe 4 níveis até a raiz do projeto
      gchar *p1 = g_path_get_dirname(exe_path);
      gchar *p2 = p1 ? g_path_get_dirname(p1) : nullptr;
      gchar *p3 = p2 ? g_path_get_dirname(p2) : nullptr;
      gchar *p4 = p3 ? g_path_get_dirname(p3) : nullptr;
      gchar *project_root = p4 ? g_path_get_dirname(p4) : nullptr; // .../pdf_translate
      if (project_root != nullptr) project_icon = g_build_filename(project_root, "assets/icon/app_icon.png", nullptr);
      g_free(p1); g_free(p2); g_free(p3); g_free(p4); g_free(project_root);
    }
    const char *candidates[] = {home_icon, "/usr/share/icons/hicolor/512x512/apps/pdf-translate.png", "/usr/share/pixmaps/pdf-translate.png", bundle_icon, project_icon, "assets/icon/app_icon.png", nullptr};
    bool icon_ok = false;
    for (int i = 0; candidates[i] != nullptr; i++) {
      if (candidates[i] == nullptr) continue;
      g_clear_error(&err);
      pixbuf = gdk_pixbuf_new_from_file(candidates[i], &err);
      if (pixbuf != nullptr) { gtk_window_set_icon(window, pixbuf); g_message("Icon OK: %s", candidates[i]); icon_ok = true; break; }
    }
    if (!icon_ok) g_message("Icon FAIL - nenhum candidato achado (home=%s bundle=%s project=%s)", home_icon ? home_icon : "(null)", bundle_icon ? bundle_icon : "(null)", project_icon ? project_icon : "(null)");
    g_free(home_icon);
    g_free(exe_link);
    g_free(exe_path);
    g_free(bundle_icon);
    g_free(project_icon);
  }

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

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}
