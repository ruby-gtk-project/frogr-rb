# frozen_string_literal: true

require 'gtk4'
require 'uri'

module Frogr
  # Small helpers that had a whole frogr-util.c to themselves in C, mostly
  # because GLib makes each of them several lines long.
  module Util
    module_function

    # Where the app's data (icons, images) lives. Set by the Nix wrapper; falls
    # back to the source tree so the app runs straight from a checkout.
    def data_dir
      @data_dir ||= ENV.fetch('FROGR_DATA_DIR', File.expand_path('../../data', __dir__))
    end

    def config_dir
      @config_dir ||= File.join(
        ENV['XDG_CONFIG_HOME'] || File.join(Dir.home, '.config'), 'frogr'
      )
    end

    def uri_to_path(uri)
      URI::DEFAULT_PARSER.unescape(uri.to_s.sub(%r{\Afile://}, ''))
    end

    def path_to_uri(path) = "file://#{URI::DEFAULT_PARSER.escape(File.expand_path(path))}"

    # Titles come from the filename; whether the extension survives is a
    # preference, since Flickr shows the title verbatim.
    def title_from_path(path, keep_extension:)
      File.basename(path).then { |name| keep_extension ? name : File.basename(name, '.*') }
    end

    # Human-readable byte counts for the quota labels and error messages.
    def format_filesize(bytes)
      %w[bytes KB MB GB TB].each_with_index do |unit, i|
        (1024.0**(i + 1)).then do |limit|
          return format(i.zero? ? '%d %s' : '%.1f %s', bytes / (1024.0**i), unit) if bytes < limit
        end
      end

      format('%.1f PB', bytes / (1024.0**5))
    end

    # Opens a URI with whatever the desktop has registered for it. Used for the
    # authorisation page, the help pages and the external image viewer.
    def open_uri(uri, parent: nil)
      Gtk::UriLauncher.new(uri).launch(parent, nil) { |launcher, result| launcher.launch_finish(result) }
    rescue StandardError
      # A missing handler must never take the app down with it.
      warn "frogr: could not open #{uri}"
    end

    VIDEO_EXTENSIONS = %w[.avi .mp4 .m4v .mov .mpg .mpeg .ogv .wmv .3gp .mkv .webm].freeze

    def video?(path) = VIDEO_EXTENSIONS.include?(File.extname(path).downcase)

    IMAGE_EXTENSIONS = %w[.jpg .jpeg .png .gif .bmp .tif .tiff .webp .avif .heic .heif].freeze

    def image?(path) = IMAGE_EXTENSIONS.include?(File.extname(path).downcase)

    def supported?(path) = image?(path) || video?(path)
  end
end
