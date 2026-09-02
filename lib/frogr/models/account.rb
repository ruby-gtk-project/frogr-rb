# frozen_string_literal: true

module Frogr
  module Models
    # A Flickr account frogr has been authorised against, plus the quota
    # figures fetched from flickr.people.getUploadStatus.
    class Account
      # Bumped when the accounts.xml schema changes, as upstream does.
      CURRENT_VERSION = '2'

      attr_accessor :token, :token_secret, :permissions, :id, :username,
                    :fullname, :active, :has_extra_info, :remaining_bandwidth,
                    :max_bandwidth, :max_picture_filesize, :remaining_videos,
                    :current_videos, :max_video_filesize, :pro, :version

      alias active? active
      alias pro? pro
      alias has_extra_info? has_extra_info

      def initialize(token: nil, token_secret: nil)
        @token = token
        @token_secret = token_secret
        @permissions = nil
        @active = false
        @has_extra_info = false
        @pro = false
        @remaining_bandwidth = 0
        @max_bandwidth = 0
        @max_picture_filesize = 0
        @remaining_videos = 0
        @current_videos = 0
        @max_video_filesize = 0
        @version = CURRENT_VERSION
      end

      # An account is only usable once it carries both halves of the OAuth
      # credential and identifies a user.
      def valid? = !token.to_s.empty? && !token_secret.to_s.empty? && !username.to_s.empty?

      def display_name = fullname.to_s.empty? ? username.to_s : fullname.to_s

      def ==(other) = other.is_a?(Account) && other.username == username

      alias eql? ==

      def hash = username.hash

      # Quota figures arrive in KB from flickr.people.getUploadStatus.
      def apply_upload_status(status)
        self.id = status['id'] || id
        self.username = status['username'] || username
        self.pro = status['pro']
        self.max_bandwidth = status['bw_max_kb'].to_i * 1024
        self.remaining_bandwidth = status['bw_remaining_kb'].to_i * 1024
        self.max_picture_filesize = status['picture_fs_max_kb'].to_i * 1024
        self.max_video_filesize = status['video_fs_max_kb'].to_i * 1024
        self.current_videos = status['bw_used_videos'].to_i
        self.remaining_videos = status['bw_remaining_videos'].to_i
        self.has_extra_info = true
        self
      end
    end
  end
end
