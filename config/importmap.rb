# frozen_string_literal: true

# Drawn into core's importmap by init.rb. Redmine serves assets/javascripts/ at
# plugin_assets/redmine_ulysses/. Turbo and ulysses aren't preloaded, so pages that don't import
# ulysses (lib/redmine_ulysses/hooks.rb) don't download them.

pin '@hotwired/turbo', to: 'plugin_assets/redmine_ulysses/turbo.js', preload: false # @8.0.23
pin 'ulysses', to: 'plugin_assets/redmine_ulysses/ulysses.js', preload: false
pin_all_from File.expand_path('../assets/javascripts/controllers', __dir__),
             under: 'controllers', to: 'plugin_assets/redmine_ulysses/controllers'
