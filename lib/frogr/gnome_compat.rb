# frozen_string_literal: true

require 'gtk4'

module Frogr
  # Workarounds for ruby-gnome binding bugs, documented in FINDINGS.md.
  #
  # These are temporary. Everything here exists because a GVariant-typed
  # property setter in the bindings casts its argument to a GVariant* without
  # checking the type, so handing it an ordinary Ruby value either segfaults the
  # interpreter or is silently discarded. Neither is something calling code can
  # defend against, so the repair belongs at the binding boundary rather than
  # scattered across every call site.
  #
  # Delete this file and its require once the bindings convert on assignment.
  # `test/run_tests.rb` probes the unpatched behaviour in a subprocess and says
  # so when the shims stop being necessary.
  module GnomeCompat
    # The gem version these were verified against. On anything newer, re-run the
    # reproductions in FINDINGS.md before assuming they are still needed.
    VERIFIED_AGAINST = '4.3.8'

    module_function

    # Converts a Ruby value to the GVariant the setters actually require,
    # passing existing GVariants through untouched.
    def to_variant(value)
      value.is_a?(GLib::Variant) ? value : GLib::Variant.new(value)
    end

    def apply!
      patch_simple_action_state!
      patch_actionable_target!
    end

    # FINDINGS.md #1 - `action.state = <ruby value>` segfaults for booleans,
    # integers and symbols, and is silently ignored for strings.
    #
    # `change_state` is the same operation done safely: it validates against the
    # action's declared state type and accepts plain Ruby values as well as
    # GVariants. Routing the setter through it keeps `action.state = value`
    # readable at the call sites while removing the crash.
    def patch_simple_action_state!
      return if Gio::SimpleAction.method_defined?(:state_without_frogr_compat=)

      Gio::SimpleAction.class_eval do
        alias_method :state_without_frogr_compat=, :state=

        def state=(value)
          change_state(value)
        end
      end
    end

    # FINDINGS.md #2 - `widget.action_target = <ruby value>` sets nil without
    # any warning. Here the fix is just to convert before handing it over.
    #
    # Gtk::Actionable is an interface, and patching the interface module does
    # not reach the classes that already included it, so the implementors this
    # app uses are patched individually.
    def patch_actionable_target!
      [Gtk::Button, Gtk::ToggleButton, Gtk::CheckButton, Gtk::MenuButton].each do |klass|
        next unless klass.method_defined?(:action_target=)
        next if klass.method_defined?(:action_target_without_frogr_compat=)

        klass.class_eval do
          alias_method :action_target_without_frogr_compat=, :action_target=

          def action_target=(value)
            send(:action_target_without_frogr_compat=,
                 value.nil? ? nil : Frogr::GnomeCompat.to_variant(value))
          end
        end
      end
    end
  end
end

Frogr::GnomeCompat.apply!
