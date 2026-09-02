# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative 'config'
require_relative 'enums'
require_relative 'file_loader'
require_relative 'flickr/session'
require_relative 'model'
require_relative 'upload_job'
require_relative 'util'

module Frogr
  # Coordinates the session, the model and the views: authorisation, loading
  # files, fetching remote data, and uploading.
  #
  # The views call into the controller and the controller calls back through
  # `main_view`; nothing here builds widgets.
  class Controller
    # frogr's own registered Flickr application credentials, as upstream ships
    # them. They identify the app, not the user.
    API_KEY = '18861766601de84f0921ce6be729f925'
    SHARED_SECRET = '6233fbefd85f733a'

    attr_reader :model, :config, :session, :state
    attr_accessor :main_view, :project_path

    def initialize(config: Config.instance)
      @config = config
      @model = Model.new
      @session = Flickr::Session.new(api_key: API_KEY, secret: SHARED_SECRET)
      @state = :idle
      @project_path = nil
      @loader = nil
      @upload_job = nil
      @tags_fetched = false

      apply_proxy
      apply_active_account
    end

    def busy? = %i[loading_pictures uploading_pictures].include?(state)

    # --- Accounts and authorisation ---------------------------------------

    def accounts = config.accounts

    def active_account = config.active_account

    def authorized? = !active_account.nil? && session.authorized?

    def active_account=(username)
      config.set_active_account(username)
      apply_active_account
      invalidate_remote_data
      main_view&.account_changed
      fetch_account_extra_info
    end

    def revoke_authorization
      active_account.then do |account|
        if account
          config.remove_account(account.username)
          apply_active_account
          invalidate_remote_data
          main_view&.account_changed
        end
      end
    end

    # Step one of authorising: fetch the URL and open it in a browser.
    def open_auth_url(on_ready: nil, on_error: nil)
      session.request(
        :auth_url,
        on_success: lambda { |url|
          Util.open_uri(url, parent: main_view)
          on_ready&.call(url)
        },
        on_error: ->(error) { on_error&.call(error.message) }
      )
    end

    # Step two: turn the verification code into a stored account.
    def complete_auth(verification_code, on_success: nil, on_error: nil)
      session.request(
        :complete_auth, verification_code,
        on_success: lambda { |token|
          store_account(token)
          on_success&.call(active_account)
          fetch_account_extra_info
        },
        on_error: ->(error) { on_error&.call(error.message) }
      )
    end

    # Refreshes the quota figures shown in the status bar.
    def fetch_account_extra_info
      return unless authorized?

      session.request(
        :upload_status,
        on_success: lambda { |status|
          active_account&.apply_upload_status(status)
          config.save_accounts
          main_view&.account_changed
        },
        on_error: ->(_) { nil }
      )
    end

    # Tags feed the autocompletion in the tag entries, so they are only worth
    # fetching once per session and only when the preference is on.
    def fetch_tags_if_needed
      return if @tags_fetched || !authorized? || !config.tags_autocompletion

      @tags_fetched = true
      session.request(:tags_list,
                      on_success: ->(tags) { model.remote_tags = tags },
                      on_error: ->(_) { @tags_fetched = false })
    end

    def fetch_photosets(on_finished: nil, on_error: nil)
      session.request(:photosets,
                      on_success: lambda { |sets|
                        model.remote_photosets = sets
                        on_finished&.call(sets)
                      },
                      on_error: ->(error) { on_error&.call(error.message) })
    end

    def fetch_groups(on_finished: nil, on_error: nil)
      session.request(:groups,
                      on_success: lambda { |groups|
                        model.groups = groups
                        on_finished&.call(groups)
                      },
                      on_error: ->(error) { on_error&.call(error.message) })
    end

    # --- Loading pictures -------------------------------------------------

    def load_pictures(uris)
      return if busy? || uris.empty?

      @state = :loading_pictures
      main_view&.show_progress('Loading Pictures', nil)

      @loader = FileLoader.new(
        uris: uris,
        config: config,
        account: active_account,
        on_picture_loaded: ->(picture) { model.add_picture(picture) },
        on_progress: lambda { |done, total, uri|
          main_view&.set_progress(done.to_f / [total, 1].max,
                                  format('%d / %d', [done + 1, total].min, total),
                                  uri && File.basename(Util.uri_to_path(uri)))
        },
        on_finished: -> { finish_loading },
        on_error: ->(message) { main_view&.report_error(message) }
      )

      @loader.load_all
    end

    def finish_loading
      @loader = nil
      @state = :idle
      main_view&.hide_progress
      reorder_pictures
      fetch_tags_if_needed
    end

    def remove_pictures(pictures)
      pictures.each { |picture| model.remove_picture(picture) }
    end

    def reorder_pictures
      model.sort_pictures(config.mainview_sorting_criteria,
                          reversed: config.mainview_sorting_reversed)
    end

    # --- Uploading --------------------------------------------------------

    def upload_pictures(pictures)
      return if busy?

      pictures.reject { |picture| picture.title.to_s.empty? }.then do |uploadable|
        if !authorized?
          main_view&.report_error('You need to authorise frogr with your Flickr account first.')
        elsif uploadable.empty?
          main_view&.report_error('There is nothing to upload.')
        else
          start_upload(uploadable)
        end
      end
    end

    def start_upload(pictures)
      @state = :uploading_pictures
      main_view&.show_progress('Uploading Pictures', nil)

      @upload_job = UploadJob.new(
        pictures: pictures,
        session: session,
        model: model,
        on_progress: lambda { |fraction, index, total, title|
          main_view&.set_progress(fraction, format('%d / %d', index, total), title)
        },
        on_picture_done: ->(picture) { model.remove_picture(picture) },
        on_finished: ->(errors) { finish_upload(errors) },
        on_error: ->(message) { main_view&.report_error(message) }
      )

      @upload_job.start
    end

    def finish_upload(errors)
      @upload_job = nil
      @state = :idle
      main_view&.hide_progress
      main_view&.set_status_text(errors.empty? ? 'Upload finished.' : "Upload finished with #{errors.length} error(s).")
      fetch_account_extra_info
    end

    def cancel_ongoing_requests
      @loader&.cancel
      @upload_job&.cancel
      session.cancel_all
      @state = :idle
      main_view&.hide_progress
    end

    # --- Projects ---------------------------------------------------------

    def open_project(path)
      model.load_from_file(path).tap do |ok|
        if ok
          self.project_path = path
          main_view&.project_path_changed
          reorder_pictures
        end
      end
    end

    def save_project(path = project_path)
      return false if path.nil?

      model.save_to_file(path).tap do |ok|
        if ok
          self.project_path = path
          main_view&.project_path_changed
        end
      end
    end

    # --- Settings ---------------------------------------------------------

    def apply_proxy
      if config.use_proxy && !config.proxy_host.to_s.empty?
        session.proxy = {
          host: config.proxy_host,
          port: config.proxy_port.to_i,
          username: config.proxy_username,
          password: config.proxy_password
        }
      else
        session.use_default_proxy
      end
    end

    # Libadwaita owns the light/dark decision, so this goes through its style
    # manager rather than the GtkSettings property the C version set.
    def use_dark_theme=(value)
      config.use_dark_theme = value
      Adwaita::StyleManager.default.color_scheme =
        value ? Adwaita::ColorScheme::FORCE_DARK : Adwaita::ColorScheme::DEFAULT
    end

    private

    def apply_active_account
      active_account.then do |account|
        session.token = account&.token
        session.token_secret = account&.token_secret
      end
    end

    def store_account(token)
      Models::Account.new(token: token['token'], token_secret: token['token_secret']).tap do |account|
        account.permissions = token['permissions']
        account.id = token['nsid']
        account.username = token['username']
        account.fullname = token['fullname']
        account.active = true

        config.add_account(account)
        apply_active_account
        main_view&.account_changed
      end
    end

    # Sets, groups and tags belong to whichever account is active, so switching
    # or revoking one has to drop all of them.
    def invalidate_remote_data
      model.photosets = model.photosets.select(&:local?)
      model.groups = []
      model.remove_remote_tags
      @tags_fetched = false
    end
  end
end
