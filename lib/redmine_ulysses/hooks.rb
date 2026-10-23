# frozen_string_literal: true

module RedmineUlysses
  class Hooks < Redmine::Hook::ViewListener
    # The site's theme, in the one place Ulysses looks for it. Redmine serves public/ as it is.
    SITE_THEME = 'ulysses/theme.css'

    # The theme loads on every page, after core's stylesheet and any Redmine theme: the reference
    # tokens, base.css drawing Redmine from them, then the site's theme file if there is one. Its
    # link carries the file's modification time, so a browser fetches a changed file without a
    # restart.
    def view_layouts_base_html_head(context = {})
      tags = [stylesheet_link_tag('tokens', 'base', plugin: 'redmine_ulysses', media: 'all')]
      path = Rails.public_path.join(SITE_THEME)
      if path.file?
        href = "#{Redmine::Utils.relative_url_root}/#{SITE_THEME}?v=#{path.mtime.to_i}"
        tags << tag.link(rel: 'stylesheet', href: href, media: 'all')
      end
      safe_join(tags, "\n")
    end

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
