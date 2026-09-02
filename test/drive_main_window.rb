#!/usr/bin/env ruby
# frozen_string_literal: true

# Drives the real UI headlessly: loads pictures, works the menu actions, opens
# the dialogs and edits through them, then checks the model actually changed.
#
#   nix develop --command ruby test/drive_main_window.rb
#
# Screenshots land in tmp/shots - look at them, they show what assertions miss.

require 'tmpdir'

ENV['XDG_CONFIG_HOME'] = Dir.mktmpdir('frogr-test-config')
ENV['FROGR_DATA_DIR'] ||= File.expand_path('../data', __dir__)

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'frogr/app'
require_relative 'gtk_driver'

PICTURES = File.expand_path('fixtures', __dir__)

GtkDriver.drive(Frogr::App.new, shots: File.expand_path('../tmp/shots', __dir__)) do |d, app|
  d.window { app.main_view.window }

  view = -> { app.main_view }
  model = -> { app.controller.model }

  d.step('the authorisation prompt opens at startup') do
    d.check('prompt is showing') { view.call.window.visible_dialog }
    view.call.window.visible_dialog&.close
  end

  d.step('empty state') do
    d.check('empty page is showing') { view.call.main_stack.visible_child_name == 'empty' }
    d.shot('01-empty')
  end

  d.step('load the fixtures') do
    app.controller.load_pictures(Dir["#{PICTURES}/*.jpg"].sort.map { |p| Frogr::Util.path_to_uri(p) })
  end

  d.step('the grid fills in') do
    d.check('all fixtures loaded') { model.call.n_pictures == Dir["#{PICTURES}/*.jpg"].length }
    d.check('every picture has a thumbnail') { model.call.pictures.all?(&:pixbuf) }
    d.check('grid page is showing') { view.call.main_stack.visible_child_name == 'pictures' }
    d.check('EXIF keywords became tags') do
      model.call.pictures.flat_map(&:tags).include?('eiffel tower')
    end
    d.shot('02-grid')
  end

  # Menu actions go through GAction, which unwraps GVariants differently in each
  # direction - so they are worth driving by name rather than trusting.
  d.step('sort by title through the menu action') do
    view.call.window.lookup_action('sort-by').activate(GLib::Variant.new('by_title'))
    # The radio state has to follow, or the menu shows the wrong item ticked.
    d.check('action state followed') { view.call.window.lookup_action('sort-by').state == 'by_title' }
    d.check('sorted ascending by title') do
      model.call.pictures.map(&:title) == model.call.pictures.map(&:title).sort
    end
  end

  d.step('reverse the order through the menu action') do
    view.call.window.lookup_action('sort-in-reverse-order').activate(nil)
    d.check('action state flipped') { view.call.window.lookup_action('sort-in-reverse-order').state == true }
    d.check('order reversed') do
      model.call.pictures.map(&:title) == model.call.pictures.map(&:title).sort.reverse
    end
  end

  d.step('toggle tooltips through the menu action') do
    view.call.window.lookup_action('enable-tooltips').activate(nil)
    d.check('action state flipped') { view.call.window.lookup_action('enable-tooltips').state == false }
    d.check('preference followed') { app.controller.config.mainview_enable_tooltips == false }
  end

  d.step('edit details across a multi-selection') do
    view.call.selection.unselect_all
    view.call.selection.select_item(0, false)
    view.call.selection.select_item(1, false)
    view.call.send(:edit_details)
  end

  d.step('the details dialog opened') do
    d.check('dialog is showing') { view.call.window.visible_dialog }
    d.shot('03-details')
  end

  d.step('type into it and save') do
    ObjectSpace.each_object(Frogr::Ui::DetailsDialog).first.then do |dialog|
      dialog.send(:title_row).text = 'Renamed'
      dialog.send(:tag_entry).text = 'holiday "san francisco"'
      dialog.send(:save_button).activate
    end
  end

  d.step('the edit reached the model') do
    model.call.pictures.first(2).then do |edited|
      d.check('both titles changed') { edited.all? { |p| p.title == 'Renamed' } }
      d.check('quoted tag stayed whole') { edited.all? { |p| p.tags == ['holiday', 'san francisco'] } }
    end
    d.check('dialog closed') { view.call.window.visible_dialog.nil? }
  end

  d.step('remove the selection') do
    model.call.n_pictures.then do |before|
      app.controller.remove_pictures(view.call.send(:selected_pictures))
      d.check('two fewer pictures') { model.call.n_pictures == before - 2 }
    end
  end

  d.step('uploading without an account is refused, not attempted') do
    app.controller.upload_pictures(model.call.pictures)
    d.check('state stayed idle') { app.controller.state == :idle }
  end

  d.step('final look') do
    d.shot('04-final')
  end
end
