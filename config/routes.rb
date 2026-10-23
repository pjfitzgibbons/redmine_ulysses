# frozen_string_literal: true

# Core's routes file evaluates this one inside its draw block. Neither route takes a format, so
# neither has a .json form that would skip the session and the CSRF check.
constraints id: /\d+/, field: /[a-z0-9_]+/ do
  get 'ulysses/issues/:id/fields/:field/edit', to: 'ulysses_fields#edit', format: false,
                                               as: 'edit_ulysses_issue_field'
  patch 'ulysses/issues/:id/fields/:field', to: 'ulysses_fields#update', format: false,
                                            as: 'ulysses_issue_field'
end
