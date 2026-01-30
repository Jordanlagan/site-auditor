module Audits
  class AccessibilityService < BaseService
    def category
      'accessibility'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_color_contrast(client)
      check_heading_structure(client)
      check_link_text(client)
      check_skip_links(client)
      check_aria_labels(client)
      check_keyboard_navigation(client)
      
      {
        score: calculate_score,
        raw_data: {
          has_skip_link: has_skip_link?(client),
          heading_hierarchy_valid: check_heading_hierarchy(client),
          images_without_alt: count_images_without_alt(client)
        }
      }
    end

    private

    def check_color_contrast(client)
      return unless client.document
      
      # Check for common low-contrast patterns
      html = client.html.downcase
      
      # Light gray text on white
      if html.match?(/#ccc|#ddd|#eee/i) || html.include?('color: lightgray') || html.include?('color: silver')
        add_issue(
          severity: 'medium',
          title: 'Potential Color Contrast Issues',
          description: 'Light gray text on white backgrounds fails WCAG AA standards. 8% of men have color vision deficiency.',
          recommendation: 'Ensure text has minimum 4.5:1 contrast ratio (AA) or 7:1 (AAA). Test with WebAIM Contrast Checker. Use #767676 or darker for body text on white backgrounds.'
        )
      end
    end

    def check_heading_structure(client)
      return unless client.document
      
      headings = client.document.css('h1, h2, h3, h4, h5, h6')
      
      # Check for proper hierarchy
      heading_levels = headings.map { |h| h.name[1].to_i }
      
      # Check for skipped levels (e.g., h1 then h3)
      skipped = false
      heading_levels.each_cons(2) do |current, next_level|
        if next_level > current + 1
          skipped = true
          break
        end
      end
      
      if skipped
        add_issue(
          severity: 'medium',
          title: 'Heading Hierarchy Skips Levels',
          description: 'Skipping heading levels (H1 to H3) confuses screen readers and affects SEO.',
          recommendation: 'Maintain proper heading hierarchy: H1 → H2 → H3. Never skip levels. Use CSS to style headings, not heading tags for styling.'
        )
      end
      
      # Check for empty headings
      empty_headings = headings.select { |h| h.text.strip.empty? }
      
      if empty_headings.any?
        add_issue(
          severity: 'high',
          title: 'Empty Heading Tags Found',
          description: "Found #{empty_headings.count} heading tags with no text. Screen readers announce these as empty.",
          recommendation: 'Remove empty heading tags or add descriptive text. Never use headings for spacing - use CSS margins instead.'
        )
      end
    end

    def check_link_text(client)
      return unless client.document
      
      links = client.document.css('a')
      
      # Check for non-descriptive link text
      bad_links = links.select do |link|
        text = link.text.strip.downcase
        ['click here', 'read more', 'here', 'more', 'link', 'this'].include?(text)
      end
      
      if bad_links.count > 2
        add_issue(
          severity: 'medium',
          title: 'Links with Non-Descriptive Text',
          description: "Found #{bad_links.count} links with generic text like 'Click Here'. Screen reader users navigate by links list.",
          recommendation: 'Use descriptive link text that makes sense out of context. Bad: "Click here for pricing". Good: "View our pricing plans". Benefits SEO too.'
        )
      end
      
      # Check for links without text or aria-label
      empty_links = links.select do |link|
        link.text.strip.empty? && !link['aria-label'] && !link['title']
      end
      
      if empty_links.any?
        add_issue(
          severity: 'high',
          title: 'Links Missing Text or Labels',
          description: "Found #{empty_links.count} links with no text. Inaccessible to screen readers.",
          recommendation: 'Add descriptive text, aria-label, or meaningful title attribute to all links. Icon-only links must have aria-label.'
        )
      end
    end

    def check_skip_links(client)
      return unless client.document
      
      unless has_skip_link?(client)
        add_issue(
          severity: 'low',
          title: 'No "Skip to Main Content" Link',
          description: 'Skip links help keyboard users bypass repetitive navigation.',
          recommendation: 'Add skip link as first focusable element: <a href="#main" class="skip-link">Skip to main content</a>. Can be visually hidden until focused.'
        )
      end
    end

    def check_aria_labels(client)
      return unless client.document
      
      # Check for ARIA landmarks
      has_main = client.document.at_css('main, [role="main"]')
      has_nav = client.document.at_css('nav, [role="navigation"]')
      
      unless has_main
        add_issue(
          severity: 'medium',
          title: 'No <main> Landmark',
          description: 'Main landmark helps screen readers jump to primary content.',
          recommendation: 'Wrap primary page content in <main> tag or add role="main" to container. Use once per page.'
        )
      end
      
      unless has_nav
        add_issue(
          severity: 'low',
          title: 'No <nav> Landmark',
          description: 'Navigation landmarks help users find and skip navigation areas.',
          recommendation: 'Wrap navigation in <nav> tag or add role="navigation" to navigation container.'
        )
      end
      
      # Check for form inputs without labels
      inputs = client.document.css('input:not([type="hidden"]), select, textarea')
      inputs_without_labels = inputs.reject do |input|
        input_id = input['id']
        has_label = input_id && client.document.at_css("label[for='#{input_id}']")
        has_label || input['aria-label'] || input['aria-labelledby']
      end
      
      if inputs_without_labels.count > 0
        add_issue(
          severity: 'high',
          title: 'Form Inputs Without Labels',
          description: "#{inputs_without_labels.count} form fields lack proper labels. Fails WCAG 2.1 Level A.",
          recommendation: 'Add <label> tags with for attribute, or use aria-label. Placeholder is not a substitute for label. Labels improve usability for everyone.'
        )
      end
    end

    def check_keyboard_navigation(client)
      return unless client.document
      
      # Check for interactive elements without proper focus
      interactive = client.document.css('div[onclick], span[onclick], a[onclick]')
      
      if interactive.any?
        add_issue(
          severity: 'medium',
          title: 'Non-Focusable Interactive Elements',
          description: "Found #{interactive.count} div/span elements with click handlers. Not keyboard accessible.",
          recommendation: 'Use semantic HTML: <button> for actions, <a> for navigation. If you must use div/span, add tabindex="0" and keyboard event handlers.'
        )
      end
      
      # Check for focus outline removal
      html = client.html.downcase
      if html.include?('outline: none') || html.include?('outline:none')
        add_issue(
          severity: 'high',
          title: 'Focus Outline Disabled',
          description: 'Removing focus outlines makes site impossible to navigate with keyboard. Fails WCAG 2.1.',
          recommendation: 'Never use outline: none without providing alternative focus indicator. Style :focus with visible border/shadow instead. Test by tabbing through site.'
        )
      end
    end

    # Helper methods
    def has_skip_link?(client)
      return false unless client.document
      
      # Look for skip link (usually first link in body)
      first_links = client.document.css('body a')[0..2]
      first_links.any? do |link|
        href = link['href'].to_s
        text = link.text.downcase
        href.start_with?('#') && (text.include?('skip') || text.include?('main'))
      end
    end

    def check_heading_hierarchy(client)
      return true unless client.document
      
      headings = client.document.css('h1, h2, h3, h4, h5, h6')
      heading_levels = headings.map { |h| h.name[1].to_i }
      
      # Check if hierarchy is valid
      heading_levels.each_cons(2).all? { |current, next_level| next_level <= current + 1 }
    end

    def count_images_without_alt(client)
      return 0 unless client.document
      client.document.css('img').reject { |img| img['alt'] }.count
    end
  end
end
