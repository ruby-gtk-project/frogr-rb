# frozen_string_literal: true

require 'adwaita'
require 'gtk4'

module Frogr
  module Ui
    # Walks the user through Flickr's OAuth flow: open the authorisation page
    # in a browser, then paste the verification code back here.
    class AuthDialog
      def initialize(controller:, parent:, on_authorized:)
        @controller = controller
        @parent = parent
        @on_authorized = on_authorized
      end

      def build
        dialog.tap do |dlg|
          dlg.child = toolbar_view

          toolbar_view.tap do |view|
            view.add_top_bar(header_bar)
            view.content = box

            header_bar.tap do |bar|
              bar.pack_start(cancel_button)
              bar.pack_end(confirm_button)

              cancel_button.signal_connect('clicked') { dlg.close }
              confirm_button.signal_connect('clicked') { confirm(dlg) }
            end

            box.tap do |b|
              b.append(explanation_label)
              b.append(authorize_button)
              b.append(code_row_box)
              b.append(error_label)

              authorize_button.signal_connect('clicked') { open_authorization_page }

              code_row_box.tap do |row|
                row.append(code_label)
                row.append(code_entry)

                code_entry.tap do |entry|
                  entry.signal_connect('changed') { update_sensitivity }
                  entry.signal_connect('activate') { confirm(dlg) }
                end
              end
            end
          end
        end

        update_sensitivity
        dialog
      end

      private

      def open_authorization_page
        authorize_button.sensitive = false

        @controller.open_auth_url(
          on_ready: ->(_) { authorize_button.sensitive = true },
          on_error: lambda { |message|
            authorize_button.sensitive = true
            show_error(message)
          }
        )
      end

      def confirm(dlg)
        code_entry.text.strip.then do |code|
          next if code.empty?

          confirm_button.sensitive = false
          error_label.visible = false

          @controller.complete_auth(
            code,
            on_success: lambda { |_|
              @on_authorized.call
              dlg.close
            },
            on_error: lambda { |message|
              confirm_button.sensitive = true
              show_error(message)
            }
          )
        end
      end

      def show_error(message)
        error_label.label = message.to_s
        error_label.visible = true
      end

      def update_sensitivity
        confirm_button.sensitive = !code_entry.text.strip.empty?
      end

      def dialog
        @dialog ||= Adwaita::Dialog.new.tap do |dlg|
          dlg.title = 'Authorize frogr'
          dlg.content_width = 460
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

      def confirm_button
        @confirm_button ||= Gtk::Button.new.tap do |button|
          button.label = '_Close'
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

      def explanation_label
        @explanation_label ||= Gtk::Label.new.tap do |label|
          label.label = 'frogr needs permission to upload to your Flickr account. ' \
                        'Authorize it in your browser, then paste the verification code below.'
          label.wrap = true
          label.max_width_chars = 46
          label.xalign = 0
        end
      end

      def authorize_button
        @authorize_button ||= Gtk::Button.new.tap do |button|
          button.label = 'Authorize in Browser'
          button.halign = :center
          button.add_css_class('suggested-action')
        end
      end

      def code_row_box = @code_row_box ||= Gtk::Box.new(:horizontal, 12)

      def code_label
        @code_label ||= Gtk::Label.new('Enter verification code:').tap { |label| label.xalign = 0 }
      end

      def code_entry
        @code_entry ||= Gtk::Entry.new.tap do |entry|
          entry.hexpand = true
          entry.placeholder_text = '123-456-789'
        end
      end

      def error_label
        @error_label ||= Gtk::Label.new.tap do |label|
          label.wrap = true
          label.max_width_chars = 46
          label.xalign = 0
          label.visible = false
          label.add_css_class('error')
        end
      end
    end
  end
end
