# frozen_string_literal: true

module RedmineUlysses
  # The theme contract, and the check a theme file passes against it (design 0004, §3.8). A theme
  # sets the contract's --uly-* properties in :root, its dark colours in
  # @media (prefers-color-scheme: dark) { :root { … } }, its motion under
  # @media (prefers-reduced-motion: reduce) { :root { … } }, and may declare @font-face rules.
  # Anything else in the file fails the check.
  module Theme
    # Colour roles, each given for light and for dark.
    COLORS = %w[
      ink muted faint
      page surface sunk rule
      primary primary-fill on-primary accent focus
      ok-ink ok-soft warn-ink warn-soft danger-ink danger-soft info-ink info-soft
      header-from header-to on-header
    ].map { |name| "--uly-#{name}" }.freeze

    OTHERS = %w[
      font-sans font-mono font-serif
      text-xs text-sm text-base text-lg text-xl text-2xl leading leading-tight
      space-1 space-2 space-3 space-4 space-5 space-6
      radius-sm radius radius-pill
      shadow shadow-raised
      duration duration-slow easing
    ].map { |name| "--uly-#{name}" }.freeze

    CONTRACT = (COLORS + OTHERS).freeze

    TEXT = 4.5
    HEADER = 5.6

    # Each text colour and the grounds it's read on, with the ratio it needs.
    PAIRS = [
      *%w[ink muted faint primary].product(%w[page surface sunk]).map { |t, g| [t, g, TEXT] },
      *%w[ok warn danger info].flat_map do |r|
        ["#{r}-soft", 'surface', 'page'].map { |g| ["#{r}-ink", g, TEXT] }
      end,
      ['on-primary', 'primary-fill', TEXT],
      ['on-header', 'header-from', HEADER],
      ['on-header', 'header-to', HEADER]
    ].map { |t, g, need| ["--uly-#{t}", "--uly-#{g}", need] }.freeze

    REFERENCE = File.expand_path('../../assets/stylesheets/tokens.css', __dir__)

    DARK = /\A@media\s*\(\s*prefers-color-scheme\s*:\s*dark\s*\)\z/
    REDUCED_MOTION = /\A@media\s*\(\s*prefers-reduced-motion\s*:\s*reduce\s*\)\z/
    # What the reduced-motion block may set.
    MOTION = %w[--uly-duration --uly-duration-slow --uly-easing].freeze

    # The declarations a theme file sets, in source order, each with the media it applies under:
    # :all, :dark or :reduced_motion.
    Sheet = Struct.new(:decls, :errors) do
      # The properties set under one media, later declarations winning.
      def set(media)
        decls.each_with_object({}) { |(m, name, value), out| out[name] = value if m == media }
      end

      # The values in effect for :light or :dark, in source order as the browser applies them, so
      # a :root after the dark block wins in dark too.
      def values(mode)
        applies = mode == :dark ? %i[all dark] : %i[all]
        decls.each_with_object({}) { |(m, name, value), out| out[name] = value if applies.include?(m) }
      end
    end

    module_function

    def parse(css)
      sheet = Sheet.new([], [])
      blocks(strip_comments(css), sheet.errors).each do |selector, body|
        case selector
        when ':root' then declare(sheet, :all, body)
        when '@font-face' then nil
        when DARK, REDUCED_MOTION
          inner = blocks(body, sheet.errors)
          if inner.empty? || inner.any? { |s, _| s != ':root' }
            sheet.errors << "#{selector} may hold only :root { … }"
          else
            media = selector.match?(DARK) ? :dark : :reduced_motion
            inner.each { |_, b| declare(sheet, media, b) }
          end
        else
          sheet.errors << "#{selector} { … } isn't part of a theme: set the contract's properties in :root"
        end
      end
      sheet
    end

    # Problems with a theme file, as messages; none means it passes. The file loads after the
    # reference, so each mode's values are the reference's with the file's on top.
    def check(css, reference: File.read(REFERENCE))
      sheet = parse(css)
      ref = parse(reference)
      errors = sheet.errors + unknown(sheet)
      %i[light dark].each do |mode|
        errors.concat(colour_errors(mode, ref.values(mode).merge(sheet.values(mode))))
      end
      errors.uniq
    end

    def unknown(sheet)
      sheet.decls.map { |_, name, _| name }.uniq.reject { |name| CONTRACT.include?(name) }.map do |name|
        hint = DidYouMean::SpellChecker.new(dictionary: CONTRACT).correct(name).first
        "#{name} isn't in the contract#{" (did you mean #{hint}?)" if hint}"
      end
    end

    # Every colour role must read as a colour, and every pair must meet its ratio.
    def colour_errors(mode, values)
      unreadable = COLORS.reject { |name| color(values, name) }
      errors = unreadable.map { |name| "#{mode}: can't read #{name} as a colour (#{values[name].inspect})" }
      PAIRS.each do |text, ground, need|
        next if unreadable.include?(text) || unreadable.include?(ground)

        ratio = contrast(color(values, text), color(values, ground))
        errors << format('%s: %s on %s is %.2f:1, under %.1f:1', mode, text, ground, ratio, need) if ratio < need
      end
      errors
    end

    # A colour value as [r, g, b] in 0..255: #rgb, #rrggbb, rgb() with an opaque alpha if any,
    # its channels clamped as the browser clamps them, or var() of another property. nil for
    # anything else, a var() cycle included.
    def color(values, name, depth = 0)
      value = values[name].to_s.strip
      return if value.empty? || depth > 8

      case value
      when /\Avar\(\s*(--[\w-]+)\s*\)\z/ then color(values, Regexp.last_match(1), depth + 1)
      when /\A#(\h)(\h)(\h)\z/ then Regexp.last_match.captures.map { |c| (c * 2).hex }
      when /\A#(\h\h)(\h\h)(\h\h)\z/ then Regexp.last_match.captures.map(&:hex)
      when %r{\Argba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)\s*(?:[,/]\s*(1|1\.0+|100%)\s*)?\)\z}
        Regexp.last_match.captures.first(3).map { |c| [c.to_i, 255].min }
      end
    end

    # WCAG 2 contrast ratio.
    def contrast(a, b)
      la, lb = [luminance(a), luminance(b)].sort.reverse
      (la + 0.05) / (lb + 0.05)
    end

    def luminance(rgb)
      r, g, b = rgb.map do |c|
        c /= 255.0
        c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end
      (0.2126 * r) + (0.7152 * g) + (0.0722 * b)
    end

    def strip_comments(css)
      css.gsub(%r{/\*.*?\*/}m, '')
    end

    # Top-level `selector { body }` pairs, bodies unparsed. A statement outside a block, an
    # unclosed block or a stray } goes to errors.
    def blocks(css, errors = [])
      out = []
      depth = 0
      start = 0
      selector = nil
      css.each_char.with_index do |ch, i|
        if ch == '{'
          if depth.zero?
            *statements, selector = css[start...i].split(';', -1)
            stray(statements, errors)
            selector = selector.strip
            start = i + 1
          end
          depth += 1
        elsif ch == '}'
          if depth.zero?
            errors << 'a } closes no block'
            start = i + 1
            next
          end
          depth -= 1
          if depth.zero?
            out << [selector, css[start...i]]
            start = i + 1
          end
        end
      end
      if depth.positive?
        errors << "#{selector} { … } has no closing }"
      else
        stray(css[start..].split(';'), errors)
      end
      out
    end

    def stray(statements, errors)
      statements.map(&:strip).reject(&:empty?).each do |statement|
        errors << "#{statement} isn't part of a theme: set the contract's properties in :root"
      end
    end

    def declare(sheet, media, body)
      body.split(';').each do |decl|
        next if decl.strip.empty?

        name, value = decl.split(':', 2).map(&:strip)
        if value.nil? || !name.start_with?('--')
          sheet.errors << "#{decl.strip} isn't a custom property: a theme sets only --uly-* properties"
        elsif media == :reduced_motion && CONTRACT.include?(name) && !MOTION.include?(name)
          sheet.errors << "#{name} can't be set under prefers-reduced-motion, which sets only #{MOTION.join(', ')}"
        else
          sheet.decls << [media, name, value]
        end
      end
    end
  end
end
