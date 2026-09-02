#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks for the parts of the port where getting it subtly wrong would be
# invisible in the UI: OAuth signing, EXIF parsing, tag quoting, and the two
# on-disk formats that have to stay compatible with upstream frogr.
#
#   nix develop --command ruby test/run_tests.rb

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

require 'fileutils'
require 'tmpdir'

require 'frogr/config'
require 'frogr/exif'
require 'frogr/flickr/client'
require 'frogr/model'

@failures = []
@count = 0

def check(name)
  @count += 1
  yield.then do |ok|
    puts(ok ? "  ok   #{name}" : "  FAIL #{name}")
    @failures << name unless ok
  end
rescue StandardError => e
  puts "  FAIL #{name} (#{e.class}: #{e.message})"
  @failures << name
end

puts 'OAuth 1.0a signing'

# The signature base string from the OAuth spec's worked example. This is the
# step implementations actually get wrong — percent-encoding, parameter
# sorting, and the double-encoding of the parameter string.
check 'builds the documented signature base string' do
  Frogr::Flickr::Client.new(api_key: 'xvz1evFS4wEEPTGEFPHBog', secret: 'secret').then do |client|
    client.send(:encode_params,
                'status' => 'Hello Ladies + Add Yours',
                'include_entities' => 'true',
                'oauth_consumer_key' => 'xvz1evFS4wEEPTGEFPHBog',
                'oauth_nonce' => 'kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg',
                'oauth_signature_method' => 'HMAC-SHA1',
                'oauth_timestamp' => '1318622958',
                'oauth_token' => '370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb',
                'oauth_version' => '1.0').then do |encoded|
      encoded == 'include_entities=true&oauth_consumer_key=xvz1evFS4wEEPTGEFPHBog&' \
                 'oauth_nonce=kYjzVBB8Y0ZFabxSWbWovY3uYSQ2pTgmZeNu2VS4cg&' \
                 'oauth_signature_method=HMAC-SHA1&oauth_timestamp=1318622958&' \
                 'oauth_token=370773112-GmHxMAgYyLbNEtIKZeRNFsMKPR9EyMZeS9weJAEb&' \
                 'oauth_version=1.0&status=Hello%20Ladies%20%2B%20Add%20Yours'
    end
  end
end

check 'percent-encodes per OAuth, not CGI' do
  Frogr::Flickr::Client.new(api_key: 'k', secret: 's').then do |client|
    client.send(:escape, 'a b~c+d') == 'a%20b~c%2Bd'
  end
end

check 'signature is deterministic base64 HMAC-SHA1' do
  Frogr::Flickr::Client.new(api_key: 'k', secret: 'cs').then do |client|
    client.send(:sign, 'GET', 'https://example.com/x', { 'a' => '1' }, 'ts').then do |signature|
      signature == client.send(:sign, 'GET', 'https://example.com/x', { 'a' => '1' }, 'ts') &&
        signature.length == 28 && signature.end_with?('=')
    end
  end
end

puts 'Tags'

check 'quoted multi-word tags survive a round trip' do
  Frogr::Models::Picture.new(fileuri: 'file:///tmp/a.jpg').then do |picture|
    picture.tags = 'holidays "san francisco" beach'
    picture.tags == ['beach', 'holidays', 'san francisco'] &&
      Frogr::Models::Picture.split_tags(picture.tags_string) == picture.tags
  end
end

check 'joining a keyword list keeps multi-word keywords intact' do
  Frogr::Models::Picture.join_tags(['paris', 'eiffel tower']).then do |joined|
    joined == 'paris "eiffel tower"' &&
      Frogr::Models::Picture.split_tags(joined) == ['paris', 'eiffel tower']
  end
end

check 'tags are deduplicated and sorted' do
  Frogr::Models::Picture.new(fileuri: 'file:///tmp/a.jpg').then do |picture|
    picture.tags = 'b a b'
    picture.tags == %w[a b]
  end
end

puts 'EXIF'

check 'reads nothing rather than raising from a non-image' do
  Dir.mktmpdir do |dir|
    File.join(dir, 'junk.bin').tap { |path| File.binwrite(path, "\x00\xff" * 512) }.then do |path|
      Frogr::Exif.read(path).then do |metadata|
        metadata.datetime.nil? && metadata.location.nil? && metadata.keywords.empty?
      end
    end
  end
end

check 'reads dc:subject keywords out of an XMP packet' do
  Frogr::Exif.keywords_from(
    '<dc:subject><rdf:Bag><rdf:li>paris</rdf:li><rdf:li>eiffel tower</rdf:li></rdf:Bag></dc:subject>'
  ) == ['paris', 'eiffel tower']
end

check 'converts GPS degrees/minutes/seconds with hemisphere' do
  Frogr::Exif.coordinate([48.0, 51.0, 31.8384], 'N').then do |north|
    Frogr::Exif.coordinate([48.0, 51.0, 31.8384], 'S').then do |south|
      (north - 48.858844).abs < 1e-5 && (south + 48.858844).abs < 1e-5
    end
  end
end

puts 'Project files'

check 'a project survives save and reload' do
  Dir.mktmpdir do |dir|
    Frogr::Model.new.then do |model|
      Frogr::Models::PhotoSet.new(title: 'Trip').tap { |set| model.add_local_photoset(set) }.then do |set|
        Frogr::Models::Picture.new(fileuri: 'file:///tmp/a.jpg', title: 'A').tap do |picture|
          picture.tags = 'paris "eiffel tower"'
          picture.description = 'desc'
          picture.license = 4
          picture.location = Frogr::Models::Location.new(latitude: 1.5, longitude: -2.5)
          picture.add_photoset(set)
          model.add_picture(picture)
        end
      end

      File.join(dir, 'p.frogr').then do |path|
        model.save_to_file(path)

        Frogr::Model.new.tap { |reloaded| reloaded.load_from_file(path) }.then do |reloaded|
          reloaded.n_pictures == 1 &&
            reloaded.pictures.first.tags == ['eiffel tower', 'paris'] &&
            reloaded.pictures.first.license == 4 &&
            reloaded.pictures.first.location.latitude == 1.5 &&
            reloaded.pictures.first.photosets.map(&:title) == ['Trip']
        end
      end
    end
  end
end

puts 'Settings and accounts'

check 'settings round-trip through the upstream XML schema' do
  Dir.mktmpdir do |dir|
    Frogr::Config.new(config_dir: dir).tap do |config|
      config.default_public = false
      config.default_license = 5
      config.mainview_sorting_criteria = :by_date
      config.mainview_sorting_reversed = true
      config.use_proxy = true
      config.proxy_host = 'proxy.example'
      config.save_settings
    end

    File.read(File.join(dir, 'settings.xml')).then do |xml|
      Frogr::Config.new(config_dir: dir).then do |reloaded|
        # Element text stays inline, the way libxml2 wrote it upstream.
        xml.include?('<public>0</public>') &&
          xml.include?("<settings version='2'>") &&
          reloaded.default_public == false &&
          reloaded.default_license == 5 &&
          reloaded.mainview_sorting_criteria == :by_date &&
          reloaded.mainview_sorting_reversed == true &&
          reloaded.proxy_host == 'proxy.example'
      end
    end
  end
end

check 'accounts round-trip and the file is not world-readable' do
  Dir.mktmpdir do |dir|
    Frogr::Config.new(config_dir: dir).tap do |config|
      Frogr::Models::Account.new(token: 'tok', token_secret: 'sec').tap do |account|
        account.username = 'someone'
        account.fullname = 'Some One'
        account.id = '42@N01'
        config.add_account(account)
      end
    end

    File.join(dir, 'accounts.xml').then do |path|
      Frogr::Config.new(config_dir: dir).active_account.then do |account|
        (File.stat(path).mode & 0o077).zero? &&
          account&.username == 'someone' &&
          account.token == 'tok' &&
          account.token_secret == 'sec' &&
          account.active?
      end
    end
  end
end

check 'an account missing its token is discarded on load' do
  Dir.mktmpdir do |dir|
    File.write(File.join(dir, 'accounts.xml'),
               "<accounts><account version='2'><username>x</username></account></accounts>")
    Frogr::Config.new(config_dir: dir).accounts.empty?
  end
end

puts
puts "#{@count - @failures.length}/#{@count} checks passed"
@failures.each { |name| puts "  failed: #{name}" }
exit(@failures.empty? ? 0 : 1)
