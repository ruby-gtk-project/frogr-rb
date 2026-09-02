# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'tag_entry'

module Frogr
  module Ui
    # Adds a space-separated list of tags to every selected picture.
    class AddTagsDialog
      def initialize(model:, parent:, on_added:)
        @model = model
        @parent = parent
        @on_added = on_added
      end

      def build
        dialog.tap do |dlg|
          dlg.child = toolbar_view

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = box

            header_bar.tap do |bar|
              bar.pack_start(cancel_button)
              bar.pack_end(add_button)

              cancel_button.signal_connect('clicked') { dlg.close }

              add_button.signal_connect('clicked') do
                @on_added.call(tag_entry.text)
                dlg.close
              end
            end

            box.tap do |b|
              b.append(prompt_label)
              b.append(tag_entry.build)

              tag_entry.entry.signal_connect('activate') do
                @on_added.call(tag_entry.text)
                dlg.close
              end
            end
          end
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |dlg|
          dlg.title = 'Add Tags'
          dlg.content_width = 420
          dlg.follows_content_size = true
        end
      end

      def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
      def header_bar = @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.show_end_title_buttons = false }

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

      def box
        @box ||= Gtk::Box.new(:vertical, 12).tap do |box|
          box.margin_top = 18
          box.margin_bottom = 18
          box.margin_start = 18
          box.margin_end = 18
        end
      end

      def prompt_label
        @prompt_label ||= Gtk::Label.new('Enter a spaces separated list of tags:').tap do |label|
          label.xalign = 0
        end
      end

      def tag_entry = @tag_entry ||= TagEntry.new(model: @model)
    end
  end
end
