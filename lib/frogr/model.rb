# frozen_string_literal: true

require 'json'
require 'gtk4'

require_relative 'models/group'
require_relative 'models/photo_set'
require_relative 'models/picture'

module Frogr
  # The open document: the pictures queued for upload, plus the sets, groups
  # and tags known about the account.
  #
  # Pictures live in a Gio::ListStore because that is what the main view's
  # GridView consumes directly; everything else is a plain Ruby array.
  #
  # Tags come from two places — fetched from Flickr, and typed by the user —
  # and `tags` is the sorted union, exactly as in the C version.
  class Model
    attr_reader :pictures_store, :photosets, :groups
    attr_accessor :on_changed

    def initialize
      @pictures_store = Gio::ListStore.new(Models::Picture)
      @photosets = []
      @groups = []
      @remote_tags = []
      @local_tags = []
      @on_changed = nil
    end

    # --- Pictures ---------------------------------------------------------

    def pictures = (0...pictures_store.n_items).map { |i| pictures_store.get_item(i) }

    def n_pictures = pictures_store.n_items

    def add_picture(picture)
      pictures_store.append(picture)
      notify_changed
    end

    def remove_picture(picture)
      position_of(picture).then { |position| pictures_store.remove(position) if position }
      notify_changed
    end

    def remove_all_pictures
      pictures_store.remove_all
      notify_changed
    end

    def position_of(picture) = pictures.index { |item| item.equal?(picture) }

    # Reorders the store in place. The GridView is bound straight to the store,
    # so re-appending in the new order is what makes the view follow.
    def sort_pictures(criteria, reversed:)
      pictures.then do |current|
        (criteria == :as_loaded ? current : current.sort_by { |p| p.sort_key(criteria) })
          .then { |sorted| reversed ? sorted.reverse : sorted }
          .then do |sorted|
            pictures_store.remove_all
            sorted.each { |picture| pictures_store.append(picture) }
          end
      end

      notify_changed
    end

    # --- Photosets --------------------------------------------------------

    # Replaces the sets fetched from Flickr while keeping the ones the user
    # created locally and has not uploaded yet.
    def remote_photosets=(sets)
      @photosets = sets + @photosets.select(&:local?)
      notify_changed
    end

    def add_local_photoset(set)
      @photosets << set unless @photosets.any? { |existing| existing.key == set.key }
      notify_changed
    end

    def photosets=(sets)
      @photosets = sets.to_a
      notify_changed
    end

    def n_photosets = photosets.length

    def photoset_by_id(id) = photosets.find { |set| set.id == id }

    def photoset_by_key(key) = photosets.find { |set| set.key == key }

    # --- Groups -----------------------------------------------------------

    def groups=(groups)
      @groups = groups.to_a
      notify_changed
    end

    def n_groups = groups.length

    def group_by_id(id) = groups.find { |group| group.id == id }

    # --- Tags -------------------------------------------------------------

    def remote_tags=(tags)
      @remote_tags = tags.to_a
      notify_changed
    end

    def remove_remote_tags
      @remote_tags = []
    end

    def add_local_tags_from_string(string)
      Models::Picture.split_tags(string).then do |new_tags|
        (new_tags - @local_tags).then do |added|
          unless added.empty?
            @local_tags = (@local_tags + added).sort
            notify_changed
          end
        end
      end
    end

    def tags = (@remote_tags + @local_tags).uniq.sort

    def n_tags = tags.length

    def n_local_tags = @local_tags.length

    # --- Project files ----------------------------------------------------
    #
    # Same JSON shape as the C version's json-glib output, so .frogr projects
    # move between the two implementations.

    def to_h
      {
        'pictures' => pictures.map(&:to_h),
        'photosets' => photosets.map(&:to_h),
        'groups' => groups.map(&:to_h),
        'tags' => tags
      }
    end

    def save_to_file(path)
      File.write(path, JSON.pretty_generate(to_h))
      true
    rescue SystemCallError => e
      warn "frogr: could not save project: #{e.message}"
      false
    end

    # Sets and groups are restored first because pictures reference them by id.
    def load_from_file(path)
      JSON.parse(File.read(path)).then do |data|
        @photosets = data.fetch('photosets', []).map { |hash| Models::PhotoSet.from_h(hash) }
        @groups = data.fetch('groups', []).map { |hash| Models::Group.from_h(hash) }
        @local_tags = data.fetch('tags', []).map(&:to_s).sort

        photosets.to_h { |set| [set.key, set] }.then do |sets_by_key|
          groups.to_h { |group| [group.id, group] }.then do |groups_by_id|
            pictures_store.remove_all
            data.fetch('pictures', []).each do |hash|
              pictures_store.append(
                Models::Picture.from_h(hash, photosets_by_key: sets_by_key, groups_by_id: groups_by_id)
              )
            end
          end
        end
      end

      notify_changed
      true
    rescue JSON::ParserError, SystemCallError => e
      warn "frogr: could not open project: #{e.message}"
      false
    end

    def notify_changed
      on_changed&.call
    end
  end
end
