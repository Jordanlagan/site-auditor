module Audits
  class UxCroService < BaseService
    def category
      'ux_cro'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_viewport_meta(client)
      check_font_sizes(client)
      check_tap_targets(client)
      check_form_labels(client)
      check_mobile_friendly_elements(client)
      
      {
        score: calculate_score,
        raw_data: {
          has_viewport: has_viewport_meta?(client),
          small_fonts_count: count_small_fonts(client),
          forms_count: count_forms(client),
          forms_without_labels: count_forms_without_labels(client)
        }
      }
    end

    private

    def check_viewport_meta(client)
      return unless client.document
      
      viewport = client.document.at_css('meta[name="viewport"]')
      
      if viewport.nil?
        add_issue(
          severity: 'high',
          title: 'Missing Viewport Meta Tag',
          description: 'No viewport meta tag found.',
          recommendation: 'Add <meta name="viewport" content="width=device-width, initial-scale=1"> for mobile responsiveness.'
        )
      else
        content = viewport['content'].to_s
        unless content.include?('width=device-width')
          add_issue(
            severity: 'medium',
            title: 'Incomplete Viewport Configuration',
            description: 'Viewport meta tag does not include width=device-width.',
            recommendation: 'Update viewport to include width=device-width for proper mobile scaling.'
          )
        end
      end
    end

    def check_font_sizes(client)
      return unless client.document
      
      # Check for inline styles with small font sizes
      elements_with_style = client.document.css('[style*="font-size"]')
      small_fonts = elements_with_style.select do |element|
        style = element['style']
        style.match?(/font-size\s*:\s*(\d+)px/) && $1.to_i < 16
      end
      
      if small_fonts.count > 5
        add_issue(
          severity: 'medium',
          title: 'Small Font Sizes Detected',
          description: "Found #{small_fonts.count} elements with font sizes below 16px.",
          recommendation: 'Use minimum 16px font size for body text to improve readability on mobile devices.'
        )
      end
    end

    def check_tap_targets(client)
      return unless client.document
      
      # Check for links and buttons that might be too close together
      links = client.document.css('a, button')
      
      # Simple heuristic: check for many links in navigation areas
      nav_links = client.document.css('nav a, .nav a, .menu a')
      
      if nav_links.count > 10
        add_issue(
          severity: 'low',
          title: 'Potentially Small Tap Targets',
          description: "Navigation contains #{nav_links.count} links that may be too close together.",
          recommendation: 'Ensure tap targets are at least 48x48px with adequate spacing for mobile users.'
        )
      end
    end

    def check_form_labels(client)
      return unless client.document
      
      # Find input fields
      inputs = client.document.css('input[type="text"], input[type="email"], input[type="tel"], input[type="password"], textarea, select')
      
      inputs_without_labels = inputs.reject do |input|
        input_id = input['id']
        input_name = input['name']
        
        # Check for associated label
        has_label = false
        
        if input_id
          has_label = client.document.at_css("label[for='#{input_id}']")
        end
        
        # Check if input is wrapped in label
        has_label ||= input.ancestors.any? { |ancestor| ancestor.name == 'label' }
        
        # Check for placeholder (not ideal but common)
        has_label ||= input['placeholder']
        
        # Check for aria-label
        has_label ||= input['aria-label']
        
        has_label
      end
      
      if inputs.any? && inputs_without_labels.count > 0
        add_issue(
          severity: 'high',
          title: 'Form Inputs Without Labels',
          description: "#{inputs_without_labels.count} of #{inputs.count} form inputs lack proper labels.",
          recommendation: 'Add visible labels or aria-label attributes to all form inputs for accessibility and usability.'
        )
      end
    end

    def check_mobile_friendly_elements(client)
      return unless client.document
      
      # Check for horizontal scrolling indicators
      body = client.document.at_css('body')
      
      # Check for fixed-width elements that might cause horizontal scroll
      fixed_width_elements = client.document.css('[style*="width"][style*="px"]')
      
      large_fixed_widths = fixed_width_elements.select do |element|
        style = element['style']
        style.match?(/width\s*:\s*(\d+)px/) && $1.to_i > 600
      end
      
      if large_fixed_widths.count > 3
        add_issue(
          severity: 'medium',
          title: 'Fixed-Width Elements Detected',
          description: "Found #{large_fixed_widths.count} elements with fixed pixel widths over 600px.",
          recommendation: 'Use responsive units (%, vw, rem) instead of fixed pixel widths for better mobile compatibility.'
        )
      end
      
      # Check for presence of common mobile-unfriendly elements
      flash_objects = client.document.css('embed[type="application/x-shockwave-flash"], object[type="application/x-shockwave-flash"]')
      
      if flash_objects.any?
        add_issue(
          severity: 'high',
          title: 'Flash Content Detected',
          description: "Found #{flash_objects.count} Flash objects (not supported on mobile).",
          recommendation: 'Replace Flash content with modern HTML5 alternatives.'
        )
      end
    end

    # Helper methods for raw data
    def has_viewport_meta?(client)
      return false unless client.document
      client.document.at_css('meta[name="viewport"]').present?
    end

    def count_small_fonts(client)
      return 0 unless client.document
      elements_with_style = client.document.css('[style*="font-size"]')
      elements_with_style.select do |element|
        style = element['style']
        style.match?(/font-size\s*:\s*(\d+)px/) && $1.to_i < 16
      end.count
    end

    def count_forms(client)
      return 0 unless client.document
      client.document.css('form').count
    end

    def count_forms_without_labels(client)
      return 0 unless client.document
      inputs = client.document.css('input[type="text"], input[type="email"], input[type="tel"], textarea')
      inputs.reject do |input|
        input['id'] && client.document.at_css("label[for='#{input['id']}']")
      end.count
    end
  end
end
