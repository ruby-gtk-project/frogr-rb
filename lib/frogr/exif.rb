# frozen_string_literal: true

require_relative 'models/location'

module Frogr
  # A small, dependency-free reader for the three pieces of metadata frogr
  # actually uses: when the photo was taken, where it was taken, and the
  # keywords to import as tags.
  #
  # The C version pulled in libexif and a hand-rolled XMP scanner for the same
  # job. This reads the JPEG APP1 segments directly — the TIFF/EXIF IFD tree
  # for DateTimeOriginal and GPS, and the XMP packet for dc:subject.
  module Exif
    # TIFF tag numbers.
    EXIF_IFD_POINTER = 0x8769
    GPS_IFD_POINTER  = 0x8825
    DATE_TIME_ORIGINAL = 0x9003
    DATE_TIME = 0x0132
    GPS_LATITUDE_REF  = 0x0001
    GPS_LATITUDE      = 0x0002
    GPS_LONGITUDE_REF = 0x0003
    GPS_LONGITUDE     = 0x0004

    # Byte counts per TIFF field type, indexed by type number.
    TYPE_SIZES = { 1 => 1, 2 => 1, 3 => 2, 4 => 4, 5 => 8, 7 => 1, 9 => 4, 10 => 8 }.freeze

    # How much of the file to read. EXIF and XMP both live near the start, and
    # this keeps a directory of large RAWs from being slurped into memory.
    HEADER_BYTES = 512 * 1024

    Metadata = Struct.new(:datetime, :location, :keywords, keyword_init: true)

    module_function

    # Never raises: unreadable or exotic metadata simply yields empty fields,
    # because a photo with odd EXIF must still be uploadable.
    def read(path)
      File.binread(path, HEADER_BYTES).then do |head|
        tiff_tags(head).then do |tags|
          Metadata.new(
            datetime: datetime_from(tags),
            location: location_from(tags),
            keywords: keywords_from(head)
          )
        end
      end
    rescue StandardError
      Metadata.new(datetime: nil, location: nil, keywords: [])
    end

    # --- EXIF -------------------------------------------------------------

    def datetime_from(tags)
      (tags[DATE_TIME_ORIGINAL] || tags[DATE_TIME]).then do |value|
        value&.to_s&.delete("\0")&.strip&.then { |text| text unless text.empty? }
      end
    end

    def location_from(tags)
      coordinate(tags[GPS_LATITUDE], tags[GPS_LATITUDE_REF]).then do |latitude|
        coordinate(tags[GPS_LONGITUDE], tags[GPS_LONGITUDE_REF]).then do |longitude|
          Models::Location.new(latitude: latitude, longitude: longitude) if latitude && longitude
        end
      end
    end

    # GPS coordinates are stored as three rationals (degrees, minutes, seconds)
    # plus a hemisphere letter.
    def coordinate(rationals, hemisphere)
      rationals.is_a?(Array) && rationals.length >= 3 or return nil

      (rationals[0] + (rationals[1] / 60.0) + (rationals[2] / 3600.0)).then do |degrees|
        %w[S W].include?(hemisphere.to_s.delete("\0").strip.upcase) ? -degrees : degrees
      end
    end

    # Walks the APP1 EXIF segment and returns a flat tag => value map, merging
    # the main IFD with the Exif and GPS sub-IFDs. GPS tag numbers are low and
    # do not collide with the ones read from the other IFDs.
    def tiff_tags(data)
      exif_segment(data).then do |tiff|
        next {} if tiff.nil?

        byte_order(tiff).then do |order|
          next {} if order.nil?

          read_ifd(tiff, read_long(tiff, 4, order), order).then do |tags|
            [tags[EXIF_IFD_POINTER], tags[GPS_IFD_POINTER]].compact.reduce(tags) do |merged, offset|
              read_ifd(tiff, offset.to_i, order).merge(merged)
            end
          end
        end
      end
    end

    # Finds the APP1 segment whose payload starts with "Exif\0\0" and returns
    # the TIFF block that follows it, which is what every offset is relative to.
    def exif_segment(data)
      data.index("Exif\0\0").then { |at| data[(at + 6)..] if at }
    end

    def byte_order(tiff)
      case tiff[0, 2]
      when 'II' then :little
      when 'MM' then :big
      end
    end

    def read_ifd(tiff, offset, order, depth = 0)
      # A malformed file can point an IFD at itself; the depth cap stops that
      # turning into an unbounded walk.
      return {} if offset.nil? || offset <= 0 || offset + 2 > tiff.bytesize || depth > 4

      read_short(tiff, offset, order).then do |count|
        (0...count).each_with_object({}) do |i, tags|
          (offset + 2 + (i * 12)).then do |entry|
            next if entry + 12 > tiff.bytesize

            read_entry(tiff, entry, order).then { |tag, value| tags[tag] = value if tag }
          end
        end
      end
    end

    def read_entry(tiff, entry, order)
      [read_short(tiff, entry, order),
       read_short(tiff, entry + 2, order),
       read_long(tiff, entry + 4, order)].then do |tag, type, count|
        (TYPE_SIZES.fetch(type, 0) * count.to_i).then do |size|
          # Values of four bytes or fewer are stored inline in the entry.
          (size > 4 ? read_long(tiff, entry + 8, order) : entry + 8).then do |value_offset|
            [tag, read_value(tiff, value_offset, type, count.to_i, order)]
          end
        end
      end
    end

    def read_value(tiff, offset, type, count, order)
      return nil if offset.nil? || offset.negative? || offset >= tiff.bytesize

      case type
      when 2 then tiff[offset, count].to_s.split("\0").first
      when 5, 10 then rationals(tiff, offset, count, order, signed: type == 10)
      when 3 then read_short(tiff, offset, order)
      when 4, 9 then read_long(tiff, offset, order)
      end
    end

    def rationals(tiff, offset, count, order, signed:)
      (0...count).map do |i|
        (offset + (i * 8)).then do |at|
          [read_long(tiff, at, order, signed: signed),
           read_long(tiff, at + 4, order, signed: signed)].then do |num, den|
            den.to_i.zero? ? 0.0 : num.to_f / den
          end
        end
      end
    end

    def read_short(tiff, offset, order)
      return nil if offset.nil? || offset + 2 > tiff.bytesize

      tiff[offset, 2].unpack1(order == :little ? 'v' : 'n')
    end

    def read_long(tiff, offset, order, signed: false)
      return nil if offset.nil? || offset + 4 > tiff.bytesize

      tiff[offset, 4].unpack1(order == :little ? 'V' : 'N').then do |value|
        signed && value > 0x7fffffff ? value - 0x1_0000_0000 : value
      end
    end

    # --- XMP --------------------------------------------------------------

    # Keywords live in the XMP packet as an RDF bag under dc:subject. This
    # matches upstream's behaviour of importing them as tags.
    def keywords_from(data)
      data[%r{<dc:subject>(.*?)</dc:subject>}m, 1].then do |subject|
        next [] if subject.nil?

        subject.scan(%r{<rdf:li[^>]*>(.*?)</rdf:li>}m).flatten.map(&:strip).reject(&:empty?)
      end
    end
  end
end
