# frozen_string_literal: true

module Frogr
  module Models
    # Geolocation attached to a picture. Serialised with the same member names
    # the C version's GObject properties produced, so existing .frogr projects
    # keep loading.
    class Location
      attr_accessor :latitude, :longitude

      def initialize(latitude: 0.0, longitude: 0.0)
        @latitude = latitude.to_f
        @longitude = longitude.to_f
      end

      def self.from_h(hash)
        new(latitude: hash['latitude'], longitude: hash['longitude'])
      end

      def to_h = { 'latitude' => latitude, 'longitude' => longitude }

      def to_s = format('%.6f, %.6f', latitude, longitude)

      def ==(other) = other.is_a?(Location) && other.latitude == latitude && other.longitude == longitude
    end
  end
end
