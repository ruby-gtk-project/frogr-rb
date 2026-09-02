# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

module Frogr
  module Ui
    # Shared shape for "Add to Sets" and "Add to Groups": fetch a list from
    # Flickr, show it with a checkbox per row, and apply the ticked ones to the
    # selected pictures.
    #
    # The two dialogs differ only in their title, column heading, how a row is
    # labelled, and what applying a row does — so those are the four things
    # subclasses supply, and everything else lives here.
    class SelectionListDialog
      def initialize(controller:, pictures:, parent:, on_added:)
        @controller = controller
        @pictures = pictures
        @parent = parent
        @on_added = on_added
        @rows = {}
      end

      def build
        dialog.tap do |dlg|
          dlg.child = toolbar_view

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = stack

            header_bar.tap do |bar|
              bar.pack_start(cancel_button)
              bar.pack_end(add_button)

              cancel_button.signal_connect('clicked') { dlg.close }

              add_button.signal_connect('clicked') do
                apply_checked
                @on_added.call
                dlg.close
              end
            end

            stack.tap do |s|
              s.add_named(spinner, 'loading')
              s.add_named(scrolled_window, 'list')
              s.add_named(empty_page, 'empty')

              scrolled_window.child = list_box
            end
          end
        end

        fetch
        dialog
      end

      private

      # --- Subclass hooks ---------------------------------------------------

      def dialog_title = raise(NotImplementedError)

      def empty_message = raise(NotImplementedError)

      def label_for(_item) = raise(NotImplementedError)

      def already_in?(_picture, _item) = raise(NotImplementedError)

      def apply(_picture, _item) = raise(NotImplementedError)

      def fetch_items(_on_finished, _on_error) = raise(NotImplementedError)

      # --- Behaviour --------------------------------------------------------

      def fetch
        stack.visible_child_name = 'loading'
        spinner.start

        fetch_items(
          ->(items) { populate(items) },
          lambda { |message|
            spinner.stop
            empty_page.description = message
            stack.visible_child_name = 'empty'
          }
        )
      end

      def populate(items)
        spinner.stop
        @rows = {}

        items.each do |item|
          Gtk::CheckButton.new.tap do |check|
            check.label = label_for(item)
            # A picture already in the set or group starts ticked and locked,
            # so the dialog cannot be used to undo an earlier addition.
            check.active = @pictures.all? { |picture| already_in?(picture, item) }
            check.sensitive = !check.active?
            @rows[check] = item
            list_box.append(check)
          end
        end

        stack.visible_child_name = items.empty? ? 'empty' : 'list'
      end

      def apply_checked
        @rows.select { |check, _| check.active? && check.sensitive? }.each_value do |item|
          @pictures.each { |picture| apply(picture, item) }
        end
      end

      # --- Widgets ----------------------------------------------------------

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |dlg|
          dlg.title = dialog_title
          dlg.content_width = 460
          dlg.content_height = 420
        end
      end

      def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
      def header_bar = @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.show_end_title_buttons = false }
      def stack = @stack ||= Gtk::Stack.new

      def cancel_button
        @cancel_button ||= Gtk::Button.new.tap do |button|
          button.label = '_Cancel'
          button.use_underline = true
        end
      end

      def add_button
        @add_button ||= Gtk::Button.new.tap do |button|
          button.label = '_Add'
          button.use_underline = true
          button.add_css_class('suggested-action')
        end
      end

      def spinner
        @spinner ||= Gtk::Spinner.new.tap do |spinner|
          spinner.halign = :center
          spinner.valign = :center
          spinner.width_request = 32
          spinner.height_request = 32
        end
      end

      def scrolled_window
        @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |window|
          window.hexpand = true
          window.vexpand = true
        end
      end

      def list_box
        @list_box ||= Gtk::ListBox.new.tap do |box|
          box.selection_mode = :none
          box.margin_top = 12
          box.margin_bottom = 12
          box.margin_start = 12
          box.margin_end = 12
          box.add_css_class('boxed-list')
        end
      end

      def empty_page
        @empty_page ||= Adwaita::StatusPage.new.tap do |page|
          page.icon_name = 'dialog-information-symbolic'
          page.title = empty_message
        end
      end
    end
  end
end
