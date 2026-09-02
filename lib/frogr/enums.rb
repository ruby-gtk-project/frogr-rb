# frozen_string_literal: true

module Frogr
  # The Flickr API vocabulary, kept as integer-valued maps because the numbers
  # are what the API and the on-disk settings file both speak. Each map is
  # ordered the way its dropdown should be, so the UI can build its model from
  # `.keys` and translate a selected index back through `.values`.
  module Enums
    SAFETY_LEVELS = {
      'Safe' => 1,
      'Moderate' => 2,
      'Restricted' => 3
    }.freeze

    CONTENT_TYPES = {
      'Photo' => 1,
      'Screenshot' => 2,
      'Other' => 3
    }.freeze

    LICENSES = {
      'None' => -1,
      'All rights reserved' => 0,
      'CC Attribution-NonCommercial-ShareAlike' => 1,
      'CC Attribution-NonCommercial' => 2,
      'CC Attribution-NonCommercial-NoDerivs' => 3,
      'CC Attribution' => 4,
      'CC Attribution-ShareAlike' => 5,
      'CC Attribution-NoDerivs' => 6
    }.freeze

    # flickr.photos.geo.setLocation's `context` argument.
    LOCATION_CONTEXTS = {
      unknown: 0,
      indoors: 1,
      outdoors: 2
    }.freeze

    # `hidden` in the upload API: 1 shows the photo in searches, 2 hides it.
    SEARCH_SCOPE_PUBLIC = 1
    SEARCH_SCOPE_HIDDEN = 2

    # Ordering offered by the View menu; the integer is what settings.xml stores.
    SORTING_CRITERIA = {
      as_loaded: 0,
      by_title: 1,
      by_date: 2,
      by_size: 3
    }.freeze

    module_function

    # Dropdowns are index-based, so every enum needs both directions.
    def index_of(map, value) = map.values.index(value) || 0

    def value_at(map, index) = map.values[index] || map.values.first

    def sorting_criteria_from_int(int)
      SORTING_CRITERIA.key(int) || :as_loaded
    end
  end
end
