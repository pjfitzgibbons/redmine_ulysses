# frozen_string_literal: true

require_relative '../application_system_test_case'

# The theme in the browser: the plugin's stylesheets after core's, a site's
# public/ulysses/theme.css read without a restart, and every stylesheet and font on the page
# served from Redmine itself.
class ThemeInBrowserTest < UlyssesSystemTestCase
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issues,
           :enumerations, :workflows, :journals, :journal_details

  SITE_DIR = Rails.public_path.join('ulysses')
  FONT = File.expand_path('../../assets/stylesheets/fonts/IBMPlexSerif-Regular.woff2', __dir__)
  PAGES = ['/issues/1', '/projects/ecookbook/issues'].freeze

  def setup
    super
    log_user('jsmith', 'jsmith')
  end

  def teardown
    FileUtils.rm_rf(SITE_DIR)
    super
  end

  def test_links_come_after_core_stylesheet
    visit '/issues/1'
    hrefs = page.evaluate_script(
      "[...document.querySelectorAll('head link[rel=stylesheet]')].map(l => l.getAttribute('href'))"
    )
    core = hrefs.index { |h| h.include?('/application') }
    tokens = hrefs.index { |h| h.include?('redmine_ulysses/tokens') }
    base = hrefs.index { |h| h.include?('redmine_ulysses/base') }
    assert core && tokens && base, hrefs.inspect
    assert_operator core, :<, tokens
    assert_operator tokens, :<, base
  end

  def test_reference_theme_without_a_site_file
    visit '/issues/1'
    assert_equal '#0b5aa8', root_property('--uly-primary')
    assert_match(/\A"?IBM Plex Sans/, page.evaluate_script('getComputedStyle(document.body).fontFamily'))
    assert_no_selector 'link[href*="ulysses/theme.css"]', visible: :all
  end

  # The two writes take times no other test uses: the container's filesystem keeps whole seconds,
  # and a file another test wrote in the same second would share its ?v= and come from the cache.
  def test_site_file_overrides_and_a_change_shows_after_a_reload
    write_theme(':root { --uly-primary: #00563f; }', mtime: Time.at(1_700_000_000))
    visit '/issues/1'
    assert_equal '#00563f', root_property('--uly-primary')
    assert_equal '#0d1321', root_property('--uly-ink'), 'a property the file leaves out keeps the reference'
    assert_equal 'rgb(0, 86, 63)', link_color

    write_theme(':root { --uly-primary: #6a1b9a; }', mtime: Time.at(1_700_000_060))
    page.refresh
    assert_equal '#6a1b9a', root_property('--uly-primary')
  end

  # L6 and L9: no failed stylesheet or font, and nothing fetched from another host.
  def test_pages_load_every_stylesheet_and_font_from_their_own_host
    [nil, site_theme_with_a_font].each do |theme|
      write_theme(theme) if theme
      PAGES.each do |path|
        visit path
        assert_resources_ok("#{path} #{theme ? 'with' : 'without'} a site theme")
      end
    end
    assert_equal '"Site Serif", serif', root_property('--uly-font-serif')
  end

  private

  def root_property(name)
    page.evaluate_script("getComputedStyle(document.documentElement).getPropertyValue('#{name}')").strip
  end

  # The colour of a plain link in the content, which core draws in its link blue.
  def link_color
    page.evaluate_script(<<~JS)
      (() => {
        const a = document.createElement('a');
        a.href = '#';
        a.textContent = 'a link';
        document.getElementById('content').append(a);
        return getComputedStyle(a).color;
      })()
    JS
  end

  def write_theme(css, mtime: Time.now)
    FileUtils.mkdir_p(SITE_DIR)
    path = SITE_DIR.join('theme.css')
    File.write(path, css)
    File.utime(mtime, mtime, path)
  end

  # A site theme with its own font beside it, which the header's serif uses.
  def site_theme_with_a_font
    FileUtils.mkdir_p(SITE_DIR.join('fonts'))
    FileUtils.cp(FONT, SITE_DIR.join('fonts/site-serif.woff2'))
    <<~CSS
      @font-face { font-family: "Site Serif"; src: url("fonts/site-serif.woff2") format("woff2"); }
      :root { --uly-font-serif: "Site Serif", serif; }
    CSS
  end

  # Loads every font face the page declares, used or not, then checks each stylesheet, font and
  # other resource the page fetched.
  def assert_resources_ok(where)
    result = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1];
      Promise.allSettled([...document.fonts].map(f => f.load())).then(() => done({
        sheets: [...document.querySelectorAll('link[rel=stylesheet]')]
          .map(l => ({ href: l.href, ok: !!l.sheet })),
        fonts: [...document.fonts].map(f => ({ family: f.family, weight: f.weight, status: f.status })),
        resources: performance.getEntriesByType('resource')
          .map(r => ({ name: r.name, status: r.responseStatus, type: r.initiatorType })),
        host: location.host
      }));
    JS
    failed_sheets = result['sheets'].reject { |s| s['ok'] }
    assert_empty failed_sheets, "#{where}: stylesheets that failed"
    assert_operator result['fonts'].size, :>=, 9, "#{where}: #{result['fonts'].inspect}"
    failed_fonts = result['fonts'].reject { |f| f['status'] == 'loaded' }
    assert_empty failed_fonts, "#{where}: fonts that failed"
    failed = result['resources'].select { |r| r['status'].to_i >= 400 }
    assert_empty failed, "#{where}: requests that failed"
    foreign = result['resources'].reject do |r|
      uri = URI(r['name'])
      [uri.host, "#{uri.host}:#{uri.port}"].include?(result['host'])
    end
    assert_empty foreign, "#{where}: requests off the page's host"
  end
end
