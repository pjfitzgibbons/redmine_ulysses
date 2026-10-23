# frozen_string_literal: true

# A page in Redmine's layout with one Turbo form, and an endpoint that answers it the way a stale
# save will: a turbo-stream with status 409. It and its routes exist only while the system tests
# run.
class UlyssesProbeController < ApplicationController
  def show
    render html: <<~HTML.html_safe, layout: 'base'
      #{helpers.javascript_import_module_tag('ulysses')}
      <div id="ulysses-probe">at rest</div>
      <form action="/ulysses/probe/conflict" method="post" data-turbo="true">
        <button type="submit">Save</button>
      </form>
    HTML
  end

  def conflict
    # render html: would answer text/html whatever content_type says.
    render body: <<~HTML, status: :conflict, content_type: 'text/vnd.turbo-stream.html'
      <turbo-stream action="replace" target="ulysses-probe">
        <template><div id="ulysses-probe">changed by someone else</div></template>
      </turbo-stream>
    HTML
  end
end

Rails.application.routes.append do
  get 'ulysses/probe', to: 'ulysses_probe#show'
  post 'ulysses/probe/conflict', to: 'ulysses_probe#conflict'
end
# The routes may already be drawn; drawing them again takes in the appended ones.
Rails.application.reload_routes!
