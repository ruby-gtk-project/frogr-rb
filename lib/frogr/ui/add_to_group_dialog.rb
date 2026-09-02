# frozen_string_literal: true

require_relative 'selection_list_dialog'

module Frogr
  module Ui
    # Queues the selected pictures for one or more of the account's group pools.
    class AddToGroupDialog < SelectionListDialog
      private

      def dialog_title = 'Add to Groups'

      def empty_message = 'No groups found for this account'

      def label_for(group) = group.display_name

      def already_in?(picture, group) = picture.in_group?(group)

      def apply(picture, group) = picture.add_group(group)

      def fetch_items(on_finished, on_error)
        @controller.fetch_groups(
          on_finished: ->(_) { on_finished.call(@controller.model.groups) },
          on_error: on_error
        )
      end
    end
  end
end
