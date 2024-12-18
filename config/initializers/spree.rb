# frozen_string_literal: true

Spree::Backend::Config.configure do |config|
  # NOTE: Modified from original
  # We add the importer menu item manually, thus allowing us easy modification
  # on our system.
end

Mime::Type.register "application/csv", "csv"
