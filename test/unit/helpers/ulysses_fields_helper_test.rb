# frozen_string_literal: true

require_relative '../../test_helper'

class UlyssesFieldsHelperTest < Redmine::HelperTest
  include UlyssesFieldsHelper

  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issues,
           :enumerations, :workflows

  # A 409 or 422 draws the choices from the issue as it is now. When the workflow no longer lets
  # New go to Assigned, the user's Assigned stays selected, marked, rather than the first option.
  def test_control_keeps_a_choice_the_issue_no_longer_allows
    User.current = User.find(2)
    WorkflowTransition.where(tracker_id: 1, old_status_id: 1, new_status_id: 2).delete_all
    html = ulysses_field_control(Issue.find(1), RedmineUlysses::Field.find('status_id'), '2')
    options = Nokogiri::HTML4.fragment(html).css('option').map {|o| [o.text, o['value'], o.key?('selected')]}
    assert_includes options, ['New', '1', false]
    assert_equal ['Assigned (not available now)', '2', true], options.last
    assert_equal 1, options.count {|o| o[2]}
  end

  def test_control_adds_nothing_for_an_allowed_choice
    User.current = User.find(2)
    html = ulysses_field_control(Issue.find(1), RedmineUlysses::Field.find('priority_id'), '5')
    assert_not_includes html, 'not available'
  end
end
