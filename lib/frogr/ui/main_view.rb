# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

require_relative '../util'
require_relative 'about_dialog'
require_relative 'add_tags_dialog'
require_relative 'add_to_group_dialog'
require_relative 'add_to_set_dialog'
require_relative 'auth_dialog'
require_relative 'create_new_set_dialog'
require_relative 'details_dialog'
require_relative 'progress_dialog'
require_relative 'settings_dialog'

module Frogr
  module Ui
    # The main window: a grid of the pictures queued for upload, a header bar
    # of actions, and a status bar showing the account and its quota.
    #
    # The C version drove this from three GtkBuilder files and a GtkIconView.
    # Here the widget tree is the `build` method, and the grid is a GTK4
    # GridView bound straight to the model's Gio::ListStore, so adding or
    # removing a picture updates the view with no explicit refresh.
    class MainView
      THUMB_SIZE = 136

      # action name => [accelerator, whether it needs a selection]
      WINDOW_ACTIONS = {
        'open-project' => ['<Primary>o', false],
        'save-project' => ['<Primary>s', false],
        'save-project-as' => ['<Primary><Shift>s', false],
        'add-pictures' => ['<Primary>l', false],
        'remove-pictures' => ['Delete', true],
        'edit-details' => ['<Primary>e', true],
        'add-tags' => ['<Primary>t', true],
        'add-to-group' => ['<Primary>g', true],
        'add-to-set' => ['<Primary><Shift>a', true],
        'add-to-new-set' => ['<Primary>n', true],
        'open-in-external-viewer' => ['<Primary>m', true],
        'upload-all' => ['<Primary>u', false]
      }.freeze

      def initialize(app:, controller:)
        @app = app
        @controller = controller
        @controller.main_view = self
      end

      def build
        window.tap do |win|
          win.content = toast_overlay

          toast_overlay.tap do |overlay|
            overlay.child = toolbar_view

            toolbar_view.tap do |view|
              view.add_top_bar(header_bar)
              view.add_bottom_bar(status_bar)
              view.content = main_stack

              header_bar.tap do |bar|
                bar.title_widget = window_title

                bar.pack_start(open_button)
                bar.pack_start(add_button)
                bar.pack_start(remove_button)
                bar.pack_start(upload_button)

                bar.pack_end(menu_button)
                bar.pack_end(save_button)
              end

              status_bar.tap do |box|
                box.append(status_label)
                box.append(quota_label)
              end

              main_stack.tap do |stack|
                stack.add_named(empty_state, 'empty')
                stack.add_named(scrolled_window, 'pictures')

                empty_state.tap do |page|
                  page.child = empty_state_button

                  empty_state_button.signal_connect('clicked') { add_pictures }
                end

                scrolled_window.child = grid_view

                grid_view.tap do |view|
                  view.model = selection
                  view.factory = picture_factory
                  view.signal_connect('activate') { edit_details }
                  view.add_controller(context_gesture)
                end
              end
            end
          end

          context_gesture.signal_connect('pressed') do |gesture, _, x, y|
            show_context_menu(gesture, x, y)
          end

          win.add_controller(drop_target)

          drop_target.signal_connect('drop') do |_, value, _, _|
            load_dropped_files(value)
          end

          win.signal_connect('close-request') do
            @controller.cancel_ongoing_requests
            @controller.config.save_all
            false
          end
        end

        register_actions
        model.on_changed = -> { update_ui }
        update_ui
        maybe_prompt_for_authorization

        window
      end

      # --- Called by the controller ----------------------------------------

      def show_progress(title, description)
        progress_dialog.tap do |dialog|
          dialog.title = title
          dialog.description = description
          dialog.present(window)
        end
      end

      def set_progress(fraction, status, description)
        progress_dialog.update(fraction: fraction, status: status, description: description)
      end

      def hide_progress
        progress_dialog.close
      end

      def set_status_text(text)
        status_label.label = text.to_s
      end

      def report_error(message)
        toast_overlay.add_toast(Adwaita::Toast.new(message.to_s))
      end

      def account_changed
        populate_accounts_menu
        update_ui
      end

      def project_path_changed
        update_ui
      end

      private

      def model = @controller.model

      def config = @controller.config

      # --- Actions ---------------------------------------------------------

      def register_actions
        WINDOW_ACTIONS.each_key do |name|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect('activate') { activate_window_action(name) }
            window.add_action(action)
          end
        end

        WINDOW_ACTIONS.each do |name, (accel, _)|
          @app.set_accels_for_action("win.#{name}", [accel])
        end

        sort_action.tap { |action| window.add_action(action) }
        reverse_action.tap { |action| window.add_action(action) }
        tooltips_action.tap { |action| window.add_action(action) }

        %w[authorize preferences help about quit].each do |name|
          Gio::SimpleAction.new(name).tap do |action|
            action.signal_connect('activate') { activate_app_action(name) }
            @app.add_action(action)
          end
        end

        @app.add_action(login_action)
        @app.set_accels_for_action('app.quit', ['<Primary>q'])
        populate_accounts_menu
      end

      def activate_window_action(name)
        case name
        when 'open-project' then open_project
        when 'save-project' then save_project
        when 'save-project-as' then save_project(force_prompt: true)
        when 'add-pictures' then add_pictures
        when 'remove-pictures' then @controller.remove_pictures(selected_pictures)
        when 'edit-details' then edit_details
        when 'add-tags' then add_tags
        when 'add-to-group' then add_to_group
        when 'add-to-set' then add_to_set
        when 'add-to-new-set' then add_to_new_set
        when 'open-in-external-viewer' then open_in_external_viewer
        when 'upload-all' then @controller.upload_pictures(pictures_to_upload)
        end
      end

      def activate_app_action(name)
        case name
        when 'authorize' then show_auth_dialog
        when 'preferences' then show_settings_dialog
        when 'help' then Util.open_uri('help:frogr', parent: window)
        when 'about' then AboutDialog.new(parent: window).build.present
        when 'quit' then window.close
        end
      end

      # --- Operations on the selection --------------------------------------

      def selected_pictures
        (0...selection.n_items).select { |i| selection.selected?(i) }
                               .map { |i| selection.get_item(i) }
      end

      # "Upload" means the whole queue, matching the action's name upstream.
      def pictures_to_upload = model.pictures

      def edit_details
        with_selection do |pictures|
          DetailsDialog.new(pictures: pictures, model: model, parent: window,
                            on_saved: -> { update_ui }).build.present(window)
        end
      end

      def add_tags
        with_selection do |pictures|
          AddTagsDialog.new(model: model, parent: window,
                            on_added: lambda { |tags|
                              pictures.each { |picture| picture.add_tags(tags) }
                              model.add_local_tags_from_string(tags)
                              update_ui
                            }).build.present(window)
        end
      end

      def add_to_set
        with_selection do |pictures|
          AddToSetDialog.new(controller: @controller, pictures: pictures, parent: window,
                             on_added: -> { update_ui }).build.present(window)
        end
      end

      def add_to_new_set
        with_selection do |pictures|
          CreateNewSetDialog.new(pictures: pictures, model: model, parent: window,
                                 on_created: -> { update_ui }).build.present(window)
        end
      end

      def add_to_group
        with_selection do |pictures|
          AddToGroupDialog.new(controller: @controller, pictures: pictures, parent: window,
                               on_added: -> { update_ui }).build.present(window)
        end
      end

      def open_in_external_viewer
        selected_pictures.each { |picture| Util.open_uri(picture.fileuri, parent: window) }
      end

      def with_selection
        selected_pictures.then do |pictures|
          if pictures.empty?
            report_error('Select one or more pictures first.')
          else
            yield pictures
          end
        end
      end

      # --- File and project dialogs ------------------------------------------

      def add_pictures
        Gtk::FileDialog.new.tap do |dialog|
          dialog.title = 'Add Pictures'
          dialog.filters = Gio::ListStore.new(Gtk::FileFilter).tap { |list| list.append(media_filter) }
          dialog.default_filter = media_filter

          dialog.open_multiple(window, nil) do |source, result|
            files_from(source, result) { |uris| @controller.load_pictures(uris) }
          end
        end
      end

      def open_project
        Gtk::FileDialog.new.tap do |dialog|
          dialog.title = 'Open Project'
          dialog.filters = Gio::ListStore.new(Gtk::FileFilter).tap { |list| list.append(project_filter) }

          dialog.open(window, nil) do |source, result|
            file_from(source, result) { |path| @controller.open_project(path) }
          end
        end
      end

      def save_project(force_prompt: false)
        if @controller.project_path && !force_prompt
          @controller.save_project
          set_status_text("Saved #{File.basename(@controller.project_path)}")
        else
          prompt_for_project_path
        end
      end

      def prompt_for_project_path
        Gtk::FileDialog.new.tap do |dialog|
          dialog.title = 'Save Project'
          dialog.filters = Gio::ListStore.new(Gtk::FileFilter).tap { |list| list.append(project_filter) }

          dialog.save(window, nil) do |source, result|
            file_from(source, result) do |path|
              @controller.save_project(path.end_with?('.frogr') ? path : "#{path}.frogr")
            end
          end
        end
      end

      # GTK4's async file dialogs raise rather than yielding nil when the user
      # cancels, so every caller funnels through these two.
      def file_from(source, result)
        source.open_finish(result).then { |file| yield file.path if file }
      rescue StandardError
        nil
      end

      def files_from(source, result)
        source.open_multiple_finish(result).then do |files|
          (0...files.n_items).map { |i| Util.path_to_uri(files.get_item(i).path) }
                             .then { |uris| yield uris unless uris.empty? }
        end
      rescue StandardError
        nil
      end

      def load_dropped_files(value)
        Array(value).filter_map { |file| file.path if file.respond_to?(:path) }
                    .select { |path| Util.supported?(path) }
                    .map { |path| Util.path_to_uri(path) }
                    .then do |uris|
          @controller.load_pictures(uris) unless uris.empty?
          !uris.empty?
        end
      end

      # --- Authorisation -----------------------------------------------------

      def show_auth_dialog
        AuthDialog.new(controller: @controller, parent: window,
                       on_authorized: -> { account_changed }).build.present(window)
      end

      def show_settings_dialog
        SettingsDialog.new(controller: @controller, parent: window,
                           on_closed: -> { update_ui }).build.present(window)
      end

      # Upstream opens the authorisation dialog on idle at startup when there
      # is no account yet, so the app is never sitting there unable to upload
      # without saying why.
      def maybe_prompt_for_authorization
        GLib::Idle.add do
          show_auth_dialog unless @controller.authorized?
          false
        end
      end

      # --- Menus -------------------------------------------------------------

      # The accounts submenu is rebuilt whenever the account list changes, so
      # it is the one menu section not defined once up front.
      def populate_accounts_menu
        accounts_menu.remove_all

        @controller.accounts.each do |account|
          accounts_menu.append(account.display_name, "app.login-as::#{account.username}")
        end

        login_action.state = GLib::Variant.new(@controller.active_account&.username.to_s)
      end

      def show_context_menu(gesture, x, y)
        # Right-clicking outside the selection should act on what was clicked,
        # which means selecting it before the menu opens.
        gesture.widget.pick(x, y, :default).then do |picked|
          context_menu_popover.tap do |popover|
            popover.pointing_to = Gdk::Rectangle.new(x.to_i, y.to_i, 1, 1)
            popover.popup
          end if picked
        end
      end

      # --- State refresh ------------------------------------------------------

      def update_ui
        main_stack.visible_child_name = model.n_pictures.zero? ? 'empty' : 'pictures'

        window_title.tap do |title|
          title.title = @controller.project_path ? File.basename(@controller.project_path) : 'frogr'
          title.subtitle = format('%d picture(s)', model.n_pictures)
        end

        [remove_button, upload_button, save_button].each do |button|
          button.sensitive = !model.n_pictures.zero? && !@controller.busy?
        end

        grid_view.tooltip_text = nil unless config.mainview_enable_tooltips

        update_account_labels
      end

      def update_account_labels
        @controller.active_account.then do |account|
          if account.nil?
            status_label.label = 'Not connected'
            quota_label.label = ''
          else
            status_label.label = "Connected as #{account.display_name}"
            quota_label.label = account.has_extra_info? ? quota_text(account) : ''
          end
        end
      end

      def quota_text(account)
        format('%s remaining%s',
               Util.format_filesize(account.remaining_bandwidth),
               account.pro? ? ' (Pro)' : '')
      end

      public

      # ==== Widgets ==========================================================

      # Adwaita::ApplicationWindow rather than the Gtk one: it is what lets
      # Adwaita::Dialog present *inside* the window instead of spawning a
      # separate toplevel. (The bindings' older type-interface problem with
      # this class is gone as of ruby-gnome 4.3.8 — verified against the real
      # widget tree, actions and dialogs this app uses.)
      def window
        @window ||= Adwaita::ApplicationWindow.new(@app).tap do |win|
          win.title = 'frogr'
          win.set_default_size(800, 600)
          win.icon_name = 'org.gnome.frogr'
        end
      end

      def toast_overlay = @toast_overlay ||= Adwaita::ToastOverlay.new
      def toolbar_view = @toolbar_view ||= Adwaita::ToolbarView.new
      def header_bar = @header_bar ||= Adwaita::HeaderBar.new
      def window_title = @window_title ||= Adwaita::WindowTitle.new('frogr', '')

      def open_button = @open_button ||= header_button('document-open-symbolic', 'Open Existing Project', 'win.open-project')
      def add_button = @add_button ||= header_button('list-add-symbolic', 'Add Pictures', 'win.add-pictures')
      def remove_button = @remove_button ||= header_button('list-remove-symbolic', 'Remove Pictures', 'win.remove-pictures')
      def upload_button = @upload_button ||= header_button('document-send-symbolic', 'Upload', 'win.upload-all')
      def save_button = @save_button ||= header_button('document-save-symbolic', 'Save Current Project', 'win.save-project')

      def header_button(icon, tooltip, action)
        Gtk::Button.new.tap do |button|
          button.icon_name = icon
          button.tooltip_text = tooltip
          button.action_name = action
        end
      end

      def menu_button
        @menu_button ||= Gtk::MenuButton.new.tap do |button|
          button.icon_name = 'open-menu-symbolic'
          button.tooltip_text = 'Main Menu'
          button.menu_model = main_menu
        end
      end

      def status_bar
        @status_bar ||= Gtk::Box.new(:horizontal, 12).tap do |box|
          box.margin_top = 4
          box.margin_bottom = 4
          box.margin_start = 12
          box.margin_end = 12
        end
      end

      def status_label
        @status_label ||= Gtk::Label.new.tap do |label|
          label.xalign = 0
          label.hexpand = true
          label.ellipsize = :end
          label.add_css_class('dim-label')
        end
      end

      def quota_label
        @quota_label ||= Gtk::Label.new.tap do |label|
          label.xalign = 1
          label.add_css_class('dim-label')
        end
      end

      def main_stack = @main_stack ||= Gtk::Stack.new

      def empty_state
        @empty_state ||= Adwaita::StatusPage.new.tap do |page|
          page.icon_name = 'org.gnome.frogr-symbolic'
          page.title = 'Nothing to Upload'
          page.description = 'Add pictures and videos to queue them for Flickr.'
        end
      end

      def empty_state_button
        @empty_state_button ||= Gtk::Button.new.tap do |button|
          button.label = 'Add Pictures'
          button.halign = :center
          button.add_css_class('suggested-action')
          button.add_css_class('pill')
        end
      end

      def scrolled_window
        @scrolled_window ||= Gtk::ScrolledWindow.new.tap do |window|
          window.hexpand = true
          window.vexpand = true
        end
      end

      def grid_view
        @grid_view ||= Gtk::GridView.new.tap do |view|
          view.max_columns = 16
          view.min_columns = 1
          view.margin_top = 6
          view.margin_bottom = 6
          view.margin_start = 6
          view.margin_end = 6
        end
      end

      def selection = @selection ||= Gtk::MultiSelection.new(model.pictures_store)

      # Each cell is the thumbnail with the title underneath, sized so the grid
      # keeps its columns aligned whatever the pictures' aspect ratios are.
      def picture_factory
        @picture_factory ||= Gtk::SignalListItemFactory.new.tap do |factory|
          factory.signal_connect('setup') do |_, item|
            item.child = Gtk::Box.new(:vertical, 4).tap do |box|
              box.margin_top = 4
              box.margin_bottom = 4
              box.margin_start = 4
              box.margin_end = 4
              box.width_request = THUMB_SIZE + 16

              box.append(Gtk::Picture.new.tap do |picture|
                picture.width_request = THUMB_SIZE
                picture.height_request = THUMB_SIZE
                picture.content_fit = :contain
              end)

              box.append(Gtk::Label.new.tap do |label|
                label.ellipsize = :middle
                label.max_width_chars = 18
                label.add_css_class('caption')
              end)
            end
          end

          factory.signal_connect('bind') do |_, item|
            item.item.then do |picture|
              item.child.first_child.tap do |image|
                image.paintable = picture.pixbuf && Gdk::Texture.new(picture.pixbuf)
                image.next_sibling.label = picture.title.to_s
                image.parent.tooltip_text = tooltip_for(picture) if config.mainview_enable_tooltips
              end
            end
          end
        end
      end

      def tooltip_for(picture)
        [picture.title,
         picture.basename,
         Util.format_filesize(picture.filesize),
         picture.tags.empty? ? nil : "Tags: #{picture.tags_string}"].compact.join("\n")
      end

      def context_gesture
        @context_gesture ||= Gtk::GestureClick.new.tap { |gesture| gesture.button = 3 }
      end

      def context_menu_popover
        @context_menu_popover ||= Gtk::PopoverMenu.new(:model, context_menu).tap do |popover|
          popover.parent = grid_view
          popover.has_arrow = false
        end
      end

      def drop_target
        @drop_target ||= Gtk::DropTarget.new(Gdk::FileList.gtype, :copy)
      end

      def media_filter
        @media_filter ||= Gtk::FileFilter.new.tap do |filter|
          filter.name = 'Pictures and Videos'
          (Util::IMAGE_EXTENSIONS + Util::VIDEO_EXTENSIONS).each do |extension|
            filter.add_pattern("*#{extension}")
            filter.add_pattern("*#{extension.upcase}")
          end
        end
      end

      def project_filter
        @project_filter ||= Gtk::FileFilter.new.tap do |filter|
          filter.name = 'frogr Projects'
          filter.add_pattern('*.frogr')
        end
      end

      def progress_dialog = @progress_dialog ||= ProgressDialog.new(on_cancel: -> { @controller.cancel_ongoing_requests }).build

      # --- Menu models -------------------------------------------------------

      def main_menu
        @main_menu ||= Gio::Menu.new.tap do |menu|
          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append('_Authorize frogr…', 'app.authorize')
            section.append_submenu('Login _As', accounts_menu)
          end)

          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append('_Save Project', 'win.save-project')
            section.append('Save Project _As…', 'win.save-project-as')
          end)

          menu.append_section(nil, picture_actions_menu)

          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append_submenu('_View', view_menu)
          end)

          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append('_Preferences', 'app.preferences')
            section.append('_Help', 'app.help')
            section.append('_About frogr', 'app.about')
            section.append('_Quit', 'app.quit')
          end)
        end
      end

      def picture_actions_menu
        @picture_actions_menu ||= Gio::Menu.new.tap do |menu|
          menu.append('Edit _Details…', 'win.edit-details')
          menu.append('Add _Tags…', 'win.add-tags')
          menu.append('Add to _Group…', 'win.add-to-group')
          menu.append('Add to _Set…', 'win.add-to-set')
          menu.append('Add to New Se_t…', 'win.add-to-new-set')
          menu.append('Open in External _Viewer', 'win.open-in-external-viewer')
        end
      end

      def view_menu
        @view_menu ||= Gio::Menu.new.tap do |menu|
          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append('As _Loaded', 'win.sort-by::as_loaded')
            section.append('By _Title', 'win.sort-by::by_title')
            section.append('By _Date', 'win.sort-by::by_date')
            section.append('By _Size', 'win.sort-by::by_size')
          end)

          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append('_Reversed Order', 'win.sort-in-reverse-order')
            section.append('Enable Tooltips', 'win.enable-tooltips')
          end)
        end
      end

      def context_menu
        @context_menu ||= Gio::Menu.new.tap do |menu|
          menu.append_section(nil, picture_actions_menu)

          menu.append_section(nil, Gio::Menu.new.tap do |section|
            section.append('_Remove', 'win.remove-pictures')
          end)
        end
      end

      def accounts_menu = @accounts_menu ||= Gio::Menu.new

      # --- Stateful actions ---------------------------------------------------
      #
      # The bindings unwrap GVariants on the way out but not on the way in:
      # `action.state` and the `activate` parameter arrive as plain Ruby values
      # (true, 'by_title'), while assigning state needs a GLib::Variant - a
      # plain assignment aborts the process rather than raising.

      def sort_action
        @sort_action ||= Gio::SimpleAction.new(
          'sort-by', GLib::VariantType.new('s'),
          GLib::Variant.new(config.mainview_sorting_criteria.to_s)
        ).tap do |action|
          action.signal_connect('activate') do |_, parameter|
            action.state = GLib::Variant.new(parameter)
            config.mainview_sorting_criteria = parameter.to_sym
            config.save_settings
            @controller.reorder_pictures
          end
        end
      end

      def reverse_action
        @reverse_action ||= Gio::SimpleAction.new(
          'sort-in-reverse-order', nil, GLib::Variant.new(config.mainview_sorting_reversed)
        ).tap do |action|
          action.signal_connect('activate') do
            (!action.state).then do |value|
              action.state = GLib::Variant.new(value)
              config.mainview_sorting_reversed = value
              config.save_settings
              @controller.reorder_pictures
            end
          end
        end
      end

      def tooltips_action
        @tooltips_action ||= Gio::SimpleAction.new(
          'enable-tooltips', nil, GLib::Variant.new(config.mainview_enable_tooltips)
        ).tap do |action|
          action.signal_connect('activate') do
            (!action.state).then do |value|
              action.state = GLib::Variant.new(value)
              config.mainview_enable_tooltips = value
              config.save_settings
              update_ui
            end
          end
        end
      end

      def login_action
        @login_action ||= Gio::SimpleAction.new(
          'login-as', GLib::VariantType.new('s'), GLib::Variant.new('')
        ).tap do |action|
          action.signal_connect('activate') do |_, parameter|
            action.state = GLib::Variant.new(parameter)
            @controller.active_account = parameter
          end
        end
      end
    end
  end
end
