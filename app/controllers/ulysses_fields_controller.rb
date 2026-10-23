# frozen_string_literal: true

# Opens and saves one field of one issue (design 0004 §3.2). The routes have no .json suffix, so
# they take the session and check the CSRF token, never an API key. Each outcome has its own
# status, and a PATCH answers with Turbo Streams: the field, and the issue's lock_version.
class UlyssesFieldsController < ApplicationController
  helper :custom_fields
  helper :issues
  helper UlyssesFieldsHelper

  # The checks, in order. Rails has checked the CSRF token before any of them.
  before_action :find_issue, :find_field, :authorize_update, :check_editable
  before_action :check_shape, only: :update

  def edit
    render partial: 'editor', locals: editor_locals(@field.current(@issue))
  end

  def update
    value = params[:value]
    notes = params[:notes].to_s.strip
    if @field.notes_required? && !@issue.notes_addable?(User.current)
      return refuse(:forbidden, l(:ulysses_error_not_editable, field: @field.label))
    end
    if @field.notes_required? && notes.empty?
      return answer_editor(:unprocessable_content, value,
                           errors: [l(:ulysses_error_notes_required, field: @field.label)])
    end

    requested = @field.normalize(@issue, value)
    @issue.init_journal(User.current, @field.notes_required? ? notes : nil)
    @issue.safe_attributes = @field.attributes(value)
    # Set apart from safe_attributes=, which keeps lock_version only for a user who may edit the
    # issue's attributes, so every save, is_private's too, is checked for staleness.
    @issue.lock_version = params[:lock_version].to_i
    # safe_attributes= deletes a key the user may not set without a word, and a save with
    # nothing changed succeeds, so a dropped value is caught here.
    return refuse(:forbidden, l(:ulysses_error_not_editable, field: @field.label)) unless @field.current(@issue) == requested

    if @issue.save
      # Redmine skips an empty journal, so a journal saved means something changed, a note
      # included.
      answer_rest(:ok, outcome: @issue.current_journal.persisted? ? :saved : :unchanged)
    else
      answer_editor(:unprocessable_content, value, errors: @issue.errors.full_messages)
    end
  rescue ActiveRecord::StaleObjectError
    answer_editor(:conflict, value, conflict: true)
  end

  private

  def find_issue
    @issue = Issue.visible.find_by(id: params[:id])
    return render_404 unless @issue

    @project = @issue.project
  end

  # A custom field the user may not see is as unknown as one that doesn't exist, so its name isn't
  # given away.
  def find_field
    @field = RedmineUlysses::Field.find(params[:field])
    render_404 unless @field&.visible?(@issue, User.current)
  end

  # As the edit form is authorized.
  def authorize_update
    return if User.current.allowed_to?({controller: 'issues', action: 'update'}, @project)

    refuse(:forbidden, l(:ulysses_error_not_editable, field: @field.label))
  end

  def check_editable
    return if @field.editable?(@issue, User.current)

    refuse(:forbidden, l(:ulysses_error_not_editable, field: @field.label))
  end

  # An array only for a multi-valued field (invariant 8), and a lock_version always.
  def check_shape
    return if @field.accepts?(params[:value]) && params[:lock_version].to_s.match?(/\A\d+\z/)

    refuse(:bad_request, l(:ulysses_error_shape, field: @field.label))
  end

  # The field at its saved value, with message. An edit is a frame load, so it answers HTML.
  def refuse(status, message)
    if request.get?
      render partial: 'rest', locals: {issue: @issue, field: @field, message: message}, status: status
    else
      answer_rest(status, message: message)
    end
  end

  def answer_rest(status, message: nil, outcome: nil)
    return if status != :ok && !reload_issue

    answer status, 'rest', issue: @issue, field: @field, message: message, outcome: outcome
  end

  # The editor stays open with the user's value. The issue is read again for its saved value,
  # its lock_version and, on a conflict, who changed it last.
  def answer_editor(status, value, errors: [], conflict: false)
    return unless reload_issue

    locals = editor_locals(value).merge(errors: errors)
    if conflict
      last = @issue.journals.visible.reorder(:id).last
      locals[:conflict] =
        if last
          {author: last.user, time: last.created_on}
        else
          {author: @issue.author, time: @issue.updated_on}
        end
    end
    answer status, 'editor', locals
  end

  # The issue as saved, or a 404 if another request has meanwhile put it out of the user's sight.
  def reload_issue
    @issue = Issue.visible.find_by(id: @issue.id)
    render_404 unless @issue
    @issue
  end

  def editor_locals(value)
    {issue: @issue, field: @field, value: value, errors: [], conflict: nil}
  end

  def answer(status, partial, locals)
    render 'answer', formats: [:turbo_stream], status: status,
                     locals: {partial: partial, partial_locals: locals}
  end
end
