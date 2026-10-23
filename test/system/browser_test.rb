# frozen_string_literal: true

require_relative '../application_system_test_case'

# The browser side the plugin builds on: Turbo loaded with Drive off, the plugin's Stimulus
# controllers registered through core's importmap, and turbo-stream answers applied whatever
# their status.
class BrowserTest < UlyssesSystemTestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issues,
           :enumerations, :workflows, :journals, :journal_details

  def test_chromium_renders_redmine
    visit '/login'
    assert_selector '#login-form'
  end

  def test_turbo_loads_with_drive_off_on_the_issue_page
    log_user('jsmith', 'jsmith')
    visit '/issues/1'
    wait_for_ulysses
    assert_equal false, page.evaluate_script('Turbo.session.drive')
  end

  # Module scripts run before the load event visit waits for, so Turbo would be there by now.
  def test_turbo_stays_off_pages_the_plugin_does_not_use
    visit '/login'
    assert_selector '#login-form'
    assert_not turbo_loaded?, 'Turbo loaded on the login page'
  end

  def test_plugin_controller_connects_on_the_issue_page
    log_user('jsmith', 'jsmith')
    visit '/issues/1'
    assert_selector '#ulysses[data-ulysses-connected="true"]', visible: :all
  end

  def test_turbo_stream_with_status_409_is_applied
    log_user('jsmith', 'jsmith')
    visit '/ulysses/probe'
    wait_for_ulysses
    mark_page
    click_button 'Save'
    assert_selector '#ulysses-probe', text: 'changed by someone else'
    assert page.evaluate_script('window.ulyssesMarker === true'), 'the page reloaded'
  end

  def test_core_link_is_a_full_page_load
    log_user('jsmith', 'jsmith')
    visit '/issues/1'
    wait_for_ulysses
    mark_page
    within('#main-menu') { click_link 'Issues' }
    assert_current_path '/projects/ecookbook/issues'
    assert_full_page_load
  end

  # Turbo's own popstate listener would answer Back with a restoration visit, which swaps the
  # body for a snapshot and loses whatever was typed. A marker on the body survives only if the
  # body is never replaced.
  def test_back_and_forward_over_a_fragment_keep_the_page
    log_user('jsmith', 'jsmith')
    visit '/issues/1'
    wait_for_ulysses
    page.first(:link, 'Edit').click
    fill_in 'issue_notes', with: 'Unsaved'
    page.execute_script('document.body.ulyssesMarker = true')
    page.execute_script("location.hash = 'note-1'")
    assert_equal '#note-1', page.evaluate_script('location.hash')
    page.go_back
    assert_equal '', page.evaluate_script('location.hash')
    assert_body_kept_with_notes 'Unsaved'
    page.go_forward
    assert_equal '#note-1', page.evaluate_script('location.hash')
    assert_body_kept_with_notes 'Unsaved'
    assert_equal 'auto', page.evaluate_script('history.scrollRestoration')
  end

  def test_core_form_is_a_full_page_load
    log_user('jsmith', 'jsmith')
    visit '/issues/1'
    wait_for_ulysses
    mark_page
    page.first(:link, 'Edit').click
    fill_in 'issue_notes', with: 'A note through the core form'
    within('#issue-form') { click_button 'Submit' }
    assert_text 'A note through the core form'
    assert_full_page_load
  end
end
