# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'config'
require_relative 'controller'
require_relative 'ui/main_view'
require_relative 'util'
require_relative 'version'

module Frogr
  # Wires the application together.
  #
  # Gtk::Application rather than Adwaita::Application: the Ruby bindings for
  # the Adwaita subclasses have type-interface problems, while every other
  # Adwaita widget works fine inside a Gtk::ApplicationWindow.
  class App
    def initialize(files: [])
      @files = files
    end

    def build
      app.tap do
        app.signal_connect('startup') do
          Adwaita.init
          controller.use_dark_theme = controller.config.use_dark_theme
          Gtk::IconTheme.get_for_display(Gdk::Display.default)
                        .add_search_path(File.join(Util.data_dir, 'icons'))
        end

        app.signal_connect('activate') do
          main_view.build.present

          # Files named on the command line are queued once the window exists,
          # so their progress dialog has something to attach to.
          GLib::Idle.add do
            controller.load_pictures(@files.map { |path| Util.path_to_uri(path) }) unless @files.empty?
            false
          end
        end
      end
    end

    def run = app.run([])

    def app = @app ||= Gtk::Application.new(APP_ID, :default_flags)
    def controller = @controller ||= Controller.new
    def main_view = @main_view ||= Ui::MainView.new(app: app, controller: controller)
  end
end
