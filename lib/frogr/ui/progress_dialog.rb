# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

module Frogr
  module Ui
    # The modal progress window shown while loading or uploading.
    #
    # Adwaita::Dialog is used rather than a GtkWindow so it presents attached
    # to the main window, matching how the rest of the app's dialogs behave.
    class ProgressDialog
      def initialize(on_cancel:)
        @on_cancel = on_cancel
        @open = false
      end

      def build
        dialog.tap do |dlg|
          dlg.child = box

          box.tap do |b|
            b.append(description_label)
            b.append(progress_bar)
            b.append(cancel_button)

            cancel_button.signal_connect('clicked') do
              @on_cancel.call
              close
            end
          end
        end

        self
      end

      def title=(text)
        dialog.title = text.to_s
      end

      def description=(text)
        description_label.label = text.to_s
      end

      def update(fraction:, status:, description:)
        progress_bar.fraction = fraction.to_f.clamp(0.0, 1.0)
        progress_bar.text = status.to_s
        description_label.label = description.to_s unless description.nil?
      end

      def present(parent)
        # Presenting an already-open dialog stacks it; loading straight into an
        # upload would otherwise leave one behind.
        dialog.present(parent) unless @open
        @open = true
      end

      def close
        dialog.close if @open
        @open = false
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |dlg|
          dlg.content_width = 400
          dlg.follows_content_size = true
        end
      end

      def box
        @box ||= Gtk::Box.new(:vertical, 12).tap do |box|
          box.margin_top = 24
          box.margin_bottom = 24
          box.margin_start = 24
          box.margin_end = 24
        end
      end

      def description_label
        @description_label ||= Gtk::Label.new.tap do |label|
          label.ellipsize = :middle
          label.max_width_chars = 40
          label.add_css_class('dim-label')
        end
      end

      def progress_bar
        @progress_bar ||= Gtk::ProgressBar.new.tap do |bar|
          bar.show_text = true
          bar.hexpand = true
        end
      end

      def cancel_button
        @cancel_button ||= Gtk::Button.new.tap do |button|
          button.label = '_Cancel'
          button.use_underline = true
          button.halign = :center
        end
      end
    end
  end
end
