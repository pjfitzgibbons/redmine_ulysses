# frozen_string_literal: true

module RedmineUlysses
  class Hooks < Redmine::Hook::ViewListener
    # Turbo and the plugin's entry module load only on the pages the plugin works on. The import
    # goes in the layout's header_tags, after core's javascript_importmap_tags, so it resolves
    # through the importmap.
    def view_issues_show_details_bottom(context = {})
      view = context[:hook_caller]
      view.content_for(:header_tags, view.javascript_import_module_tag('ulysses'))
      content_tag(:div, '', id: 'ulysses', hidden: true, data: { controller: 'ulysses' })
    end
  end
end
