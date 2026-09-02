# frozen_string_literal: true

require 'fileutils'
require 'rexml/document'

require_relative 'enums'
require_relative 'models/account'
require_relative 'util'

module Frogr
  # Reads and writes ~/.config/frogr/{settings,accounts}.xml.
  #
  # The schema is byte-compatible with upstream frogr's: the same element
  # names, the same nesting, the same version attribute, and the same 0600
  # permissions on both files (accounts.xml holds OAuth tokens).
  class Config
    SETTINGS_FILENAME = 'settings.xml'
    ACCOUNTS_FILENAME = 'accounts.xml'
    SETTINGS_CURRENT_VERSION = '2'

    # Defaults applied to newly loaded pictures.
    attr_accessor :default_public, :default_family, :default_friend,
                  :default_license, :default_safety_level, :default_content_type,
                  :default_show_in_search, :default_send_geolocation_data,
                  :default_replace_date_posted

    # Behaviour toggles.
    attr_accessor :tags_autocompletion, :keep_file_extensions,
                  :import_tags_from_metadata, :use_dark_theme

    # Main-view options, driven by the View submenu.
    attr_accessor :mainview_enable_tooltips, :mainview_sorting_criteria,
                  :mainview_sorting_reversed

    # HTTP proxy.
    attr_accessor :use_proxy, :proxy_host, :proxy_port, :proxy_username, :proxy_password

    attr_reader :accounts, :settings_version, :config_dir

    def self.instance = @instance ||= new

    def initialize(config_dir: Util.config_dir)
      @config_dir = config_dir
      @accounts = []
      @settings_version = SETTINGS_CURRENT_VERSION

      @default_public = true
      @default_family = false
      @default_friend = false
      @default_license = -1
      @default_safety_level = 1
      @default_content_type = 1
      @default_show_in_search = true
      @default_send_geolocation_data = false
      @default_replace_date_posted = false

      @tags_autocompletion = true
      @keep_file_extensions = false
      @import_tags_from_metadata = true
      @use_dark_theme = false

      @mainview_enable_tooltips = true
      @mainview_sorting_criteria = :as_loaded
      @mainview_sorting_reversed = false

      @use_proxy = false
      @proxy_host = nil
      @proxy_port = nil
      @proxy_username = nil
      @proxy_password = nil

      load_settings
      load_accounts
    end

    # --- Accounts ---------------------------------------------------------

    def add_account(account)
      accounts.reject! { |existing| existing.username == account.username }
      accounts << account
      set_active_account(account.username)
    end

    def remove_account(username)
      accounts.reject! { |account| account.username == username }
      # Losing the active account promotes whichever one is left, so the app
      # never sits in a state where it has accounts but none of them selected.
      accounts.first.then { |account| account&.active = true }
      save_accounts
    end

    def set_active_account(username)
      accounts.each { |account| account.active = (account.username == username) }
      save_accounts
    end

    def active_account = accounts.find(&:active?)

    # --- Persistence ------------------------------------------------------

    def save_all = save_settings && save_accounts

    def save_settings
      write_xml(SETTINGS_FILENAME, settings_document)
    end

    def save_accounts
      write_xml(ACCOUNTS_FILENAME, accounts_document)
    end

    private

    def settings_document
      REXML::Document.new.tap do |doc|
        doc << REXML::XMLDecl.new('1.0', 'UTF-8')

        doc.add_element('settings', 'version' => SETTINGS_CURRENT_VERSION).tap do |root|
          root.add_element('default-visibility').tap do |node|
            add_bool(node, 'public', default_public)
            add_bool(node, 'family', default_family)
            add_bool(node, 'friend', default_friend)
          end

          add_text(root, 'default-license', default_license)
          add_text(root, 'default-content-type', default_content_type)
          add_text(root, 'default-safety-level', default_safety_level)

          add_bool(root, 'default-send-geolocation-data', default_send_geolocation_data)
          add_bool(root, 'default-show-in-search', default_show_in_search)
          add_bool(root, 'default-replace-date-posted', default_replace_date_posted)

          add_bool(root, 'tags-autocompletion', tags_autocompletion)
          add_bool(root, 'keep-file-extensions', keep_file_extensions)
          add_bool(root, 'import-tags-from-metadata', import_tags_from_metadata)
          add_bool(root, 'use-dark-theme', use_dark_theme)

          root.add_element('http-proxy').tap do |node|
            add_bool(node, 'use-proxy', use_proxy)
            add_text(node, 'proxy-host', proxy_host)
            add_text(node, 'proxy-port', proxy_port)
            add_text(node, 'proxy-username', proxy_username)
            add_text(node, 'proxy-password', proxy_password)
          end

          root.add_element('mainview-options').tap do |node|
            add_bool(node, 'enable-tooltips', mainview_enable_tooltips)
            add_text(node, 'sorting-criteria', Enums::SORTING_CRITERIA[mainview_sorting_criteria])
            add_bool(node, 'sorting-reversed', mainview_sorting_reversed)
          end
        end
      end
    end

    def accounts_document
      REXML::Document.new.tap do |doc|
        doc << REXML::XMLDecl.new('1.0', 'UTF-8')

        doc.add_element('accounts').tap do |root|
          accounts.each do |account|
            root.add_element('account', 'version' => account.version).tap do |node|
              add_text(node, 'token', account.token)
              add_text(node, 'token-secret', account.token_secret)
              add_text(node, 'permissions', account.permissions)
              add_text(node, 'id', account.id)
              add_text(node, 'username', account.username)
              add_text(node, 'fullname', account.fullname)
              add_text(node, 'active', account.active? ? '1' : '0')
            end
          end
        end
      end
    end

    def load_settings
      read_xml(SETTINGS_FILENAME).then do |root|
        if root && root.name == 'settings'
          @settings_version = root.attributes['version'] || '1'

          root.elements['default-visibility'].then do |node|
            if node
              @default_public = bool(node, 'public', default_public)
              @default_family = bool(node, 'family', default_family)
              @default_friend = bool(node, 'friend', default_friend)
            end
          end

          @default_license = int(root, 'default-license', default_license)
          @default_content_type = int(root, 'default-content-type', default_content_type)
          @default_safety_level = int(root, 'default-safety-level', default_safety_level)

          @default_send_geolocation_data = bool(root, 'default-send-geolocation-data', default_send_geolocation_data)
          @default_show_in_search = bool(root, 'default-show-in-search', default_show_in_search)
          @default_replace_date_posted = bool(root, 'default-replace-date-posted', default_replace_date_posted)

          @tags_autocompletion = bool(root, 'tags-autocompletion', tags_autocompletion)
          @keep_file_extensions = bool(root, 'keep-file-extensions', keep_file_extensions)
          @import_tags_from_metadata = bool(root, 'import-tags-from-metadata', import_tags_from_metadata)
          @use_dark_theme = bool(root, 'use-dark-theme', use_dark_theme)

          root.elements['http-proxy'].then do |node|
            if node
              @use_proxy = bool(node, 'use-proxy', use_proxy)
              @proxy_host = text(node, 'proxy-host')
              @proxy_port = text(node, 'proxy-port')
              @proxy_username = text(node, 'proxy-username')
              @proxy_password = text(node, 'proxy-password')
            end
          end

          root.elements['mainview-options'].then do |node|
            if node
              @mainview_enable_tooltips = bool(node, 'enable-tooltips', mainview_enable_tooltips)
              @mainview_sorting_criteria = Enums.sorting_criteria_from_int(int(node, 'sorting-criteria', 0))
              @mainview_sorting_reversed = bool(node, 'sorting-reversed', mainview_sorting_reversed)
            end
          end
        end
      end
    end

    def load_accounts
      read_xml(ACCOUNTS_FILENAME).then do |root|
        if root && root.name == 'accounts'
          @accounts = root.get_elements('account').filter_map do |node|
            Models::Account.new(
              token: text(node, 'token'),
              token_secret: text(node, 'token-secret')
            ).tap do |account|
              account.version = node.attributes['version'] || '1'
              account.permissions = text(node, 'permissions')
              account.id = text(node, 'id')
              account.username = text(node, 'username')
              account.fullname = text(node, 'fullname')
              account.active = text(node, 'active') == '1'
            end.then { |account| account if account.valid? }
          end
        end
      end
    end

    # --- XML plumbing -----------------------------------------------------

    def read_xml(filename)
      File.join(config_dir, filename).then do |path|
        REXML::Document.new(File.read(path)).root if File.exist?(path)
      end
    rescue REXML::ParseException, SystemCallError => e
      warn "frogr: could not read #{filename}: #{e.message}"
      nil
    end

    def write_xml(filename, document)
      FileUtils.mkdir_p(config_dir)

      File.join(config_dir, filename).then do |path|
        File.write(path, String.new.tap { |out| formatter.write(document, out) })
        # Both files can hold credentials, so neither is world-readable.
        File.chmod(0o600, path)
      end

      true
    rescue SystemCallError => e
      warn "frogr: could not write #{filename}: #{e.message}"
      false
    end

    # `compact` keeps element text on the same line as its tags, matching the
    # output libxml2 gave upstream so the two versions' files look alike.
    def formatter
      @formatter ||= REXML::Formatters::Pretty.new(2).tap { |f| f.compact = true }
    end

    def add_text(parent, name, value)
      parent.add_element(name).add_text(value.to_s) unless value.nil?
    end

    def add_bool(parent, name, value) = add_text(parent, name, value ? '1' : '0')

    def text(parent, name) = parent.elements[name]&.text

    def bool(parent, name, fallback)
      text(parent, name).then { |value| value.nil? ? fallback : value.strip == '1' }
    end

    def int(parent, name, fallback)
      text(parent, name).then { |value| value.nil? ? fallback : value.strip.to_i }
    end
  end
end
