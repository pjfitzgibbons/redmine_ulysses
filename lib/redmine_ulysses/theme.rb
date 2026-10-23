# frozen_string_literal: true

module RedmineUlysses
  # The theme contract, and the check a theme file passes against it (design 0004, §3.8). A theme
  # sets the contract's --uly-* properties in :root, its dark colours in
  # @media (prefers-color-scheme: dark) { :root { … } }, and may declare @font-face rules. Anything
  # else in the file fails the check.
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

    # The declarations a theme file sets, by where they apply.
    Sheet = Struct.new(:light, :dark, :errors)

    module_function

    def parse(css)
      sheet = Sheet.new({}, {}, [])
      blocks(strip_comments(css)).each do |selector, body|
        case selector
        when ':root' then declare(sheet, sheet.light, body)
        when '@font-face' then nil
        when DARK, REDUCED_MOTION
          inner = blocks(body)
          if inner.empty? || inner.any? { |s, _| s != ':root' }
            sheet.errors << "#{selector} may hold only :root { … }"
          else
            target = selector.match?(DARK) ? sheet.dark : sheet.light
            inner.each { |_, b| declare(sheet, target, b) }
          end
        else
          sheet.errors << "#{selector} { … } isn't part of a theme: set the contract's properties in :root"
        end
      end
      sheet
    end

    # Problems with a theme file, as messages; none means it passes. The reference fills whatever
    # the file leaves out, in the order the browser applies them: a property the file sets in
    # :root applies in light and dark, unless its dark block sets it again.
    def check(css, reference: File.read(REFERENCE))
      sheet = parse(css)
      ref = parse(reference)
      errors = sheet.errors.dup
      (sheet.light.keys | sheet.dark.keys).each do |name|
        next if CONTRACT.include?(name)

        hint = DidYouMean::SpellChecker.new(dictionary: CONTRACT).correct(name).first
        errors << "#{name} isn't in the contract#{" (did you mean #{hint}?)" if hint}"
      end
      light = ref.light.merge(sheet.light)
      dark = ref.light.merge(ref.dark).merge(sheet.light).merge(sheet.dark)
      { 'light' => light, 'dark' => dark }.each do |mode, values|
        PAIRS.each do |text, ground, need|
          fg = color(values, text)
          bg = color(values, ground)
          unless fg && bg
            errors << "#{mode}: can't read #{fg ? ground : text} as a colour (#{values[fg ? ground : text].inspect})"
            next
          end
          ratio = contrast(fg, bg)
          next if ratio >= need

          errors << format('%s: %s on %s is %.2f:1, under %.1f:1', mode, text, ground, ratio, need)
        end
      end
      errors.uniq
    end

    # A colour value as [r, g, b] in 0..255: #rgb, #rrggbb, rgb() with an opaque alpha if any,
    # or var() of another property. nil for anything else.
    def color(values, name, depth = 0)
      value = values[name].to_s.strip
      return if value.empty? || depth > 8

      case value
      when /\Avar\(\s*(--[\w-]+)\s*\)\z/ then color(values, Regexp.last_match(1), depth + 1)
      when /\A#(\h)(\h)(\h)\z/ then Regexp.last_match.captures.map { |c| (c * 2).hex }
      when /\A#(\h\h)(\h\h)(\h\h)\z/ then Regexp.last_match.captures.map(&:hex)
      when %r{\Argba?\(\s*(\d+)[\s,]+(\d+)[\s,]+(\d+)\s*(?:[,/]\s*(1|1\.0+|100%)\s*)?\)\z}
        Regexp.last_match.captures.first(3).map(&:to_i)
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

    # Top-level `selector { body }` pairs, bodies unparsed.
    def blocks(css)
      out = []
      depth = 0
      start = 0
      selector = nil
      css.each_char.with_index do |ch, i|
        if ch == '{'
          if depth.zero?
            selector = css[start...i].strip
            start = i + 1
          end
          depth += 1
        elsif ch == '}'
          depth -= 1
          if depth.zero?
            out << [selector, css[start...i]]
            start = i + 1
          end
        end
      end
      out
    end

    def declare(sheet, target, body)
      body.split(';').each do |decl|
        next if decl.strip.empty?

        name, value = decl.split(':', 2).map(&:strip)
        if value.nil? || !name.start_with?('--')
          sheet.errors << "#{decl.strip} isn't a custom property: a theme sets only --uly-* properties"
        else
          target[name] = value
        end
      end
    end
  end
end
