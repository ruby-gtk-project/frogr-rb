# frozen_string_literal: true

module Frogr
  # Uploads one batch of pictures, one picture at a time.
  #
  # The C version spread this across a dozen mutually-recursive callbacks with
  # two heap-allocated context structs. Here the whole thing is a queue: each
  # picture expands into an upload step followed by whatever after-upload steps
  # its settings call for, and `run_next` walks that queue. Retries re-push the
  # step that failed.
  class UploadJob
    MAX_ATTEMPTS = 5

    # Flickr error numbers that will never succeed on a retry: bad credential,
    # bad file, or quota exhausted.
    FATAL_CODES = [1, 2, 3, 4, 5, 6, 98, 99, 100, 105].freeze

    def initialize(pictures:, session:, model:,
                   on_progress:, on_picture_done:, on_finished:, on_error: nil)
      @pictures = pictures.to_a
      @session = session
      @model = model
      @on_progress = on_progress
      @on_picture_done = on_picture_done
      @on_finished = on_finished
      @on_error = on_error
      @index = 0
      @attempts = 0
      @errors = []
      @cancelled = false
      @steps = []
    end

    def start
      report_progress(0.0)
      next_picture
    end

    def cancel
      @cancelled = true
      @session.cancel_all
    end

    private

    def current = @pictures[@index]

    def next_picture
      if @cancelled || @index >= @pictures.length
        @on_finished.call(@errors)
      else
        @attempts = 0
        @steps = []
        upload_current
      end
    end

    def advance
      @on_picture_done.call(current)
      @index += 1
      report_progress(0.0)
      next_picture
    end

    # Progress spans the whole batch: completed pictures plus how far into the
    # current one we are.
    def report_progress(fraction)
      @on_progress.call(
        (@index + fraction) / [@pictures.length, 1].max,
        @index + 1,
        @pictures.length,
        current&.title
      )
    end

    def upload_current
      current.then do |picture|
        @session.request(
          :upload, picture.path, upload_params(picture),
          on_progress: ->(fraction) { report_progress(fraction) },
          on_success: lambda { |photo_id|
            picture.id = photo_id
            @steps = after_upload_steps(picture)
            run_next
          },
          on_error: ->(error) { retry_or_fail(error) { upload_current } }
        )
      end
    end

    def upload_params(picture)
      {
        'title' => picture.title,
        'description' => picture.description,
        'tags' => picture.tags_string,
        'is_public' => picture.public? ? 1 : 0,
        'is_family' => picture.family? ? 1 : 0,
        'is_friend' => picture.friend? ? 1 : 0,
        'safety_level' => picture.safety_level,
        'content_type' => picture.content_type,
        'hidden' => picture.show_in_search? ? Enums::SEARCH_SCOPE_PUBLIC : Enums::SEARCH_SCOPE_HIDDEN
      }
    end

    # The order matches the C version's _perform_after_upload_operations.
    def after_upload_steps(picture)
      [].tap do |steps|
        steps << -> { set_license(picture) } unless picture.license.to_i.negative?
        steps << -> { set_location(picture) } if picture.send_location? && picture.location
        steps << -> { set_date_posted(picture) } if picture.replace_date_posted?

        picture.photosets.each { |set| steps << -> { add_to_photoset(picture, set) } }
        picture.groups.each { |group| steps << -> { add_to_group(picture, group) } }
      end
    end

    def run_next
      if @cancelled
        @on_finished.call(@errors)
      elsif @steps.empty?
        advance
      else
        @attempts = 0
        @steps.shift.call
      end
    end

    # --- After-upload operations -----------------------------------------

    def set_license(picture)
      @session.request(:set_license, picture.id, picture.license,
                       on_success: ->(_) { run_next },
                       on_error: ->(e) { retry_or_fail(e, picture) { set_license(picture) } })
    end

    def set_location(picture)
      @session.request(:set_location, picture.id, picture.location,
                       on_success: ->(_) { run_next },
                       on_error: ->(e) { retry_or_fail(e, picture) { set_location(picture) } })
    end

    def set_date_posted(picture)
      @session.request(:set_date_posted, picture.id, Time.now,
                       on_success: ->(_) { run_next },
                       on_error: ->(e) { retry_or_fail(e, picture) { set_date_posted(picture) } })
    end

    # A set the user created locally has no remote id yet, so the first picture
    # bound for it creates the set and the rest are added to what comes back.
    def add_to_photoset(picture, set)
      if set.local?
        create_photoset(picture, set)
      else
        @session.request(:add_to_photoset, picture.id, set.id,
                         on_success: ->(_) { run_next },
                         on_error: ->(e) { retry_or_fail(e, picture) { add_to_photoset(picture, set) } })
      end
    end

    def create_photoset(picture, set)
      @session.request(
        :create_photoset, set.title, set.description.to_s, picture.id,
        on_success: lambda { |created|
          # Adopting the remote id in place means every other picture queued
          # for this set now takes the add_to_photoset path instead.
          set.id = created.id
          set.n_photos = 1
          run_next
        },
        on_error: ->(e) { retry_or_fail(e, picture) { create_photoset(picture, set) } }
      )
    end

    def add_to_group(picture, group)
      @session.request(:add_to_group, picture.id, group.id,
                       on_success: ->(_) { run_next },
                       on_error: ->(e) { retry_or_fail(e, picture) { add_to_group(picture, group) } })
    end

    # --- Failure handling -------------------------------------------------

    # Transient failures are retried up to MAX_ATTEMPTS; anything Flickr calls
    # fatal, or that has run out of attempts, is recorded and the batch moves
    # on to the next picture rather than stopping.
    def retry_or_fail(error, picture = current)
      @attempts += 1

      if retryable?(error) && @attempts < MAX_ATTEMPTS
        yield
      else
        @errors << "#{picture&.title}: #{error.message}"
        @on_error&.call("#{picture&.title}: #{error.message}")
        advance
      end
    end

    def retryable?(error) = !FATAL_CODES.include?(error.respond_to?(:code) ? error.code : nil)
  end
end
