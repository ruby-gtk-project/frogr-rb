# frozen_string_literal: true

require 'gtk4'

module Frogr
  module Ui
    # An entry that completes the last space-separated word against the tags
    # already known to the model — the C version's FrogrLiveEntry.
    #
    # The completion applies to the word under the cursor rather than the whole
    # text, because the field holds a whole list of tags.
    class TagEntry
      def initialize(model:, text: '')
        @model = model
        @initial_text = text
      end

      def build
        entry.tap do |field|
          field.completion = completion

          completion.tap do |comp|
            comp.model = completion_store
            comp.text_column = 0
            comp.signal_connect('match-selected') { |_, store, iter| replace_last_tag(store, iter) }
          end

          field.signal_connect('changed') { refresh_completions }
        end
      end

      def text = entry.text

      def text=(value)
        entry.text = value.to_s
      end

      def entry
        @entry ||= Gtk::Entry.new.tap do |field|
          field.text = @initial_text.to_s
          field.hexpand = true
          field.placeholder_text = 'tag1 tag2 "two words"'
        end
      end

      private

      def completion = @completion ||= Gtk::EntryCompletion.new.tap { |c| c.minimum_key_length = 1 }

      def completion_store = @completion_store ||= Gtk::ListStore.new(String)

      # The store is refilled per keystroke against the current word, which is
      # what makes completion apply to the last tag rather than the whole field.
      def refresh_completions
        current_word.then do |word|
          completion_store.clear

          unless word.empty?
            @model.tags.select { |tag| tag.downcase.start_with?(word.downcase) && tag.casecmp(word) != 0 }
                  .first(10)
                  .each { |tag| completion_store.append.set_value(0, tag) }
          end
        end
      end

      def current_word = entry.text.split(' ').last.to_s

      def replace_last_tag(store, iter)
        store.get_value(iter, 0).then do |tag|
          entry.text.split(' ').then do |words|
            entry.text = "#{(words[0...-1] + [tag]).join(' ')} "
            entry.position = -1
          end
        end

        true
      end
    end
  end
end
