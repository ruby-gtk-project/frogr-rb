# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative '../models/photo_set'

module Frogr
  module Ui
    # Creates a set locally and queues the selected pictures for it. The set is
    # only created on Flickr when the first of those pictures is uploaded.
    class CreateNewSetDialog
      def initialize(pictures:, model:, parent:, on_created:)
        @pictures = pictures
        @model = model
        @parent = parent
        @on_created = on_created
      end

      def build
        dialog.tap do |dlg|
          dlg.child = toolbar_view

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = preferences_page

            header_bar.tap do |bar|
              bar.pack_start(cancel_button)
              bar.pack_end(add_button)

              cancel_button.signal_connect('clicked') { dlg.close }
              add_button.signal_connect('clicked') { create_set(dlg) }
            end

            preferences_page.tap do |page|
              page.add(group)

              group.tap do |g|
                g.add(title_row)
                g.add(description_row)
                g.add(fill_details_row)
              end

              title_row.signal_connect('changed') { update_sensitivity }
            end
          end
        end

        update_sensitivity
        dialog
      end

      private

      # A set with no title cannot be created, so the button follows the field.
      def update_sensitivity
        add_button.sensitive = !title_row.text.strip.empty?
      end

      def create_set(dlg)
        title_row.text.strip.then do |title|
          next if title.empty?

          Models::PhotoSet.new(title: title, description: description_row.text).tap do |set|
            @model.add_local_photoset(set)

            @pictures.each do |picture|
              picture.add_photoset(set)

              if fill_details_row.active?
                picture.title = title
                picture.description = description_row.text
              end
            end
          end

          @on_created.call
          dlg.close
        end
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |dlg|
          dlg.title = 'Create New Set'
          dlg.content_width = 480
          dlg.follows_content_size = true
        end
      end

      def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
      def header_bar = @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.show_end_title_buttons = false }
      def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new
      def group = @group ||= Adwaita::PreferencesGroup.new

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

      def title_row = @title_row ||= Adwaita::EntryRow.new.tap { |row| row.title = 'Title' }
      def description_row = @description_row ||= Adwaita::EntryRow.new.tap { |row| row.title = 'Description' }

      def fill_details_row
        @fill_details_row ||= Adwaita::SwitchRow.new.tap do |row|
          row.title = 'Fill Pictures Details with Title and Description'
          row.active = false
        end
      end
    end
  end
end
