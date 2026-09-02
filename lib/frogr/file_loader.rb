# frozen_string_literal: true

require 'gtk4'

require_relative 'exif'
require_relative 'models/picture'
require_relative 'util'

module Frogr
  # Turns a list of file URIs into Picture objects with thumbnails.
  #
  # Loading runs one file per main-loop idle tick rather than on a worker
  # thread: GdkPixbuf scaling is the expensive part and it has to happen where
  # GTK lives anyway, and yielding between files keeps the window responsive
  # and the progress bar moving. The C version reached the same place through
  # a chain of GAsyncResult callbacks.
  class FileLoader
    # Matches IV_THUMB_WIDTH/HEIGHT from the C version, so thumbnails stay the
    # size the grid was designed around.
    THUMB_WIDTH = 136
    THUMB_HEIGHT = 136

    def initialize(uris:, config:, account: nil,
                   on_picture_loaded:, on_progress:, on_finished:, on_error: nil)
      @uris = uris.to_a
      @config = config
      @account = account
      @on_picture_loaded = on_picture_loaded
      @on_progress = on_progress
      @on_finished = on_finished
      @on_error = on_error
      @index = 0
      @cancelled = false
    end

    def load_all
      report_progress
      schedule_next
    end

    def cancel
      @cancelled = true
    end

    private

    def schedule_next
      GLib::Idle.add do
        if @cancelled || @index >= @uris.length
          @on_finished.call
        else
          load_one(@uris[@index])
          @index += 1
          report_progress
          schedule_next
        end

        false
      end
    end

    def report_progress
      @on_progress.call(@index, @uris.length, @uris[@index])
    end

    def load_one(uri)
      Util.uri_to_path(uri).then do |path|
        next unless File.file?(path)

        build_picture(path, uri).then do |picture|
          if within_size_limit?(picture)
            @on_picture_loaded.call(picture)
          else
            report_too_big(picture)
          end
        end
      end
    rescue StandardError => e
      @on_error&.call("#{File.basename(Util.uri_to_path(uri))}: #{e.message}")
    end

    def build_picture(path, uri)
      Models::Picture.new(
        fileuri: uri,
        title: Util.title_from_path(path, keep_extension: @config.keep_file_extensions),
        public: @config.default_public,
        family: @config.default_family,
        friend: @config.default_friend,
        video: Util.video?(path)
      ).tap do |picture|
        picture.safety_level = @config.default_safety_level
        picture.content_type = @config.default_content_type
        picture.license = @config.default_license
        picture.show_in_search = @config.default_show_in_search
        picture.send_location = @config.default_send_geolocation_data
        picture.replace_date_posted = @config.default_replace_date_posted
        picture.filesize = File.size(path)
        picture.pixbuf = thumbnail_for(path, picture.video?)

        apply_metadata(picture, path)
      end
    end

    def apply_metadata(picture, path)
      # Videos carry no EXIF worth reading, and parsing them wastes the time
      # the user is watching the progress bar for.
      return if picture.video?

      Exif.read(path).then do |metadata|
        picture.datetime = metadata.datetime
        picture.location = metadata.location
        picture.tags = Models::Picture.join_tags(metadata.keywords) if @config.import_tags_from_metadata
      end
    end

    # Videos have no decodable first frame here, so they get the bundled
    # film-strip image instead — the same fallback the C version used.
    def thumbnail_for(path, video)
      if video
        video_thumbnail
      else
        GdkPixbuf::Pixbuf.new(file: path, width: THUMB_WIDTH, height: THUMB_HEIGHT,
                              preserve_aspect_ratio: true).apply_embedded_orientation
      end
    rescue StandardError
      video_thumbnail
    end

    def video_thumbnail
      @video_thumbnail ||= begin
        GdkPixbuf::Pixbuf.new(file: File.join(Util.data_dir, 'images', 'mpictures.png'),
                              width: THUMB_WIDTH, height: THUMB_HEIGHT,
                              preserve_aspect_ratio: true)
      rescue StandardError
        nil
      end
    end

    # Flickr rejects oversized files outright, so they are caught here rather
    # than after the user has waited through an upload.
    def within_size_limit?(picture)
      max_filesize_for(picture).then { |limit| limit.zero? || picture.filesize <= limit }
    end

    def max_filesize_for(picture)
      return 0 unless @account&.has_extra_info?

      picture.video? ? @account.max_video_filesize : @account.max_picture_filesize
    end

    def report_too_big(picture)
      @on_error&.call(
        format('%s: file is too big (%s, limit is %s)',
               picture.title,
               Util.format_filesize(picture.filesize),
               Util.format_filesize(max_filesize_for(picture)))
      )
    end
  end
end
