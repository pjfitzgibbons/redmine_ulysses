# frozen_string_literal: true

require_relative '../test_helper'

# One test per row of design 0004 §3.2's answers table, each for a core field and a custom field,
# and one per check. jsmith (user 2) is a Manager on eCookbook, the author of issue 1, which is a
# Bug at New with lock_version 3.
class UlyssesFieldsControllerTest < Redmine::ControllerTest
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issues,
           :enumerations, :workflows, :custom_fields, :custom_values,
           :custom_fields_projects, :custom_fields_trackers, :versions, :issue_categories,
           :journals, :journal_details

  def setup
    User.current = nil
    @request.session[:user_id] = 2
    @issue = Issue.find(1)
    # New may go to Assigned only, so a save to Resolved is a key safe_attributes= drops.
    WorkflowTransition.where(tracker_id: 1, old_status_id: 1).delete_all
    WorkflowTransition.create!(role_id: 1, tracker_id: 1, old_status_id: 1, new_status_id: 2)

    fields = {is_for_all: true, tracker_ids: [1]}
    @text = IssueCustomField.create!(fields.merge(name: 'Ulysses text', field_format: 'string'))
    @number = IssueCustomField.create!(fields.merge(name: 'Ulysses number', field_format: 'int'))
    @lane = IssueCustomField.create!(fields.merge(name: 'Ulysses lane', field_format: 'list',
                                                  possible_values: %w(web cli)))
    @tags = IssueCustomField.create!(fields.merge(name: 'Ulysses tags', field_format: 'list',
                                                  possible_values: %w(red green blue), multiple: true))
    @hidden = IssueCustomField.create!(fields.merge(name: 'Ulysses hidden', field_format: 'string',
                                                    visible: false, role_ids: [2]))
    CustomValue.create!(customized: @issue, custom_field: @text, value: 'before')
    CustomValue.create!(customized: @issue, custom_field: @lane, value: 'web')
  end

  # Editing

  def test_edit_renders_the_editor_with_lock_version
    get :edit, params: {id: 1, field: 'status_id'}
    assert_response :success
    assert_select 'turbo-frame#ulysses-issue-1-status_id form[action=?]', '/ulysses/issues/1/fields/status_id' do
      assert_select 'input[name=lock_version][value="3"]'
      assert_select 'select[name=value] option', 2 # New, and Assigned, the one move allowed
    end
  end

  def test_edit_renders_a_custom_field_with_cores_control
    get :edit, params: {id: 1, field: "cf_#{@tags.id}"}
    assert_response :success
    assert_select "select[name='value[]'][multiple] option", 3
  end

  def test_edit_of_a_field_the_user_cant_change_is_403
    WorkflowPermission.create!(role_id: 1, tracker_id: 1, old_status_id: 1, field_name: @text.id.to_s, rule: 'readonly')
    get :edit, params: {id: 1, field: "cf_#{@text.id}"}
    assert_response :forbidden
    assert_select "turbo-frame#ulysses-issue-1-cf_#{@text.id} [role=alert]"
  end

  # Core's form takes a file field's upload, not a value.
  def test_edit_of_a_file_custom_field_is_403
    file = IssueCustomField.create!(name: 'Ulysses file', field_format: 'attachment', is_for_all: true, tracker_ids: [1])
    get :edit, params: {id: 1, field: "cf_#{file.id}"}
    assert_response :forbidden
  end

  # Set from the status, done_ratio is whatever the status says, and core's form hides it.
  def test_edit_of_done_ratio_set_from_the_status_is_403
    with_settings issue_done_ratio: 'issue_status' do
      get :edit, params: {id: 1, field: 'done_ratio'}
    end
    assert_response :forbidden
  end

  # editable_custom_field_values alone would let this one through.
  def test_edit_of_a_custom_field_without_edit_issues_is_403
    Role.find(1).remove_permission!(:edit_issues)
    get :edit, params: {id: 1, field: "cf_#{@text.id}"}
    assert_response :forbidden
  end

  def test_edit_of_an_unknown_field_is_404
    get :edit, params: {id: 1, field: 'author_id'}
    assert_response :not_found
  end

  # 200 saved

  def test_saved_core_field
    assert_difference 'Journal.count', 1 do
      save 'status_id', '2'
    end
    assert_response :success
    assert_equal 'text/vnd.turbo-stream.html', response.media_type
    assert_equal 2, @issue.reload.status_id
    assert_equal 'Assigned', rest_value('status_id').text.strip
    assert_select_in_stream 'ulysses-issue-1-status_id', '[role=status]'
    assert_equal '4', lock_version_streamed
    assert_one_journal_by_jsmith('attr', 'status_id', '1', '2')
  end

  def test_saved_custom_field
    assert_difference 'Journal.count', 1 do
      save "cf_#{@text.id}", 'after'
    end
    assert_response :success
    assert_equal 'after', @issue.reload.custom_field_value(@text)
    assert_equal 'after', rest_value("cf_#{@text.id}").text.strip
    assert_equal '4', lock_version_streamed
    assert_one_journal_by_jsmith('cf', @text.id.to_s, 'before', 'after')
  end

  def test_saved_multi_valued_custom_field
    save "cf_#{@tags.id}", %w(red blue)
    assert_response :success
    assert_equal %w(blue red), @issue.reload.custom_field_value(@tags).sort
    assert_equal %w(blue red), rest_value("cf_#{@tags.id}").text.strip.split(', ').sort
  end

  # A French user types 1,5; Redmine stores 1.5.
  def test_saved_float_custom_field_in_a_comma_locale
    User.find(2).update!(language: 'fr')
    float = IssueCustomField.create!(name: 'Ulysses float', field_format: 'float', is_for_all: true, tracker_ids: [1])
    save "cf_#{float.id}", '1,5'
    assert_response :success
    assert_equal '1.5', @issue.reload.custom_field_value(float)
  end

  # 200 unchanged, no journal

  def test_unchanged_core_field
    assert_no_difference 'Journal.count' do
      save 'status_id', '1'
    end
    assert_response :success
    assert_equal 3, @issue.reload.lock_version
    assert_equal '3', lock_version_streamed
  end

  def test_unchanged_custom_field
    assert_no_difference 'Journal.count' do
      save "cf_#{@text.id}", 'before'
    end
    assert_response :success
    assert_equal 3, @issue.reload.lock_version
  end

  def test_saved_reference_shows_as_text_in_the_editor_link
    save 'assigned_to_id', '3'
    assert_response :success
    link = rest_value('assigned_to_id')
    assert_equal 'a', link.name
    assert_equal 'Dave Lopper', link.text.strip
    assert_empty link.css('a')
  end

  def test_repeated_value_for_a_multi_valued_field_saves_once
    save "cf_#{@tags.id}", %w(red red)
    assert_response :success
    assert_equal %w(red), @issue.reload.custom_field_value(@tags)
  end

  def test_unchanged_value_with_a_note_is_saved_as_the_note
    with_settings plugin_redmine_ulysses: {'notes_required' => ["cf_#{@text.id}"]} do
      assert_difference 'Journal.count', 1 do
        save "cf_#{@text.id}", 'before', notes: 'Checked, still right'
      end
    end
    assert_response :success
    assert_equal 'Checked, still right', Journal.last.notes
    assert_select_in_stream "ulysses-issue-1-cf_#{@text.id}", '[role=status]'
  end

  # 403

  def test_core_field_without_edit_issues_is_403
    Role.find(1).remove_permission!(:edit_issues)
    assert_refused(:forbidden, 'status_id', '2', saved: 'New')
  end

  def test_custom_field_without_edit_issues_is_403
    Role.find(1).remove_permission!(:edit_issues)
    assert_refused(:forbidden, "cf_#{@text.id}", 'after', saved: 'before')
  end

  def test_role_without_any_update_permission_is_403
    Role.find(1).remove_permission!(:edit_issues, :add_issue_notes)
    assert_refused(:forbidden, 'status_id', '2', saved: 'New')
  end

  def test_core_field_read_only_in_the_workflow_is_403
    WorkflowPermission.create!(role_id: 1, tracker_id: 1, old_status_id: 1, field_name: 'due_date', rule: 'readonly')
    saved = format_date(@issue.due_date)
    assert_refused(:forbidden, 'due_date', '2030-01-01', saved: saved)
  end

  # gh-plan's baselines are custom fields the workflow makes read-only for every role but the
  # administrator's.
  def test_custom_field_read_only_in_the_workflow_is_403
    WorkflowPermission.create!(role_id: 1, tracker_id: 1, old_status_id: 1, field_name: @text.id.to_s, rule: 'readonly')
    assert_refused(:forbidden, "cf_#{@text.id}", 'after', saved: 'before')
  end

  # A field the user can't see is unknown, so its name isn't given away.
  def test_hidden_custom_field_is_404
    assert_no_difference 'Journal.count' do
      save "cf_#{@hidden.id}", 'after'
    end
    assert_response :not_found
    assert_not_includes response.body, @hidden.name
  end

  def test_a_key_safe_attributes_drops_is_403
    assert_refused(:forbidden, 'status_id', '3', saved: 'New')
  end

  def test_hidden_custom_field_value_is_not_shown_on_refusal
    CustomValue.create!(customized: @issue, custom_field: @hidden, value: 'secret')
    get :edit, params: {id: 1, field: "cf_#{@hidden.id}"}
    assert_response :not_found
    assert_not_includes response.body, 'secret'
    save "cf_#{@hidden.id}", 'after'
    assert_response :not_found
    assert_not_includes response.body, 'secret'
  end

  def test_field_needing_a_note_without_add_issue_notes_is_403
    Role.find(1).remove_permission!(:add_issue_notes)
    with_settings plugin_redmine_ulysses: {'notes_required' => ['due_date']} do
      assert_refused(:forbidden, 'due_date', '2030-01-01', saved: format_date(@issue.due_date))
    end
  end

  # 409

  def test_stale_core_field_is_409
    assert_conflict('subject', 'Mine', saved: 'Cannot print recipes')
  end

  def test_stale_custom_field_is_409
    assert_conflict("cf_#{@text.id}", 'mine', saved: 'before')
  end

  # set_issues_private alone makes is_private safe but not lock_version, which is checked anyway.
  def test_stale_save_without_edit_issues_is_409
    Role.find(1).remove_permission!(:edit_issues)
    assert_no_difference 'Journal.count' do
      save 'is_private', '1', lock_version: 2
    end
    assert_response :conflict
    assert_not @issue.reload.is_private?
  end

  # 422

  def test_core_field_failing_validation_is_422
    assert_invalid('subject', '', saved: 'Cannot print recipes')
  end

  def test_custom_field_failing_validation_is_422
    assert_invalid("cf_#{@number.id}", 'many', saved: '—')
  end

  def test_field_needing_a_note_without_one_is_422
    with_settings plugin_redmine_ulysses: {'notes_required' => ['due_date']} do
      assert_invalid('due_date', '2030-01-01', saved: format_date(@issue.due_date))
    end
  end

  def test_field_needing_a_note_saves_with_it_as_the_journals_notes
    with_settings plugin_redmine_ulysses: {'notes_required' => ["cf_#{@text.id}"]} do
      assert_difference 'Journal.count', 1 do
        save "cf_#{@text.id}", 'after', notes: 'Re-baselined after the scope change'
      end
    end
    assert_response :success
    assert_equal 'Re-baselined after the scope change', Journal.last.notes
    assert_one_journal_by_jsmith('cf', @text.id.to_s, 'before', 'after')
  end

  # A zero-padded id names the same field, and the same notes_required entry.
  def test_padded_custom_field_key_needs_its_note
    with_settings plugin_redmine_ulysses: {'notes_required' => ["cf_#{@text.id}"]} do
      assert_no_difference 'Journal.count' do
        save "cf_00#{@text.id}", 'after'
      end
      assert_response :unprocessable_content
      Role.find(1).remove_permission!(:add_issue_notes)
      assert_no_difference 'Journal.count' do
        save "cf_00#{@text.id}", 'after', notes: 'Why'
      end
      assert_response :forbidden
    end
    assert_equal 'before', @issue.reload.custom_field_value(@text)
  end

  # The editor names a value the issue doesn't offer, but never by a record the user can't see.
  def test_unavailable_version_of_a_project_the_user_cant_see_is_not_named
    version = Version.generate!(project: Project.generate!(is_public: false), name: 'Secret release')
    assert_unnamed_unavailable_choice 'fixed_version_id', version
  end

  def test_unavailable_category_of_a_project_the_user_cant_see_is_not_named
    category = IssueCategory.create!(project: Project.generate!(is_public: false), name: 'Secret category')
    assert_unnamed_unavailable_choice 'category_id', category
  end

  # 400

  def test_array_for_a_core_field_is_400
    assert_refused(:bad_request, 'subject', %w(one two), saved: 'Cannot print recipes')
  end

  # Invariant 8: an issue has at most one lane.
  def test_array_for_a_single_valued_list_field_is_400
    assert_refused(:bad_request, "cf_#{@lane.id}", %w(web cli), saved: 'web')
  end

  def test_string_for_a_multi_valued_field_is_400
    assert_refused(:bad_request, "cf_#{@tags.id}", 'red', saved: '—')
  end

  def test_missing_lock_version_is_400
    assert_no_difference 'Journal.count' do
      patch :update, params: {id: 1, field: 'subject', value: 'New subject'}
    end
    assert_response :bad_request
  end

  # A parent the user can't see answers as one that doesn't exist, so the answer doesn't say which.
  def test_hidden_parent_answers_as_a_missing_one
    hidden = Issue.generate!(project: Project.generate!(is_public: false))
    save 'parent_issue_id', hidden.id.to_s
    assert_response :unprocessable_content
    hidden_errors = stream_content('ulysses-issue-1-parent_issue_id').css('.ulysses-field-error li').map(&:text)
    save 'parent_issue_id', (Issue.maximum(:id) + 1).to_s
    assert_response :unprocessable_content
    assert_equal hidden_errors, stream_content('ulysses-issue-1-parent_issue_id').css('.ulysses-field-error li').map(&:text)
    assert_nil @issue.reload.parent_id
  end

  # Lost from sight between the first read and the answer

  def test_issue_hidden_before_a_conflict_answers_404
    assert_hidden_before_the_answer(:not_found) { save 'subject', 'Secret now', lock_version: 2 }
  end

  def test_issue_hidden_before_a_validation_failure_answers_404
    assert_hidden_before_the_answer(:not_found) { save 'subject', '' }
  end

  def test_issue_hidden_before_a_refusal_answers_404
    assert_hidden_before_the_answer(:not_found) { save 'status_id', '3' }
  end

  # The other checks

  def test_request_without_the_csrf_token_is_refused
    ActionController::Base.allow_forgery_protection = true
    assert_no_difference 'Journal.count' do
      save 'status_id', '2'
    end
    assert_response :unprocessable_content
    assert_equal 1, @issue.reload.status_id
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  def test_issue_the_user_cant_see_is_404
    issue = Issue.generate!(project: Project.generate!(is_public: false))
    assert_no_difference 'Journal.count' do
      patch :update, params: {id: issue.id, field: 'subject', value: 'Seen', lock_version: issue.lock_version}
    end
    assert_response :not_found
  end

  def test_api_key_is_not_accepted
    @request.session[:user_id] = nil
    patch :update, params: {id: 1, field: 'subject', value: 'By key', lock_version: 3,
                            key: User.find(2).api_key}
    assert_response :forbidden
    assert_equal 'Cannot print recipes', @issue.reload.subject
  end

  # L4: the save's p95 over 50 saves.
  def test_save_p95_is_within_500_ms
    times = Array.new(50) do |i|
      lock_version = @issue.reload.lock_version
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      save 'subject', "Subject #{i}", lock_version: lock_version
      assert_response :success
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
    p95 = times.sort[(times.size * 0.95).ceil - 1]
    puts format("\nUlysses save p95 over %d saves: %.1f ms", times.size, p95 * 1000)
    assert_operator p95, :<=, 0.5
  end

  private

  def save(field, value, lock_version: 3, notes: nil)
    patch :update, params: {id: 1, field: field, value: value, lock_version: lock_version, notes: notes}.compact
  end

  # A refused save: nothing written, and the field at its saved value with a message.
  def assert_refused(status, field, value, saved:)
    assert_no_difference 'Journal.count' do
      save field, value
    end
    assert_response status
    assert_equal saved, rest_value(field).text.strip
    assert_select_in_stream "ulysses-issue-1-#{field}", '[role=alert]'
    assert_equal 3, @issue.reload.lock_version
  end

  # A save from an old lock_version: 409, nothing saved, the editor kept with the user's value,
  # and beside it the current value, who changed it last and when, and the current lock_version.
  def assert_conflict(field, value, saved:)
    assert_no_difference 'Journal.count' do
      save field, value, lock_version: 2
    end
    assert_response :conflict
    assert_equal 3, @issue.reload.lock_version
    last = @issue.journals.reorder(:id).last
    frame = stream_content("ulysses-issue-1-#{field}")
    assert_equal value, frame.at_css('[name=value]')['value']
    conflict = frame.at_css('.ulysses-field-conflict')
    assert_includes conflict.text, last.user.name
    assert_includes conflict.text, format_time(last.created_on)
    assert_equal saved, conflict.at_css('.ulysses-field-current').text.strip
    assert_equal saved, rest_value(field).text.strip
    assert_equal '3', lock_version_streamed
  end

  # A save that fails validation: 422, nothing saved, the editor kept with the user's value and
  # Redmine's message, marked aria-invalid.
  def assert_invalid(field, value, saved:)
    assert_no_difference 'Journal.count' do
      save field, value
    end
    assert_response :unprocessable_content
    assert_equal 3, @issue.reload.lock_version
    frame = stream_content("ulysses-issue-1-#{field}")
    control = frame.at_css('[name=value]')
    assert_equal value, control['value']
    assert_equal 'true', control['aria-invalid']
    assert frame.at_css('.ulysses-field-error[role=alert] li')
    assert_equal saved, rest_value(field).text.strip
  end

  # A save of field needing a note, sent without one, to record: a 422 whose editor keeps record
  # selected but shows only its id.
  def assert_unnamed_unavailable_choice(field, record)
    with_settings plugin_redmine_ulysses: {'notes_required' => [field]} do
      save field, record.id.to_s
    end
    assert_response :unprocessable_content
    assert_not_includes response.body, record.name
    selected = stream_content("ulysses-issue-1-#{field}").at_css('[name=value] option[selected]')
    assert_equal record.id.to_s, selected['value']
    assert_equal "#{record.id} (not available now)", selected.text
  end

  # Issue.visible finds issue 1 for the first checks and nothing when the answer reads it again,
  # as if another request had meanwhile moved it out of the user's sight.
  def assert_hidden_before_the_answer(status)
    Issue.stubs(:visible).returns(Issue.where(id: 1)).then.returns(Issue.none)
    assert_no_difference('Journal.count') { yield }
    assert_response status
    assert_not_includes response.body, 'Cannot print recipes'
  end

  def assert_one_journal_by_jsmith(property, prop_key, old_value, value)
    journal = Journal.last
    assert_equal @issue, journal.journalized
    assert_equal User.find(2), journal.user
    assert_equal [[property, prop_key, old_value, value]],
                 journal.details.map {|d| [d.property, d.prop_key, d.old_value, d.value]}
  end

  # What a turbo-stream puts in place of the element target. HTML4 parses a template's content
  # as ordinary children, so it can be searched.
  def stream_content(target)
    streams = Nokogiri::HTML4.fragment(response.body)
    stream = streams.at_css("turbo-stream[action=replace][target='#{target}'] > template")
    assert stream, "no turbo-stream replaces ##{target}"
    stream
  end

  def assert_select_in_stream(target, selector)
    assert stream_content(target).at_css(selector), "##{target} has no #{selector}"
  end

  # The field at rest, as an answer draws it or as its editor keeps it for Cancel.
  def rest_value(field)
    frame = stream_content("ulysses-issue-1-#{field}")
    frame.at_css('.ulysses-field-saved .ulysses-field-value') ||
      frame.at_css('turbo-frame.ulysses-field > .ulysses-field-value')
  end

  def lock_version_streamed
    stream_content('ulysses-issue-1-lock-version').at_css('span')['data-lock-version']
  end

  def format_date(date)
    ApplicationController.helpers.format_date(date)
  end

  def format_time(time)
    ApplicationController.helpers.format_time(time)
  end
end
