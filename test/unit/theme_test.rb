# frozen_string_literal: true

require_relative '../test_helper'
require 'open3'

# The theme contract, the reference theme and the check a site's theme file passes.
class ThemeTest < ActiveSupport::TestCase
  Theme = RedmineUlysses::Theme
  PLUGIN = File.expand_path('../..', __dir__)
  STYLESHEETS = File.join(PLUGIN, 'assets/stylesheets')

  def reference
    File.read(Theme::REFERENCE)
  end

  def test_check_passes_on_the_reference
    assert_equal [], Theme.check(reference)
  end

  def test_check_passes_on_an_empty_theme_file
    assert_equal [], Theme.check('')
  end

  def test_check_passes_on_a_theme_that_sets_some_properties_and_a_font
    css = <<~CSS
      @font-face { font-family: "Site Serif"; src: url("fonts/site.woff2") format("woff2"); }
      :root { --uly-primary: #00563f; --uly-font-serif: "Site Serif", serif; }
      @media (prefers-color-scheme: dark) { :root { --uly-primary: #7fd8b8; } }
    CSS
    assert_equal [], Theme.check(css)
  end

  def test_check_fails_on_a_property_the_contract_does_not_have
    errors = Theme.check(':root { --uly-primry: #0b5aa8; }')
    assert_equal ["--uly-primry isn't in the contract (did you mean --uly-primary?)"], errors
  end

  def test_check_fails_on_a_text_and_ground_pair_under_4_5
    errors = Theme.check(':root { --uly-muted: #8a94a3; }')
    assert_includes errors, 'light: --uly-muted on --uly-page is 2.86:1, under 4.5:1'
    assert(errors.all? { |e| e.start_with?('light: --uly-muted') })
  end

  def test_a_light_value_applies_in_dark_unless_the_dark_block_sets_it
    assert_includes Theme.check(':root { --uly-ink: #0d1321; }'),
                    'dark: --uly-ink on --uly-page is 1.04:1, under 4.5:1'
    css = ':root { --uly-ink: #0d1321; } @media (prefers-color-scheme: dark) { :root { --uly-ink: #e8edf5; } }'
    assert_equal [], Theme.check(css)
  end

  def test_check_fails_on_rules_that_are_not_a_theme
    errors = Theme.check('#header { color: red; } :root { color: red; }')
    assert_equal 2, errors.size
    assert_match(/#header \{ … \} isn't part of a theme/, errors[0])
    assert_match(/color: red isn't a custom property/, errors[1])
  end

  def test_check_fails_on_a_colour_it_cannot_read
    assert_includes Theme.check(':root { --uly-ink: oklch(20% 0.02 260); }'),
                    'light: can\'t read --uly-ink as a colour ("oklch(20% 0.02 260)")'
  end

  def test_a_root_after_the_dark_block_wins_in_dark
    css = '@media (prefers-color-scheme: dark) { :root { --uly-ink: #e8edf5; } } :root { --uly-ink: #0d1321; }'
    assert_includes Theme.check(css), 'dark: --uly-ink on --uly-page is 1.04:1, under 4.5:1'
  end

  def test_reduced_motion_may_set_only_motion
    css = <<~CSS
      :root { --uly-muted: #aaaaaa; }
      @media (prefers-color-scheme: dark) { :root { --uly-muted: #b0bbcc; } }
      @media (prefers-reduced-motion: reduce) { :root { --uly-muted: #3d4859; --uly-duration: 0ms; } }
    CSS
    errors = Theme.check(css)
    assert_includes errors, "--uly-muted can't be set under prefers-reduced-motion, which sets only " \
                            '--uly-duration, --uly-duration-slow, --uly-easing'
    assert_includes errors, 'light: --uly-muted on --uly-page is 2.16:1, under 4.5:1'
  end

  def test_check_reads_every_colour_role_not_only_the_paired_ones
    assert_includes Theme.check(':root { --uly-focus: not-a-colour; }'),
                    'light: can\'t read --uly-focus as a colour ("not-a-colour")'
    assert_includes Theme.check(':root { --uly-rule: var(--uly-rule); }'),
                    'light: can\'t read --uly-rule as a colour ("var(--uly-rule)")'
  end

  def test_rgb_channels_are_clamped_as_the_browser_clamps_them
    assert_includes Theme.check(':root { --uly-primary-fill: rgb(999, 999, 999); }'),
                    'light: --uly-on-primary on --uly-primary-fill is 1.00:1, under 4.5:1'
  end

  def test_check_fails_on_statements_and_braces_outside_a_block
    assert_equal ['@import url("other.css") isn\'t part of a theme: set the contract\'s properties in :root'],
                 Theme.check('@import url("other.css");')
    assert_equal [':root { … } has no closing }'], Theme.check(':root { --uly-ink: #fff;')
    assert_equal ['a } closes no block'], Theme.check(':root { } }')
  end

  def test_check_follows_var_references
    assert_equal [], Theme.check(':root { --uly-info-ink: var(--uly-primary); }')
  end

  def test_header_text_needs_5_6
    assert_includes Theme::PAIRS, ['--uly-on-header', '--uly-header-from', 5.6]
    assert_includes Theme::PAIRS, ['--uly-on-header', '--uly-header-to', 5.6]
    assert_includes Theme.check(':root { --uly-header-to: #1d6fc4; }'),
                    'light: --uly-on-header on --uly-header-to is 5.09:1, under 5.6:1'
  end

  def test_reference_sets_every_property_and_every_colour_for_dark
    sheet = Theme.parse(reference)
    assert_equal [], Theme::CONTRACT - sheet.set(:all).keys
    assert_equal [], Theme::COLORS - sheet.set(:dark).keys
    assert_equal [], sheet.set(:all).keys - Theme::CONTRACT
  end

  # Every text and ground pair at 4.5:1 or better and header text at 5.6:1, in light and dark (L7).
  def test_reference_contrast_in_light_and_dark
    sheet = Theme.parse(reference)
    { light: sheet.values(:light), dark: sheet.values(:dark) }.each do |mode, values|
      Theme::PAIRS.each do |text, ground, need|
        ratio = Theme.contrast(Theme.color(values, text), Theme.color(values, ground))
        assert_operator ratio, :>=, need, "#{mode}: #{text} on #{ground}"
      end
    end
  end

  def test_base_css_sets_no_colour_of_its_own
    css = Theme.strip_comments(File.read(File.join(STYLESHEETS, 'base.css')))
    assert_no_match(/#\h{3,8}\b|\b(?:rgba?|hsla?|oklch|lab|lch|color-mix)\(/, css)
    assert_no_match(/:\s*(?:white|black|red|green|blue|gray|grey)\b/i, css)
  end

  def test_fonts_the_reference_declares_are_in_the_repo_with_their_licence
    urls = reference.scan(/url\("([^"]+)"\)/).flatten
    assert_operator urls.size, :>=, 3
    urls.each { |url| assert File.file?(File.join(STYLESHEETS, url)), "#{url} is missing" }
    assert_match(/SIL Open Font License/, File.read(File.join(PLUGIN, 'licenses/ibm-plex.txt')))
  end

  def test_the_readme_example_theme_passes_the_check
    example = File.read(File.join(PLUGIN, 'README.md'))[/```css\n(.*?)```/m, 1]
    assert example, 'the README has no css example'
    assert_equal [], Theme.check(example)
  end

  def test_rake_task_passes_on_the_reference_and_fails_on_a_bad_file
    output, status = rake_check(Theme::REFERENCE)
    assert status.success?, output
    assert_match(/passes the Ulysses theme check/, output)

    Tempfile.create(['theme', '.css']) do |file|
      file.write(':root { --uly-faint: #c0c0c0; --uly-nope: 1px; }')
      file.flush
      output, status = rake_check(file.path)
      assert_not status.success?
      assert_match(/--uly-nope isn't in the contract/, output)
      assert_match(/--uly-faint on --uly-surface is/, output)
    end
  end

  private

  def rake_check(file)
    Open3.capture2e('bin/rake', "redmine_ulysses:theme:check[#{file}]", chdir: Rails.root.to_s)
  end
end
