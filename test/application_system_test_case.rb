# frozen_string_literal: true

require File.expand_path('../../../test/application_system_test_case', __dir__)
require_relative 'support/ulysses_probe_controller'

class UlyssesSystemTestCase < ApplicationSystemTestCase
  # Turbo Drive replaces the page without reloading it, and a reload clears window. A marker
  # that survives a click means the page was never reloaded.
  def mark_page
    page.execute_script('window.ulyssesMarker = true')
  end

  def assert_full_page_load
    assert_not page.evaluate_script('window.ulyssesMarker === true'), 'expected a full page load'
  end

  def wait_for_ulysses
    deadline = Time.now + Capybara.default_max_wait_time
    sleep 0.05 until turbo_loaded? || Time.now > deadline
    assert turbo_loaded?, 'Turbo did not load'
  end

  def turbo_loaded?
    page.evaluate_script('window.Turbo !== undefined')
  end
end
