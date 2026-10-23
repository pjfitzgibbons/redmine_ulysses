# frozen_string_literal: true

module RedmineUlysses
  # One field of an issue, named as the routes name it: a core attribute such as status_id, or
  # cf_<id> for a custom field.
  class Field
    # The core attributes edited in place. Spent time, attachments, watchers, relations and the
    # project stay as core shows them (design 0004 §3.3).
    CORE = %w(tracker_id status_id priority_id subject description assigned_to_id category_id
              fixed_version_id parent_issue_id start_date due_date estimated_hours done_ratio
              is_private).freeze

    attr_reader :key, :custom_field

    # The field named key, or nil when key names none. A custom field's key is built again from its
    # id, so cf_007 is cf_7 wherever the key is compared, notes_required included.
    def self.find(key)
      key = key.to_s
      if (m = key.match(/\Acf_(\d+)\z/))
        custom_field = IssueCustomField.find_by(id: m[1])
        new("cf_#{custom_field.id}", custom_field) if custom_field
      elsif CORE.include?(key)
        new(key)
      end
    end

    def initialize(key, custom_field = nil)
      @key = key
      @custom_field = custom_field
    end

    def label
      custom_field ? custom_field.name : Issue.human_attribute_name(key)
    end

    def multiple?
      custom_field&.multiple? || false
    end

    # Whether user may change this field of issue now. Both lists apply the role's permissions and
    # the workflow's read-only rules for the issue's tracker and status. editable_custom_field_values
    # doesn't ask whether the user may edit the issue's attributes at all, so a custom field also
    # needs custom_field_values among the safe attributes. A file field posts an upload, not a
    # value, and done_ratio set from the status can't be set at all, as core's form hides it.
    def editable?(issue, user)
      if custom_field
        custom_field.field_format != 'attachment' &&
          issue.safe_attribute_names(user).include?('custom_field_values') &&
          issue.editable_custom_field_values(user).any? {|v| v.custom_field_id == custom_field.id}
      elsif key == 'done_ratio'
        Issue.use_field_for_done_ratio? && issue.safe_attribute_names(user).include?(key)
      else
        issue.safe_attribute_names(user).include?(key)
      end
    end

    # Whether user may see this field of issue at all.
    def visible?(issue, user)
      custom_field.nil? || issue.visible_custom_field_values(user).any? {|v| v.custom_field_id == custom_field.id}
    end

    # Whether value has the field's shape: an array for a multi-valued field, a string otherwise.
    def accepts?(value)
      multiple? ? value.is_a?(Array) && value.all?(String) : value.is_a?(String)
    end

    def notes_required?
      Array((Setting.plugin_redmine_ulysses || {})['notes_required']).include?(key)
    end

    # The attributes safe_attributes= takes to set the field to value, as the edit form sends them.
    def attributes(value)
      if custom_field
        {'custom_field_values' => {custom_field.id.to_s => value}}
      else
        {key => value}
      end
    end

    # What issue holds now, in the form normalize gives.
    def current(issue)
      custom_field ? normalize(issue, issue.custom_field_value(custom_field)) : issue.send(key)
    end

    # value as issue would hold it, so a requested value compares with current. A custom value
    # goes through its format, which writes a float with a point whatever the user's locale. A core
    # value goes through the attribute's own setter on a scratch issue, which casts it as a save
    # would.
    def normalize(issue, value)
      if multiple?
        Array(value).map(&:to_s).reject(&:blank?).uniq.sort
      elsif custom_field
        custom_field.set_custom_field_value(CustomFieldValue.new(custom_field: custom_field), value).to_s.presence
      elsif key == 'parent_issue_id'
        normalize_parent(issue, value)
      else
        probe = Issue.new
        probe.send("#{key}=", value)
        probe.send(key)
      end
    end

    # The object shown at rest: the associated record for a reference, the value otherwise. A
    # custom field's value comes from custom_field_values, which holds every value of a
    # multi-valued field; custom_value_for gives only the first.
    def object(issue)
      return issue.custom_field_values.detect {|v| v.custom_field_id == custom_field.id} if custom_field

      case key
      when 'parent_issue_id' then issue.parent
      when /\A(.+)_id\z/ then issue.send($1)
      else issue.send(key)
      end
    end

    private

    # A parent as safe_attributes= takes it: an issue the user may see, or the current parent, is
    # set by id, and anything else is kept as sent, invalid, so the save fails as core's form does.
    # The scratch issue's setter would find an issue the user can't see.
    def normalize_parent(issue, value)
      s = value.to_s.strip.presence
      return nil unless s

      m = s.match(/\A#?(\d+)\z/)
      if m && (m[1] == issue.parent_id.to_s || Issue.visible.exists?(m[1]))
        m[1].to_i
      else
        value
      end
    end
  end
end
