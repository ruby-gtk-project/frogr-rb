# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative '../enums'

module Frogr
  module Ui
    # Preferences: the defaults applied to newly loaded pictures, a few
    # behaviour toggles, and the HTTP proxy.
    #
    # The C version built three GtkNotebook tabs by hand; Adwaita's
    # PreferencesDialog gives the same three pages with the platform's own
    # layout, so each page here is just its groups and rows.
    class SettingsDialog
      def initialize(controller:, parent:, on_closed:)
        @controller = controller
        @config = controller.config
        @parent = parent
        @on_closed = on_closed
      end

      def build
        dialog.tap do |dlg|
          dlg.add(general_page)
          dlg.add(misc_page)
          dlg.add(connection_page)

          general_page.tap do |page|
            page.add(visibility_group)
            page.add(defaults_group)

            visibility_group.tap do |group|
              group.add(public_row)
              group.add(family_row)
              group.add(friend_row)
            end

            defaults_group.tap do |group|
              group.add(license_row)
              group.add(safety_row)
              group.add(content_row)
            end
          end

          misc_page.tap do |page|
            page.add(other_defaults_group)
            page.add(options_group)

            other_defaults_group.tap do |group|
              group.add(show_in_search_row)
              group.add(geolocation_row)
              group.add(replace_date_row)
            end

            options_group.tap do |group|
              group.add(tags_autocompletion_row)
              group.add(keep_extensions_row)
              group.add(import_tags_row)
              group.add(dark_theme_row)
            end
          end

          connection_page.tap do |page|
            page.add(proxy_group)

            proxy_group.tap do |group|
              group.add(use_proxy_row)
              group.add(proxy_host_row)
              group.add(proxy_port_row)
              group.add(proxy_username_row)
              group.add(proxy_password_row)

              use_proxy_row.signal_connect('notify::active') { update_proxy_sensitivity }
            end
          end

          dlg.signal_connect('closed') { save }
        end

        update_proxy_sensitivity
        dialog
      end

      private

      # Settings are written on close rather than per-keystroke, matching how
      # the C dialog behaved, and the proxy is re-applied to the live session.
      def save
        @config.default_public = public_row.active?
        @config.default_family = family_row.active?
        @config.default_friend = friend_row.active?
        @config.default_license = Enums.value_at(Enums::LICENSES, license_row.selected)
        @config.default_safety_level = Enums.value_at(Enums::SAFETY_LEVELS, safety_row.selected)
        @config.default_content_type = Enums.value_at(Enums::CONTENT_TYPES, content_row.selected)

        @config.default_show_in_search = show_in_search_row.active?
        @config.default_send_geolocation_data = geolocation_row.active?
        @config.default_replace_date_posted = replace_date_row.active?

        @config.tags_autocompletion = tags_autocompletion_row.active?
        @config.keep_file_extensions = keep_extensions_row.active?
        @config.import_tags_from_metadata = import_tags_row.active?

        @config.use_proxy = use_proxy_row.active?
        @config.proxy_host = proxy_host_row.text
        @config.proxy_port = proxy_port_row.text
        @config.proxy_username = proxy_username_row.text
        @config.proxy_password = proxy_password_row.text

        @controller.use_dark_theme = dark_theme_row.active?
        @config.save_settings
        @controller.apply_proxy
        @on_closed.call
      end

      def update_proxy_sensitivity
        [proxy_host_row, proxy_port_row, proxy_username_row, proxy_password_row].each do |row|
          row.sensitive = use_proxy_row.active?
        end
      end

      # --- Widgets ----------------------------------------------------------

      def dialog = @dialog ||= Adwaita::PreferencesDialog.new.tap { |dlg| dlg.title = 'Preferences' }

      def general_page
        @general_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = '_General'
          page.use_underline = true
          page.icon_name = 'preferences-system-symbolic'
        end
      end

      def misc_page
        @misc_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = '_Misc'
          page.use_underline = true
          page.icon_name = 'preferences-other-symbolic'
        end
      end

      def connection_page
        @connection_page ||= Adwaita::PreferencesPage.new.tap do |page|
          page.title = 'Connec_tion'
          page.use_underline = true
          page.icon_name = 'network-transmit-receive-symbolic'
        end
      end

      def visibility_group
        @visibility_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Default Visibility' }
      end

      def defaults_group
        @defaults_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Defaults' }
      end

      def other_defaults_group
        @other_defaults_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Other Defaults' }
      end

      def options_group
        @options_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Other options' }
      end

      def proxy_group
        @proxy_group ||= Adwaita::PreferencesGroup.new.tap { |g| g.title = 'Proxy Settings' }
      end

      def public_row = @public_row ||= switch_row('P_ublic', @config.default_public)
      def family_row = @family_row ||= switch_row('_Family', @config.default_family)
      def friend_row = @friend_row ||= switch_row('F_riends', @config.default_friend)

      def show_in_search_row
        @show_in_search_row ||= switch_row('_Show Pictures in Global Search Results',
                                           @config.default_show_in_search)
      end

      def geolocation_row
        @geolocation_row ||= switch_row('Set Geo_location Information for Pictures',
                                        @config.default_send_geolocation_data)
      end

      def replace_date_row
        @replace_date_row ||= switch_row("Replace 'Date Posted' with 'Date Taken' for Pictures",
                                         @config.default_replace_date_posted)
      end

      def tags_autocompletion_row
        @tags_autocompletion_row ||= switch_row('Ena_ble Tags Auto-Completion', @config.tags_autocompletion)
      end

      def keep_extensions_row
        @keep_extensions_row ||= switch_row('_Keep File Extensions in Titles when Loading',
                                            @config.keep_file_extensions)
      end

      def import_tags_row
        @import_tags_row ||= switch_row('_Import Tags from Pictures Metadata',
                                        @config.import_tags_from_metadata)
      end

      def dark_theme_row = @dark_theme_row ||= switch_row('Use _Dark GTK Theme', @config.use_dark_theme)
      def use_proxy_row = @use_proxy_row ||= switch_row('_Enable HTTP Proxy', @config.use_proxy)

      def license_row
        @license_row ||= combo_row('Default License', Enums::LICENSES, @config.default_license)
      end

      def safety_row
        @safety_row ||= combo_row('Default Safety Level', Enums::SAFETY_LEVELS, @config.default_safety_level)
      end

      def content_row
        @content_row ||= combo_row('Default Content Type', Enums::CONTENT_TYPES, @config.default_content_type)
      end

      def proxy_host_row = @proxy_host_row ||= entry_row('_Host', @config.proxy_host)
      def proxy_port_row = @proxy_port_row ||= entry_row('_Port', @config.proxy_port)
      def proxy_username_row = @proxy_username_row ||= entry_row('U_sername', @config.proxy_username)

      def proxy_password_row
        @proxy_password_row ||= Adwaita::PasswordEntryRow.new.tap do |row|
          row.title = 'Pass_word'
          row.use_underline = true
          row.text = @config.proxy_password.to_s
        end
      end

      def switch_row(title, active)
        Adwaita::SwitchRow.new.tap do |row|
          row.title = title
          row.use_underline = true
          row.active = active
        end
      end

      def entry_row(title, text)
        Adwaita::EntryRow.new.tap do |row|
          row.title = title
          row.use_underline = true
          row.text = text.to_s
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
