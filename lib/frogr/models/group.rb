# frozen_string_literal: true

module Frogr
  module Models
    # A Flickr group pool the user belongs to.
    class Group
      attr_accessor :id, :name, :privacy, :n_photos

      def initialize(id: nil, name: '', privacy: 0, n_photos: 0)
        @id = id
        @name = name.to_s
        @privacy = privacy.to_i
        @n_photos = n_photos.to_i
      end

      def self.from_h(hash)
        new(id: hash['id'], name: hash['name'].to_s,
            privacy: hash['privacy'].to_i, n_photos: hash['n-photos'].to_i)
      end

      def to_h
        { 'id' => id, 'name' => name, 'privacy' => privacy, 'n-photos' => n_photos }
      end

      def display_name = n_photos.positive? ? "#{name} (#{n_photos})" : name

      def ==(other) = other.is_a?(Group) && other.id == id

      alias eql? ==

      def hash = id.hash
    end
  end
end
