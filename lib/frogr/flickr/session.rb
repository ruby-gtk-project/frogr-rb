# frozen_string_literal: true

require 'gtk4'
require_relative 'client'

module Frogr
  module Flickr
    # Runs Flickr::Client calls off the main loop.
    #
    # The C original built this out of GAsyncResult pairs — one `_async` and
    # one `_finish` function per operation, plus a GCancellable. Ruby needs
    # none of that: the work runs in a thread and the result comes back through
    # GLib::Idle, which is the only point where GTK is touched again.
    #
    # Every request takes `on_success` and `on_error` callbacks, both invoked
    # on the main loop. Requests started while `cancelled` is set are dropped
    # rather than delivered, which is what "cancel ongoing requests" means here.
    class Session
      attr_reader :client

      def initialize(api_key:, secret:)
        @client = Client.new(api_key: api_key, secret: secret)
        @generation = 0
        @mutex = Mutex.new
      end

      def token = client.token

      def token=(value)
        client.token = value
      end

      def token_secret = client.token_secret

      def token_secret=(value)
        client.token_secret = value
      end

      def authorized? = !client.token.to_s.empty? && !client.token_secret.to_s.empty?

      # Results from requests started before this call are discarded when they
      # arrive. In-flight HTTP is left to finish on its own thread — Net::HTTP
      # has no safe interruption point, and the answer is thrown away anyway.
      def cancel_all
        @mutex.synchronize { @generation += 1 }
      end

      def use_default_proxy
        client.proxy = nil
      end

      def proxy=(settings)
        client.proxy = settings
      end

      # Dispatches one client method on a worker thread.
      #
      # `on_progress` is called on the main loop too, so upload callers can
      # drive a progress bar without any locking of their own.
      def request(method, *args, on_success: nil, on_error: nil, on_progress: nil, **kwargs)
        @mutex.synchronize { @generation }.then do |generation|
          Thread.new do
            begin
              deliver(generation, on_success, invoke(method, args, kwargs, generation, on_progress))
            rescue Error => e
              deliver(generation, on_error, e)
            rescue StandardError => e
              deliver(generation, on_error, Error.new("#{e.class}: #{e.message}"))
            end
          end
        end
      end

      private

      def invoke(method, args, kwargs, generation, on_progress)
        if on_progress
          client.public_send(method, *args, **kwargs,
                             on_progress: ->(fraction) { deliver(generation, on_progress, fraction) })
        else
          client.public_send(method, *args, **kwargs)
        end
      end

      # Hands a value back to the main loop, unless the request has been
      # superseded by a cancel_all in the meantime.
      def deliver(generation, callback, value)
        return if callback.nil?

        GLib::Idle.add do
          callback.call(value) if @mutex.synchronize { @generation } == generation
          false
        end
      end
    end
  end
end
