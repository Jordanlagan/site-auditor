# frozen_string_literal: true

module Audits
  class CroUxService < BaseService
    # CRO/UX Heuristics - Programmatic, verifiable checks only

    def category
      "cro_ux"
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      @doc = client.document
      return unless @doc

      @results = {
        color_palette: analyze_color_palette,
        contrast_ratios: analyze_contrast_ratios,
        cta_analysis: analyze_ctas,
        typography: analyze_typography,
        layout_modernity: analyze_layout_patterns,
        dom_density: analyze_dom_density,
        trust_signals: analyze_trust_signals
      }

      calculate_score
      generate_issues

      {
        score: @score,
        raw_data: @results
      }
    end

    private

    def analyze_color_palette
      colors = extract_colors_from_css

      {
        unique_colors: colors.size,
        palette: colors.take(20),
        excessive: colors.size > 15
      }
    end

    def extract_colors_from_css
      colors = Set.new

      # Extract from inline styles
      @doc.css("[style]").each do |el|
        style = el["style"].to_s
        colors.merge(extract_hex_colors(style))
        colors.merge(extract_rgb_colors(style))
      end

      # Extract from style tags
      @doc.css("style").each do |style_tag|
        css = style_tag.content
        colors.merge(extract_hex_colors(css))
        colors.merge(extract_rgb_colors(css))
      end

      colors.to_a
    end

    def extract_hex_colors(text)
      text.scan(/#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b/).map do |match|
        normalize_hex(match[0])
      end
    end

    def extract_rgb_colors(text)
      text.scan(/rgba?\((\d+),\s*(\d+),\s*(\d+)/).map do |r, g, b|
        rgb_to_hex(r.to_i, g.to_i, b.to_i)
      end
    end

    def normalize_hex(hex)
      hex = hex.upcase
      hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
      "##{hex}"
    end

    def rgb_to_hex(r, g, b)
      "#%02X%02X%02X" % [ r, g, b ]
    end

    def analyze_contrast_ratios
      issues = []

      # Check buttons
      @doc.css('button, input[type="submit"], input[type="button"], a.btn, a.button, [role="button"]').each_with_index do |btn, idx|
        break if idx >= 20 # Limit checks

        contrast = calculate_element_contrast(btn)
        if contrast && contrast[:ratio] < 4.5
          issues << {
            element: btn.name,
            text: btn.text.strip[0..50],
            ratio: contrast[:ratio].round(2),
            fg: contrast[:fg],
            bg: contrast[:bg]
          }
        end
      end

      # Check headings and important text
      @doc.css("h1, h2, h3, h4, p").first(30).each do |el|
        next if el.text.strip.empty?

        contrast = calculate_element_contrast(el)
        if contrast && contrast[:ratio] < 4.5
          issues << {
            element: el.name,
            text: el.text.strip[0..50],
            ratio: contrast[:ratio].round(2),
            fg: contrast[:fg],
            bg: contrast[:bg]
          }
        end
      end

      { low_contrast_elements: issues, count: issues.size }
    end

    def calculate_element_contrast(element)
      # Extract computed colors from style attribute
      style = element["style"].to_s

      fg_color = extract_color_from_style(style, "color")
      bg_color = extract_color_from_style(style, "background-color") ||
                 extract_color_from_style(style, "background")

      return nil unless fg_color || bg_color

      fg = parse_color(fg_color || "#000000")
      bg = parse_color(bg_color || "#FFFFFF")

      ratio = calculate_contrast_ratio(fg, bg)

      { fg: fg_color || "#000000", bg: bg_color || "#FFFFFF", ratio: ratio }
    end

    def extract_color_from_style(style, property)
      # Match color values
      match = style.match(/#{property}\s*:\s*([^;]+);?/)
      return nil unless match

      value = match[1].strip

      # Return hex or rgb
      if value.match?(/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6})$/)
        value
      elsif value.match?(/^rgba?\(/)
        value
      end
    end

    def parse_color(color_string)
      if color_string.start_with?("#")
        hex = color_string[1..]
        hex = hex.chars.map { |c| c * 2 }.join if hex.length == 3
        {
          r: hex[0..1].to_i(16),
          g: hex[2..3].to_i(16),
          b: hex[4..5].to_i(16)
        }
      elsif color_string.start_with?("rgb")
        match = color_string.match(/(\d+),\s*(\d+),\s*(\d+)/)
        return { r: 0, g: 0, b: 0 } unless match

        { r: match[1].to_i, g: match[2].to_i, b: match[3].to_i }
      else
        { r: 0, g: 0, b: 0 }
      end
    end

    def calculate_contrast_ratio(fg, bg)
      l1 = relative_luminance(fg)
      l2 = relative_luminance(bg)

      lighter = [ l1, l2 ].max
      darker = [ l1, l2 ].min

      (lighter + 0.05) / (darker + 0.05)
    end

    def relative_luminance(color)
      r = linearize(color[:r] / 255.0)
      g = linearize(color[:g] / 255.0)
      b = linearize(color[:b] / 255.0)

      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    def linearize(val)
      val <= 0.03928 ? val / 12.92 : ((val + 0.055) / 1.055)**2.4
    end

    def analyze_ctas
      buttons = find_potential_ctas
      above_fold = buttons.select { |b| b[:above_fold] }

      {
        total_buttons: buttons.size,
        above_fold_count: above_fold.size,
        competing_ctas: above_fold.size > 3,
        buttons: buttons.first(10),
        has_prominent_cta: above_fold.any? { |b| b[:large] && b[:has_action_text] }
      }
    end

    def find_potential_ctas
      buttons = []

      selectors = 'button, input[type="submit"], input[type="button"], a.btn, a.button, [role="button"]'

      @doc.css(selectors).each_with_index do |btn, idx|
        break if idx >= 30

        text = btn.text.strip
        next if text.empty? && btn["value"].to_s.empty?

        display_text = text.empty? ? btn["value"].to_s : text

        # Check dimensions from inline styles
        style = btn["style"].to_s
        width = extract_dimension(style, "width")
        height = extract_dimension(style, "height")
        font_size = extract_dimension(style, "font-size")

        # Heuristic: likely above fold if within first 1500px of content
        position_score = calculate_element_position(btn)

        buttons << {
          text: display_text[0..50],
          type: btn.name,
          width: width,
          height: height,
          font_size: font_size,
          large: (width && width > 120) || (height && height > 40) || (font_size && font_size > 16),
          above_fold: position_score < 1500,
          has_action_text: action_oriented?(display_text),
          has_color: style.include?("background"),
          position_score: position_score
        }
      end

      buttons.sort_by { |b| b[:position_score] }
    end

    def extract_dimension(style, property)
      match = style.match(/#{property}\s*:\s*(\d+)(px|rem|em)?/)
      return nil unless match

      value = match[1].to_f
      unit = match[2]

      # Convert to px approximation
      case unit
      when "rem", "em"
        value * 16
      else
        value
      end
    end

    def calculate_element_position(element)
      # Approximate position by counting preceding elements
      position = 0
      current = element

      while current.previous_element
        current = current.previous_element
        position += 100 # Rough estimate: 100px per preceding element
        break if position > 2000
      end

      position
    end

    def action_oriented?(text)
      action_words = %w[
        get start buy shop download subscribe join sign free trial demo
        learn more contact call click request order add register
      ]

      text_lower = text.downcase
      action_words.any? { |word| text_lower.include?(word) }
    end

    def analyze_typography
      fonts = extract_fonts
      body_elements = @doc.css("p, div, span, li").first(50)

      small_text = []
      low_line_height = []

      body_elements.each do |el|
        style = el["style"].to_s

        font_size = extract_dimension(style, "font-size")
        if font_size && font_size < 16
          small_text << { element: el.name, size: font_size.round(1), text: el.text.strip[0..40] }
        end

        line_height = extract_line_height(style, font_size || 16)
        if line_height && line_height < 1.4
          low_line_height << { element: el.name, line_height: line_height.round(2), text: el.text.strip[0..40] }
        end
      end

      {
        fonts: fonts,
        using_system_fonts: system_fonts_only?(fonts),
        small_text_count: small_text.size,
        small_text_elements: small_text.first(5),
        low_line_height_count: low_line_height.size,
        low_line_height_elements: low_line_height.first(5),
        heading_hierarchy: analyze_heading_hierarchy
      }
    end

    def extract_fonts
      fonts = Set.new

      @doc.css("[style]").each do |el|
        style = el["style"].to_s
        match = style.match(/font-family\s*:\s*([^;]+)/)
        next unless match

        font_family = match[1].strip.gsub(/["']/, "")
        fonts.add(font_family.split(",").first.strip)
      end

      @doc.css("style").each do |style_tag|
        css = style_tag.content
        css.scan(/font-family\s*:\s*([^;}]+)/).each do |match|
          font_family = match[0].strip.gsub(/["']/, "")
          fonts.add(font_family.split(",").first.strip)
        end
      end

      fonts.to_a
    end

    def system_fonts_only?(fonts)
      system_fonts = [
        "Arial", "Helvetica", "Times New Roman", "Times", "Courier New",
        "Courier", "Verdana", "Georgia", "Palatino", "Garamond",
        "Comic Sans MS", "Trebuchet MS", "Impact", "sans-serif", "serif"
      ]

      return true if fonts.empty?

      fonts.all? { |font| system_fonts.any? { |sf| font.downcase.include?(sf.downcase) } }
    end

    def extract_line_height(style, font_size)
      match = style.match(/line-height\s*:\s*([\d.]+)(px|rem|em)?/)
      return nil unless match

      value = match[1].to_f
      unit = match[2]

      case unit
      when "px"
        value / font_size
      when "rem", "em"
        value
      when nil
        value # Already a ratio
      end
    end

    def analyze_heading_hierarchy
      headings = @doc.css("h1, h2, h3, h4, h5, h6").map(&:name)

      issues = []
      previous_level = 0

      headings.each do |h|
        level = h[1].to_i

        if level - previous_level > 1
          issues << "Skipped from H#{previous_level} to H#{level}"
        end

        previous_level = level
      end

      {
        h1_count: headings.count { |h| h == "h1" },
        hierarchy_issues: issues,
        proper_hierarchy: issues.empty?
      }
    end

    def analyze_layout_patterns
      {
        uses_tables_for_layout: layout_table_usage,
        inline_styles_count: inline_style_count,
        has_viewport_meta: viewport_meta_present?,
        uses_modern_layout: modern_layout_detected?
      }
    end

    def layout_table_usage
      tables = @doc.css("table")

      # Tables without semantic attributes likely used for layout
      layout_tables = tables.select do |table|
        !table["role"] &&
        !table.css("th").any? &&
        table.css("td").size > 10
      end

      layout_tables.size
    end

    def inline_style_count
      @doc.css("[style]").size
    end

    def viewport_meta_present?
      @doc.css('meta[name="viewport"]').any?
    end

    def modern_layout_detected?
      # Check for modern CSS in style tags
      @doc.css("style").any? do |style|
        css = style.content
        css.include?("flexbox") ||
        css.include?("display: flex") ||
        css.include?("display: grid") ||
        css.include?("grid-template")
      end
    end

    def analyze_dom_density
      above_fold = @doc.css("body").first&.element_children&.first(10) || []

      total_elements = 0
      max_depth = 0

      above_fold.each do |section|
        depth = calculate_depth(section)
        count = section.css("*").size

        total_elements += count
        max_depth = [ max_depth, depth ].max
      end

      {
        elements_above_fold: total_elements,
        max_nesting_depth: max_depth,
        excessive_density: total_elements > 500,
        excessive_nesting: max_depth > 15
      }
    end

    def calculate_depth(element, current_depth = 0)
      return current_depth if element.element_children.empty?

      depths = element.element_children.map { |child| calculate_depth(child, current_depth + 1) }
      depths.max || current_depth
    end

    def analyze_trust_signals
      trust_elements = {
        phone_visible: find_phone_numbers.any?,
        email_visible: find_email_addresses.any?,
        ssl_badge: has_ssl_badge?,
        payment_badges: has_payment_badges?,
        review_elements: has_review_elements?,
        trust_seals: has_trust_seals?
      }

      trust_elements[:trust_signal_count] = trust_elements.values.count(true)
      trust_elements
    end

    def has_ssl_badge?
      @doc.css("img").any? do |img|
        alt = img["alt"].to_s.downcase
        src = img["src"].to_s.downcase
        alt.include?("secure") || alt.include?("ssl") || src.include?("ssl")
      end
    end

    def has_payment_badges?
      @doc.css("img").any? do |img|
        alt = img["alt"].to_s.downcase
        alt.include?("visa") || alt.include?("mastercard") || alt.include?("paypal")
      end
    end

    def has_review_elements?
      @doc.css("[class], [id]").any? do |el|
        classes = el["class"].to_s.downcase
        id = el["id"].to_s.downcase
        classes.include?("review") || classes.include?("testimonial") ||
        id.include?("review") || id.include?("testimonial")
      end
    end

    def has_trust_seals?
      @doc.css("img").any? do |img|
        alt = img["alt"].to_s.downcase
        alt.include?("trust") || alt.include?("verified") || alt.include?("certified")
      end
    end

    def find_phone_numbers
      body_text = @doc.css("body").text
      body_text.scan(/\b\d{3}[-.]?\d{3}[-.]?\d{4}\b|\(\d{3}\)\s*\d{3}[-.]?\d{4}/)
    end

    def find_email_addresses
      body_text = @doc.css("body").text
      body_text.scan(/\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Z|a-z]{2,}\b/)
    end

    def calculate_score
      score = 100

      # Deductions
      score -= 15 if @results[:color_palette][:excessive]
      score -= 10 * [ @results[:contrast_ratios][:count], 3 ].min
      score -= 20 unless @results[:cta_analysis][:has_prominent_cta]
      score -= 10 if @results[:cta_analysis][:competing_ctas]
      score -= 15 if @results[:typography][:using_system_fonts]
      score -= 10 if @results[:typography][:small_text_count] > 5
      score -= 10 if @results[:typography][:low_line_height_count] > 5
      score -= 15 unless @results[:typography][:heading_hierarchy][:proper_hierarchy]
      score -= 20 if @results[:layout_modernity][:uses_tables_for_layout] > 0
      score -= 10 if @results[:layout_modernity][:inline_styles_count] > 50
      score -= 15 unless @results[:layout_modernity][:uses_modern_layout]
      score -= 10 if @results[:dom_density][:excessive_density]
      score -= 10 if @results[:dom_density][:excessive_nesting]
      score -= 15 if @results[:trust_signals][:trust_signal_count] < 2

      @score = [ score, 0 ].max
    end

    def generate_issues
      # Only flag top priority issues

      # Critical issues
      unless @results[:cta_analysis][:has_prominent_cta]
        add_issue(
          severity: "high",
          title: "No Prominent Call-to-Action",
          description: "No large, visually distinct CTA button found above the fold.",
          recommendation: "Add a prominent CTA button (min 120px wide, 40px tall) with action-oriented text in the hero section."
        )
      end

      # High priority
      if @results[:color_palette][:excessive]
        add_issue(
          severity: "high",
          title: "Excessive Color Palette",
          description: "Using #{@results[:color_palette][:unique_colors]} unique colors. Excessive colors create visual noise.",
          recommendation: "Limit to 5-8 brand colors. Use a consistent palette: 1 primary, 1-2 secondary, neutrals."
        )
      end

      if @results[:contrast_ratios][:count] > 0
        examples = @results[:contrast_ratios][:low_contrast_elements].first(3)
        add_issue(
          severity: "high",
          title: "Low Contrast Text",
          description: "Found #{@results[:contrast_ratios][:count]} elements with contrast ratios below 4.5:1 (WCAG minimum). Examples: #{examples.map { |e| "#{e[:element]} (#{e[:ratio]}:1)" }.join(', ')}",
          recommendation: "Increase contrast to at least 4.5:1. Use darker text colors or lighter backgrounds."
        )
      end

      if @results[:layout_modernity][:uses_tables_for_layout] > 0
        add_issue(
          severity: "high",
          title: "Outdated Table Layouts",
          description: "Found #{@results[:layout_modernity][:uses_tables_for_layout]} tables being used for layout instead of data.",
          recommendation: "Replace table layouts with modern CSS (Flexbox or Grid). Tables should only contain tabular data."
        )
      end

      # Medium priority
      if @results[:cta_analysis][:competing_ctas]
        add_issue(
          severity: "medium",
          title: "Too Many Competing CTAs",
          description: "#{@results[:cta_analysis][:above_fold_count]} buttons/CTAs found above the fold. Multiple CTAs reduce conversion.",
          recommendation: "Prioritize 1 primary CTA. Secondary actions should be less prominent (text links or ghost buttons)."
        )
      end

      if @results[:typography][:using_system_fonts]
        add_issue(
          severity: "medium",
          title: "Using Only System Fonts",
          description: "No custom fonts detected. System fonts can make sites look generic.",
          recommendation: "Use web fonts (Google Fonts, Adobe Fonts) to establish brand personality and improve aesthetics."
        )
      end

      if @results[:typography][:small_text_count] > 5
        examples = @results[:typography][:small_text_elements].first(3)
        add_issue(
          severity: "medium",
          title: "Text Too Small",
          description: "Found #{@results[:typography][:small_text_count]} elements with font-size < 16px. Examples: #{examples.map { |e| "#{e[:size]}px" }.join(', ')}",
          recommendation: "Use minimum 16px for body text. Small text hurts readability, especially on mobile."
        )
      end

      if @results[:typography][:low_line_height_count] > 5
        add_issue(
          severity: "medium",
          title: "Insufficient Line Height",
          description: "Found #{@results[:typography][:low_line_height_count]} elements with line-height < 1.4. Cramped text is hard to read.",
          recommendation: "Use line-height of 1.5-1.7 for body text. Improves readability and scannability."
        )
      end

      unless @results[:typography][:heading_hierarchy][:proper_hierarchy]
        issues = @results[:typography][:heading_hierarchy][:hierarchy_issues].first(2).join(", ")
        add_issue(
          severity: "medium",
          title: "Broken Heading Hierarchy",
          description: "Heading levels skip: #{issues}. Confuses screen readers and hurts SEO.",
          recommendation: "Use proper heading order: H1 → H2 → H3. Never skip levels. Only one H1 per page."
        )
      end

      if @results[:layout_modernity][:inline_styles_count] > 50
        add_issue(
          severity: "medium",
          title: "Excessive Inline Styles",
          description: "#{@results[:layout_modernity][:inline_styles_count]} elements with inline styles. Indicates outdated development practices.",
          recommendation: "Move styles to CSS files. Inline styles are harder to maintain and override."
        )
      end

      unless @results[:layout_modernity][:uses_modern_layout]
        add_issue(
          severity: "medium",
          title: "No Modern CSS Layout Detected",
          description: "No Flexbox or Grid detected. May indicate outdated layout techniques.",
          recommendation: "Modernize with CSS Flexbox/Grid for better responsive design and maintainability."
        )
      end

      if @results[:dom_density][:excessive_density]
        add_issue(
          severity: "medium",
          title: "Excessive DOM Density",
          description: "#{@results[:dom_density][:elements_above_fold]} elements above the fold. Complex DOMs hurt performance.",
          recommendation: "Simplify markup. Remove unnecessary wrapper divs. Consider lazy-loading below-fold content."
        )
      end

      if @results[:trust_signals][:trust_signal_count] < 2
        missing = @results[:trust_signals].select { |k, v| !v && k != :trust_signal_count }.keys
        add_issue(
          severity: "medium",
          title: "Limited Trust Signals",
          description: "Only #{@results[:trust_signals][:trust_signal_count]} trust signals detected. Missing: #{missing.first(3).join(', ')}",
          recommendation: "Add phone number, payment badges, SSL badge, or review elements to increase credibility."
        )
      end

      # Low priority - only add if we're under 10 issues
      if @issues.size < 10
        unless @results[:layout_modernity][:has_viewport_meta]
          add_issue(
            severity: "low",
            title: "Missing Viewport Meta Tag",
            description: "No viewport meta tag found. Required for mobile responsiveness.",
            recommendation: 'Add: <meta name="viewport" content="width=device-width, initial-scale=1">'
          )
        end
      end
    end
  end
end
