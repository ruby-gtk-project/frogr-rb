# frozen_string_literal: true

require 'cgi'
require 'json'
require 'net/http'
require 'openssl'
require 'securerandom'
require 'uri'

module Frogr
  module Flickr
    # Raised for anything the caller should surface to the user: transport
    # failures, OAuth problems, and Flickr's own `stat="fail"` responses.
    class Error < StandardError
      attr_reader :code

      def initialize(message, code: nil)
        super(message)
        @code = code
      end
    end

    # A synchronous, OAuth 1.0a signed Flickr REST client — the replacement for
    # upstream's bundled `flicksoup`.
    #
    # Everything here blocks. Callers that must not block the GTK main loop go
    # through Flickr::Session, which runs these calls on a worker thread and
    # delivers results back via GLib::Idle.
    class Client
      REST_URL = 'https://api.flickr.com/services/rest'
      UPLOAD_URL = 'https://up.flickr.com/services/upload'
      REQUEST_TOKEN_URL = 'https://www.flickr.com/services/oauth/request_token'
      ACCESS_TOKEN_URL = 'https://www.flickr.com/services/oauth/access_token'
      AUTHORIZE_URL = 'https://www.flickr.com/services/oauth/authorize'

      CALLBACK = 'oob'
      SIGNATURE_METHOD = 'HMAC-SHA1'
      OAUTH_VERSION = '1.0'

      # Flickr's own error numbers that mean "this credential is no good", as
      # distinct from transient failures worth retrying.
      AUTH_ERROR_CODES = [98, 99, 100, 105].freeze

      attr_accessor :token, :token_secret, :proxy

      def initialize(api_key:, secret:, token: nil, token_secret: nil)
        @api_key = api_key
        @secret = secret
        @token = token
        @token_secret = token_secret
        @proxy = nil
      end

      # --- Authorisation --------------------------------------------------

      # Step one of OAuth: swap nothing for a request token, and hand back the
      # URL the user has to visit. The request-token secret is remembered so
      # `complete_auth` can sign with it.
      def auth_url
        parse_query(signed_get(REQUEST_TOKEN_URL, {}, token_secret: nil)).then do |response|
          @request_token = response['oauth_token']
          @request_token_secret = response['oauth_token_secret']

          if @request_token.nil?
            raise Error, "Flickr did not return a request token (#{response['oauth_problem'] || 'unknown reason'})"
          end

          "#{AUTHORIZE_URL}?oauth_token=#{escape(@request_token)}&perms=delete"
        end
      end

      # Step two: exchange the verification code the user pasted back for a
      # permanent access token.
      def complete_auth(verification_code)
        parse_query(
          signed_get(ACCESS_TOKEN_URL,
                     { 'oauth_verifier' => verification_code.to_s.strip },
                     token: @request_token, token_secret: @request_token_secret)
        ).then do |response|
          raise Error, 'Flickr rejected the verification code' if response['oauth_token'].nil?

          @token = response['oauth_token']
          @token_secret = response['oauth_token_secret']

          {
            'token' => @token,
            'token_secret' => @token_secret,
            'permissions' => response['fullname'] ? 'delete' : response['perms'],
            'nsid' => response['user_nsid'],
            'username' => response['username'],
            'fullname' => response['fullname']
          }
        end
      end

      # Validates the stored token and returns who it belongs to.
      def check_auth_info
        call('flickr.auth.oauth.checkToken')['oauth'].then do |oauth|
          {
            'token' => token,
            'token_secret' => token_secret,
            'permissions' => oauth.dig('perms', '_content'),
            'nsid' => oauth.dig('user', 'nsid'),
            'username' => oauth.dig('user', 'username'),
            'fullname' => oauth.dig('user', 'fullname')
          }
        end
      end

      # --- Account --------------------------------------------------------

      def upload_status
        call('flickr.people.getUploadStatus')['user'].then do |user|
          {
            'id' => user['id'],
            'username' => user.dig('username', '_content'),
            'pro' => user['ispro'].to_i == 1,
            'bw_max_kb' => user.dig('bandwidth', 'maxkb').to_i,
            'bw_used_kb' => user.dig('bandwidth', 'usedkb').to_i,
            'bw_remaining_kb' => user.dig('bandwidth', 'remainingkb').to_i,
            'bw_used_videos' => user.dig('videos', 'uploaded').to_i,
            'bw_remaining_videos' => user.dig('videos', 'remaining').to_i,
            'picture_fs_max_kb' => user.dig('filesize', 'maxkb').to_i,
            'video_fs_max_kb' => user.dig('videosize', 'maxkb').to_i
          }
        end
      end

      # --- Upload ---------------------------------------------------------

      # Uploads one file and returns its new photo id.
      #
      # The upload endpoint is multipart and, unusually for Flickr, replies in
      # XML rather than JSON — `nojsoncallback` has no effect there.
      # `on_progress` receives a 0.0..1.0 fraction as the body is written.
      def upload(path, params, on_progress: nil)
        upload_params = params.compact.transform_values(&:to_s)

        post_multipart(
          UPLOAD_URL,
          oauth_params_for(UPLOAD_URL, 'POST', upload_params),
          upload_params,
          path,
          on_progress: on_progress
        ).then do |body|
          body[%r{<photoid[^>]*>([^<]+)</photoid>}, 1] ||
            raise(Error, upload_error_message(body))
        end
      end

      # --- Photos ---------------------------------------------------------

      def photo_info(photo_id) = call('flickr.photos.getInfo', 'photo_id' => photo_id)['photo']

      def set_license(photo_id, license)
        call('flickr.photos.licenses.setLicense', 'photo_id' => photo_id, 'license_id' => license.to_s)
        true
      end

      def set_location(photo_id, location)
        call('flickr.photos.geo.setLocation',
             'photo_id' => photo_id,
             'lat' => format('%.6f', location.latitude),
             'lon' => format('%.6f', location.longitude))
        true
      end

      def location(photo_id)
        call('flickr.photos.geo.getLocation', 'photo_id' => photo_id).dig('photo', 'location').then do |geo|
          geo && Models::Location.new(latitude: geo['latitude'], longitude: geo['longitude'])
        end
      end

      # Flickr wants a MySQL-style local timestamp for `date_posted`.
      def set_date_posted(photo_id, time)
        call('flickr.photos.setDates', 'photo_id' => photo_id, 'date_posted' => time.to_i.to_s)
        true
      end

      # --- Photosets ------------------------------------------------------

      def photosets
        call('flickr.photosets.getList').dig('photosets', 'photoset').to_a.map do |set|
          Models::PhotoSet.new(
            id: set['id'],
            title: set.dig('title', '_content').to_s,
            description: set.dig('description', '_content'),
            primary_photo_id: set['primary'],
            n_photos: set['photos'].to_i
          )
        end
      end

      def create_photoset(title, description, primary_photo_id)
        call('flickr.photosets.create',
             'title' => title.to_s,
             'description' => description.to_s,
             'primary_photo_id' => primary_photo_id)['photoset'].then do |set|
          Models::PhotoSet.new(id: set['id'], title: title.to_s, description: description,
                               primary_photo_id: primary_photo_id, n_photos: 1)
        end
      end

      def add_to_photoset(photo_id, photoset_id)
        call('flickr.photosets.addPhoto', 'photo_id' => photo_id, 'photoset_id' => photoset_id)
        true
      end

      # --- Groups ---------------------------------------------------------

      def groups
        call('flickr.groups.pools.getGroups').dig('groups', 'group').to_a.map do |group|
          Models::Group.new(id: group['nsid'] || group['id'], name: group['name'].to_s,
                            privacy: group['privacy'].to_i, n_photos: group['photos'].to_i)
        end
      end

      def add_to_group(photo_id, group_id)
        call('flickr.groups.pools.add', 'photo_id' => photo_id, 'group_id' => group_id)
        true
      end

      # --- Tags -----------------------------------------------------------

      def tags_list
        call('flickr.tags.getListUser').dig('who', 'tags', 'tag').to_a.map do |tag|
          tag.is_a?(Hash) ? tag['_content'].to_s : tag.to_s
        end
      end

      private

      # Every REST call is a signed GET asking for JSON.
      def call(method, params = {})
        params = params.compact.transform_values(&:to_s).merge(
          'method' => method, 'format' => 'json', 'nojsoncallback' => '1'
        )

        parse_json(signed_get(REST_URL, params))
      end

      def parse_json(body)
        JSON.parse(body).then do |response|
          if response['stat'] != 'ok'
            raise Error.new(response['message'] || 'Unknown Flickr error', code: response['code'].to_i)
          end

          response
        end
      rescue JSON::ParserError
        raise Error, "Flickr returned a malformed response: #{body.to_s[0, 200]}"
      end

      def signed_get(url, params, token: :default, token_secret: :default)
        oauth = oauth_params_for(
          url, 'GET', params,
          token: token == :default ? @token : token,
          token_secret: token_secret == :default ? @token_secret : token_secret
        )

        get("#{url}?#{encode_params(params.merge(oauth))}")
      end

      # --- OAuth 1.0a signing ---------------------------------------------

      def oauth_params_for(url, method, params, token: :default, token_secret: :default)
        token = @token if token == :default
        token_secret = @token_secret if token_secret == :default

        {
          'oauth_nonce' => SecureRandom.hex(16),
          'oauth_timestamp' => Time.now.to_i.to_s,
          'oauth_consumer_key' => @api_key,
          'oauth_signature_method' => SIGNATURE_METHOD,
          'oauth_version' => OAUTH_VERSION,
          'oauth_callback' => (CALLBACK if url == REQUEST_TOKEN_URL),
          'oauth_token' => token
        }.compact.then do |oauth|
          oauth.merge('oauth_signature' => sign(method, url, params.merge(oauth), token_secret))
        end
      end

      # The signature base string is method + URL + every parameter (OAuth and
      # request alike) sorted and encoded, all percent-encoded again and joined
      # with '&'. The signing key is consumer secret + token secret.
      def sign(method, url, params, token_secret)
        [method, url, encode_params(params)].map { |part| escape(part) }.join('&').then do |base|
          OpenSSL::HMAC.digest(
            'sha1', "#{escape(@secret)}&#{escape(token_secret)}", base
          ).then { |digest| [digest].pack('m0') }
        end
      end

      def encode_params(params)
        params.sort.map { |key, value| "#{escape(key)}=#{escape(value)}" }.join('&')
      end

      # OAuth's percent-encoding is stricter than CGI.escape: spaces are %20,
      # and `-._~` stay literal.
      def escape(value) = CGI.escape(value.to_s).gsub('+', '%20').gsub('%7E', '~')

      def parse_query(body)
        URI.decode_www_form(body.to_s).to_h
      rescue ArgumentError
        raise Error, "Flickr returned a malformed OAuth response: #{body.to_s[0, 200]}"
      end

      # --- Transport ------------------------------------------------------

      def get(url)
        request(URI.parse(url)) { |uri| Net::HTTP::Get.new(uri) }
      end

      # Multipart bodies are assembled in memory. Photos are bounded by
      # Flickr's own per-file limit, so this stays well inside a sane size.
      def post_multipart(url, oauth, params, path, on_progress: nil)
        "----------frogr#{SecureRandom.hex(16)}".then do |boundary|
          multipart_body(boundary, params.merge(oauth), path).then do |body|
            request(URI.parse(url), body_bytes: body.bytesize, on_progress: on_progress) do |uri|
              Net::HTTP::Post.new(uri).tap do |req|
                req['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
                req.body = body
              end
            end
          end
        end
      end

      def multipart_body(boundary, fields, path)
        String.new(encoding: Encoding::BINARY).tap do |body|
          fields.each do |name, value|
            body << "--#{boundary}\r\n"
            body << "Content-Disposition: form-data; name=\"#{name}\"\r\n\r\n"
            body << "#{value}\r\n"
          end

          body << "--#{boundary}\r\n"
          body << "Content-Disposition: form-data; name=\"photo\"; filename=\"#{File.basename(path)}\"\r\n"
          body << "Content-Type: application/octet-stream\r\n\r\n"
          body << File.binread(path)
          body << "\r\n--#{boundary}--\r\n"
        end
      end

      def request(uri, body_bytes: nil, on_progress: nil)
        http_for(uri).start do |http|
          # Net::HTTP has no upload-progress hook, so the fraction is reported
          # as 0 before the write and 1 after it — enough to keep the progress
          # bar honest without lying about intermediate state.
          on_progress&.call(0.0)

          http.request(yield(uri)).then do |response|
            on_progress&.call(1.0)
            raise Error, "HTTP #{response.code}: #{response.message}" unless response.is_a?(Net::HTTPSuccess)

            response.body
          end
        end
      rescue Error
        raise
      rescue StandardError => e
        raise Error, "Could not reach Flickr: #{e.message}"
      end

      def http_for(uri)
        (proxy || {}).then do |px|
          Net::HTTP.new(uri.host, uri.port,
                        px[:host], px[:port], px[:username], px[:password]).tap do |http|
            http.use_ssl = uri.scheme == 'https'
            http.open_timeout = 30
            http.read_timeout = 300
          end
        end
      end

      def upload_error_message(body)
        body[/<err[^>]*msg="([^"]+)"/, 1] || "Upload failed: #{body.to_s[0, 200]}"
      end
    end
  end
end
