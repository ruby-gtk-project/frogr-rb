# frozen_string_literal: true

require_relative 'selection_list_dialog'

module Frogr
  module Ui
    # Queues the selected pictures for one or more of the account's sets.
    #
    # Locally-created sets are offered alongside the ones fetched from Flickr,
    # since a picture can be queued for a set that does not exist remotely yet.
    class AddToSetDialog < SelectionListDialog
      private

      def dialog_title = 'Add to Sets'

      def empty_message = 'No sets found for this account'

      def label_for(set) = set.display_title

      def already_in?(picture, set) = picture.in_photoset?(set)

      def apply(picture, set) = picture.add_photoset(set)

      def fetch_items(on_finished, on_error)
        @controller.fetch_photosets(
          on_finished: ->(_) { on_finished.call(@controller.model.photosets) },
          on_error: on_error
        )
      end
    end
  end
end
