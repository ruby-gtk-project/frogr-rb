# frozen_string_literal: true

module Frogr
  module Models
    # A Flickr photoset (album). A set is "local" until it has been created
    # remotely, at which point it gains an `id`; until then `local_id` is what
    # ties the pictures queued for it together.
    class PhotoSet
      attr_accessor :id, :local_id, :title, :description, :primary_photo_id, :n_photos

      def initialize(title: '', description: nil, id: nil, local_id: nil,
                     primary_photo_id: nil, n_photos: 0)
        @id = id
        @local_id = local_id || (id.nil? ? "local-#{object_id}" : nil)
        @title = title.to_s
        @description = description
        @primary_photo_id = primary_photo_id
        @n_photos = n_photos.to_i
      end

      def self.from_h(hash)
        new(id: hash['id'], local_id: hash['local-id'], title: hash['title'].to_s,
            description: hash['description'], primary_photo_id: hash['primary-photo-id'],
            n_photos: hash['n-photos'].to_i)
      end

      def to_h
        {
          'id' => id,
          'local-id' => local_id,
          'title' => title,
          'description' => description,
          'primary-photo-id' => primary_photo_id,
          'n-photos' => n_photos
        }
      end

      # A set the user created in frogr but that does not exist on Flickr yet.
      def local? = id.nil?

      # Sets are matched by remote id once uploaded, by local id before that.
      def key = id || local_id

      def display_title = n_photos.positive? ? "#{title} (#{n_photos})" : title

      def ==(other) = other.is_a?(PhotoSet) && other.key == key

      alias eql? ==

      def hash = key.hash
    end
  end
end
