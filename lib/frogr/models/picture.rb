# frozen_string_literal: true

require 'gtk4'

module Frogr
  module Models
    # One picture (or video) queued for upload.
    #
    # This is a GLib::Object because Gio::ListStore — which backs the main
    # view's GridView — only accepts GObject-derived items. Everything else
    # about it is a plain Ruby attribute; the C original's GObject properties
    # existed only to get json-glib's automatic serialisation, which `to_h`
    # does explicitly here instead.
    class Picture < GLib::Object
      type_register

      TAG_DELIMITER = ' '

      attr_accessor :id, :title, :description, :public, :family, :friend,
                    :safety_level, :content_type, :license, :location,
                    :show_in_search, :send_location, :replace_date_posted,
                    :filesize, :datetime, :pixbuf, :error

      attr_reader :fileuri, :video, :tags, :photosets, :groups

      alias public? public
      alias family? family
      alias friend? friend
      alias video? video
      alias show_in_search? show_in_search
      alias send_location? send_location
      alias replace_date_posted? replace_date_posted

      def initialize(fileuri: '', title: '', public: true, family: false,
                     friend: false, video: false)
        super()
        @fileuri = fileuri.to_s
        @title = title.to_s
        @description = ''
        @public = public
        @family = family
        @friend = friend
        @video = video
        @safety_level = 1
        @content_type = 1
        @license = -1
        @show_in_search = true
        @send_location = false
        @replace_date_posted = false
        @filesize = 0
        @tags = []
        @photosets = []
        @groups = []
      end

      # The absolute path behind the URI, for everything that wants a filename
      # rather than a URI (file reads, EXIF, the external viewer).
      def path = @fileuri.start_with?('file://') ? Frogr::Util.uri_to_path(@fileuri) : @fileuri

      def basename = File.basename(path)

      # --- Tags -----------------------------------------------------------
      #
      # Flickr separates tags by spaces, so a multi-word tag has to be quoted.
      # The list is kept sorted and duplicate-free, matching the C behaviour.

      def tags=(string)
        @tags = []
        add_tags(string)
      end

      def add_tags(string)
        @tags = (@tags + Picture.split_tags(string)).uniq.sort
      end

      def remove_tags
        @tags = []
      end

      def tags_string = @tags.map { |t| t.include?(' ') ? "\"#{t}\"" : t }.join(TAG_DELIMITER)

      # Splits on whitespace but keeps quoted runs together, so
      # `holidays "san francisco"` yields two tags, not three.
      def self.split_tags(string)
        string.to_s.scan(/"([^"]+)"|(\S+)/).map { |quoted, bare| (quoted || bare).strip }
              .reject(&:empty?).uniq
      end

      # --- Sets and groups ------------------------------------------------

      def add_photoset(set)
        @photosets << set unless in_photoset?(set)
      end

      def remove_photosets
        @photosets = []
      end

      def in_photoset?(set) = @photosets.any? { |s| s.key == set.key }

      def photosets=(sets)
        @photosets = sets.to_a
      end

      def add_group(group)
        @groups << group unless in_group?(group)
      end

      def remove_groups
        @groups = []
      end

      def in_group?(group) = @groups.any? { |g| g.id == group.id }

      def groups=(groups)
        @groups = groups.to_a
      end

      # --- Sorting --------------------------------------------------------
      #
      # Mirrors frogr_picture_compare_by_property: the View menu sorts by
      # title, date or size, and falls back to title when the chosen field is
      # missing so the order stays stable.

      def sort_key(criteria)
        case criteria
        when :by_title then [title.downcase, basename.downcase]
        when :by_date then [datetime.to_s, title.downcase]
        when :by_size then [filesize.to_i, title.downcase]
        else [0, 0]
        end
      end

      # --- Serialisation --------------------------------------------------
      #
      # Member names match the C version's GObject property names so that
      # projects saved by upstream frogr open unchanged.

      def to_h
        {
          'id' => id,
          'fileuri' => fileuri,
          'title' => title,
          'description' => description,
          'tags-string' => tags_string,
          'is-public' => public,
          'is-family' => family,
          'is-friend' => friend,
          'safety-level' => safety_level,
          'content-type' => content_type,
          'license' => license,
          'location' => location&.to_h,
          'show-in-search' => show_in_search,
          'send-location' => send_location,
          'replace-date-posted' => replace_date_posted,
          'filesize' => filesize,
          'is-video' => video,
          'datetime' => datetime,
          'photosets' => photosets.map(&:key).compact,
          'groups' => groups.map(&:id).compact
        }
      end

      # `photosets` and `groups` serialise as id lists, so resolving them back
      # into objects needs the model's tables — hence the two lookup hashes.
      def self.from_h(hash, photosets_by_key: {}, groups_by_id: {})
        new(
          fileuri: hash['fileuri'].to_s,
          title: hash['title'].to_s,
          public: hash.fetch('is-public', true),
          family: hash.fetch('is-family', false),
          friend: hash.fetch('is-friend', false),
          video: hash.fetch('is-video', false)
        ).tap do |picture|
          picture.id = hash['id']
          picture.description = hash['description'].to_s
          picture.tags = hash['tags-string'].to_s
          picture.safety_level = hash.fetch('safety-level', 1).to_i
          picture.content_type = hash.fetch('content-type', 1).to_i
          picture.license = hash.fetch('license', -1).to_i
          picture.location = hash['location'] && Location.from_h(hash['location'])
          picture.show_in_search = hash.fetch('show-in-search', true)
          picture.send_location = hash.fetch('send-location', false)
          picture.replace_date_posted = hash.fetch('replace-date-posted', false)
          picture.filesize = hash.fetch('filesize', 0).to_i
          picture.datetime = hash['datetime']
          picture.photosets = hash.fetch('photosets', []).filter_map { |key| photosets_by_key[key] }
          picture.groups = hash.fetch('groups', []).filter_map { |id| groups_by_id[id] }
        end
      end
    end
  end
end
