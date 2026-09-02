# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative '../enums'
require_relative 'tag_entry'

module Frogr
  module Ui
    # Edits title, description, tags and every per-picture Flickr property.
    #
    # It edits one or many pictures at once. With several selected, a field
    # starts blank when they disagree and is only written back if the user
    # actually changes it — so editing tags across a selection does not
    # flatten the titles.
    class DetailsDialog
      def initialize(pictures:, model:, parent:, on_saved:)
        @pictures = pictures
        @model = model
        @parent = parent
        @on_saved = on_saved
      end

      def build
        dialog.tap do |dlg|
          dlg.child = toolbar_view

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = preferences_page

            header_bar.tap do |bar|
              bar.pack_start(cancel_button)
              bar.pack_end(save_button)

              cancel_button.signal_connect('clicked') { dlg.close }

              save_button.signal_connect('clicked') do
                save
                @on_saved.call
                dlg.close
              end
            end

            preferences_page.tap do |page|
              page.add(basics_group)
              page.add(visibility_group)
              page.add(properties_group)
              page.add(other_group)

              basics_group.tap do |group|
                group.add(title_row)
                group.add(description_row)
                group.add(tags_row)

                tags_row.child = tags_box

                tags_box.tap do |box|
                  box.append(tags_label)
                  box.append(tag_entry.build)
                end
              end

              visibility_group.tap do |group|
                group.add(public_row)
                group.add(family_row)
                group.add(friend_row)

                # Family and friends only mean anything on a private picture,
                # which is how Flickr itself treats them.
                public_row.signal_connect('notify::active') { update_visibility_sensitivity }
              end

              properties_group.tap do |group|
                group.add(license_row)
                group.add(safety_row)
                group.add(content_row)
              end

              other_group.tap do |group|
                group.add(show_in_search_row)
                group.add(send_location_row)
                group.add(replace_date_row)
              end
            end
          end
        end

        update_visibility_sensitivity
        dialog
      end

      private

      def first = @pictures.first

      # Returns the shared value of `attribute` across the selection, or nil
      # when the pictures disagree — which is what leaves a field blank.
      def common(&block)
        @pictures.map(&block).uniq.then { |values| values.length == 1 ? values.first : nil }
      end

      def save
        @pictures.each do |picture|
          picture.title = title_row.text unless title_row.text.empty? && @pictures.length > 1
          picture.description = description_row.text unless description_row.text.empty? && @pictures.length > 1

          unless tag_entry.text.strip.empty?
            picture.tags = tag_entry.text
            @model.add_local_tags_from_string(tag_entry.text)
          end

          picture.public = public_row.active?
          picture.family = family_row.active?
          picture.friend = friend_row.active?

          picture.license = Enums.value_at(Enums::LICENSES, license_row.selected)
          picture.safety_level = Enums.value_at(Enums::SAFETY_LEVELS, safety_row.selected)
          picture.content_type = Enums.value_at(Enums::CONTENT_TYPES, content_row.selected)

          picture.show_in_search = show_in_search_row.active?
          picture.send_location = send_location_row.active?
          picture.replace_date_posted = replace_date_row.active?
        end
      end

      def update_visibility_sensitivity
        [family_row, friend_row].each { |row| row.sensitive = !public_row.active? }
      end

      # --- Widgets ----------------------------------------------------------

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |dlg|
          dlg.title = 'Edit Picture Details'
          dlg.content_width = 560
          dlg.content_height = 640
        end
      end

      def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
      def header_bar = @header_bar ||= Adwaita::HeaderBar.new.tap { |bar| bar.show_end_title_buttons = false }
      def preferences_page = @preferences_page ||= Adwaita::PreferencesPage.new

      def cancel_button
        @cancel_button ||= Gtk::Button.new.tap do |button|
          button.label = '_Cancel'
          button.use_underline = true
        end
      end

      def save_button
        @save_button ||= Gtk::Button.new.tap do |button|
          button.label = '_Edit'
          button.use_underline = true
          button.add_css_class('suggested-action')
        end
      end

      def basics_group
        @basics_group ||= Adwaita::PreferencesGroup.new.tap do |group|
          group.title = @pictures.length == 1 ? first.basename : "#{@pictures.length} pictures"
        end
      end

      def visibility_group
        @visibility_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Visibility' }
      end

      def properties_group
        @properties_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Properties' }
      end

      def other_group
        @other_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Other Properties' }
      end

      def title_row
        @title_row ||= Adwaita::EntryRow.new.tap do |row|
          row.title = '_Title'
          row.use_underline = true
          row.text = common(&:title).to_s
        end
      end

      def description_row
        @description_row ||= Adwaita::EntryRow.new.tap do |row|
          row.title = '_Description'
          row.use_underline = true
          row.text = common(&:description).to_s
        end
      end

      # Tags need the completing entry, which is a plain widget rather than a
      # row, so it goes inside a PreferencesRow. Setting `child` replaces the
      # row's own layout, which is why the label is supplied here too.
      def tags_row
        @tags_row ||= Adwaita::PreferencesRow.new.tap do |row|
          row.title = 'Tags'
          row.activatable = false
        end
      end

      def tags_box
        @tags_box ||= Gtk::Box.new(:horizontal, 12).tap do |box|
          box.margin_top = 8
          box.margin_bottom = 8
          box.margin_start = 12
          box.margin_end = 12
        end
      end

      def tags_label
        @tags_label ||= Gtk::Label.new('Ta_gs').tap do |label|
          label.use_underline = true
          label.xalign = 0
          label.mnemonic_widget = tag_entry.entry
        end
      end

      def tag_entry = @tag_entry ||= TagEntry.new(model: @model, text: common(&:tags_string).to_s)

      def public_row = @public_row ||= switch_row('P_ublic', common(&:public?))
      def family_row = @family_row ||= switch_row('_Family', common(&:family?))
      def friend_row = @friend_row ||= switch_row('F_riends', common(&:friend?))

      def show_in_search_row
        @show_in_search_row ||= switch_row('_Show Up in Global Search Results', common(&:show_in_search?))
      end

      def send_location_row
        @send_location_row ||= switch_row('Set Geo_location Information', common(&:send_location?)).tap do |row|
          # Nothing to send when none of the selected pictures carries GPS data.
          row.sensitive = @pictures.any?(&:location)
          row.subtitle = location_subtitle
        end
      end

      def location_subtitle
        common(&:location).then do |location|
          location ? location.to_s : 'No geolocation data in these pictures'
        end
      end

      def replace_date_row
        @replace_date_row ||= switch_row("Replace 'Date Posted' with 'Date Taken'", common(&:replace_date_posted?))
      end

      def license_row
        @license_row ||= combo_row('License Type', Enums::LICENSES, common(&:license))
      end

      def safety_row
        @safety_row ||= combo_row('Safety Level', Enums::SAFETY_LEVELS, common(&:safety_level))
      end

      def content_row
        @content_row ||= combo_row('Content Type', Enums::CONTENT_TYPES, common(&:content_type))
      end

      def switch_row(title, active)
        Adwaita::SwitchRow.new.tap do |row|
          row.title = title
          row.use_underline = true
          row.active = active ? true : false
        end
      end

      def combo_row(title, map, value)
        Adwaita::ComboRow.new.tap do |row|
          row.title = title
          row.model = Gtk::StringList.new(map.keys)
          row.selected = Enums.index_of(map, value)
        end
      end
    end
  end
end
