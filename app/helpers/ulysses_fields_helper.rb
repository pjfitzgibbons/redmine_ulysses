# frozen_string_literal: true

module UlyssesFieldsHelper
  # The field's turbo-frame, which every answer replaces.
  def ulysses_field_dom_id(issue, field)
    "ulysses-issue-#{issue.id}-#{field.key}"
  end

  # The one element per issue that holds its lock_version for the next save.
  def ulysses_lock_version_dom_id(issue)
    "ulysses-issue-#{issue.id}-lock-version"
  end

  # The field's value as the issue page shows it, as text: the rest view is a link to the editor,
  # and core's formatting links users, versions and issues. A field the user may not see shows
  # nothing.
  def ulysses_field_text(issue, field)
    return '' unless field.visible?(issue, User.current)

    case field.key
    when 'done_ratio' then "#{issue.done_ratio}%"
    when 'estimated_hours' then format_hours(issue.estimated_hours)
    else format_object(field.object(issue), html: false)
    end
  end

  # The field's control, named value as the PATCH route takes it, showing value. A custom field
  # uses core's own control for its format.
  def ulysses_field_control(issue, field, value, options = {})
    tag_id = "#{ulysses_field_dom_id(issue, field)}-value"
    options = options.merge(id: tag_id)
    if field.custom_field
      custom_value = CustomFieldValue.new(custom_field: field.custom_field, customized: issue, value: value)
      return field.custom_field.format.edit_tag(self, tag_id, field.multiple? ? 'value[]' : 'value',
                                                custom_value, options)
    end

    case field.key
    when 'description'
      textarea_tag('value', value, options.merge(rows: 8))
    when 'start_date', 'due_date'
      date_field_tag('value', value, options)
    when 'is_private'
      hidden_field_tag('value', '0', id: nil) +
        check_box_tag('value', '1', ActiveModel::Type::Boolean.new.cast(value), options)
    else
      if (choices = ulysses_field_choices(issue, field))
        choices = ulysses_with_unavailable_choice(issue, field, choices, value)
        select_tag('value', options_for_select(choices, value.to_s), options)
      else
        text_field_tag('value', value, options)
      end
    end
  end

  # choices with value added, labelled as not available, when the issue no longer allows it. A
  # 409 or 422 draws the choices from the issue as it is now; without this the select would show
  # its first option in place of the user's. A custom field's own control already does this.
  def ulysses_with_unavailable_choice(issue, field, choices, value)
    return choices if value.blank? || choices.any? {|_, v| v == value.to_s}

    name = ulysses_choice_name(issue, field, value).presence || value.to_s
    choices + [[l(:ulysses_label_unavailable, value: name), value.to_s]]
  end

  # The name of the record value refers to, looked up only among the records the user may see. The
  # value comes from the request, and may name a version or category of a project the user can't
  # see; then it is shown as sent.
  def ulysses_choice_name(issue, field, value)
    record =
      case field.key
      when 'tracker_id' then Tracker.visible.find_by(id: value)
      when 'status_id' then IssueStatus.find_by(id: value)
      when 'priority_id' then IssuePriority.find_by(id: value)
      when 'assigned_to_id' then Principal.visible.find_by(id: value)
      when 'category_id' then issue.project.issue_categories.find_by(id: value)
      when 'fixed_version_id' then Version.visible.find_by(id: value)
      end
    record&.to_s
  end

  # The values a list field may take, as [label, value] pairs, or nil for a field typed in.
  def ulysses_field_choices(issue, field)
    blank = [['', '']]
    case field.key
    when 'tracker_id' then issue.allowed_target_trackers.map {|t| [t.name, t.id.to_s]}
    when 'status_id' then issue.new_statuses_allowed_to(User.current).map {|s| [s.name, s.id.to_s]}
    when 'priority_id' then IssuePriority.active.map {|p| [p.name, p.id.to_s]}
    when 'assigned_to_id' then blank + issue.assignable_users.map {|u| [u.name, u.id.to_s]}
    when 'category_id' then blank + issue.project.issue_categories.map {|c| [c.name, c.id.to_s]}
    when 'fixed_version_id' then blank + issue.assignable_versions.map {|v| [v.to_s, v.id.to_s]}
    when 'done_ratio' then (0..100).step(10).map {|n| ["#{n}%", n.to_s]}
    end
  end
end
