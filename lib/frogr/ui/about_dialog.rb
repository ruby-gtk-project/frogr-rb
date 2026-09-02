# frozen_string_literal: true

require 'gtk4'

require_relative '../version'

module Frogr
  module Ui
    # The About window. Credits are carried over from upstream's AUTHORS.
    class AboutDialog
      def initialize(parent:)
        @parent = parent
      end

      def build
        dialog
      end

      def dialog
        @dialog ||= Gtk::AboutDialog.new.tap do |dlg|
          dlg.transient_for = @parent
          dlg.modal = true
          dlg.program_name = 'frogr'
          dlg.version = Frogr::VERSION
          dlg.logo_icon_name = 'org.gnome.frogr'
          dlg.comments = 'Flickr Remote Organizer, ported to Ruby GTK4'
          dlg.website = 'https://wiki.gnome.org/Apps/Frogr'
          dlg.license_type = Gtk::License::GPL_3_0
          dlg.copyright = 'Copyright © 2009-2024 Mario Sanchez Prada'
          dlg.authors = ['Mario Sanchez Prada <msanchez@gnome.org>']
          dlg.translator_credits = 'translator-credits'
        end
      end
    end
  end
end
