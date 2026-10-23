# frozen_string_literal: true

require_relative '../test_helper'

# The plugin leaves the REST API as core has it. The snapshots hold every key path of an answer
# from Redmine 7.0.2's fixtures; a key the plugin adds or loses fails here. After a Redmine
# upgrade, check the new keys are core's, then rewrite the snapshots with ULYSSES_SNAPSHOT=1.
class ApiKeysTest < Redmine::ApiTest::Base
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issues,
           :enumerations, :workflows, :custom_fields, :custom_values,
           :custom_fields_projects, :custom_fields_trackers, :versions, :issue_categories

  SNAPSHOTS = File.expand_path('../snapshots', __dir__)

  def test_issue_keys
    get '/issues/1.json', headers: credentials('admin')
    assert_response :success
    assert_keys 'issue.json'
  end

  def test_issues_keys
    get '/issues.json', headers: credentials('admin')
    assert_response :success
    assert_keys 'issues.json'
  end

  private

  def assert_keys(name)
    keys = key_paths(response.parsed_body).join("\n") + "\n"
    path = File.join(SNAPSHOTS, "#{name}.keys")
    File.write(path, keys) if ENV['ULYSSES_SNAPSHOT'] == '1'
    assert File.exist?(path), "No snapshot #{name}.keys: write it with ULYSSES_SNAPSHOT=1 bin/test"
    assert_equal File.read(path), keys
  end

  # Every key path, with [] for an array's elements, sorted and without repeats.
  def key_paths(value, prefix = nil)
    case value
    when Hash
      value.flat_map do |k, v|
        path = [prefix, k].compact.join('.')
        [path, *key_paths(v, path)]
      end
    when Array
      value.flat_map { |v| key_paths(v, "#{prefix}[]") }
    else
      []
    end.uniq.sort
  end
end
