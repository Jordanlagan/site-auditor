module Audits
  class ConversionPathService < BaseService
    def category
      'conversion_path'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_value_proposition(client)
      check_call_to_actions(client)
      check_above_the_fold(client)
      check_form_friction(client)
      check_navigation_clarity(client)
      check_button_design(client)
      check_urgency_scarcity(client)
      
      {
        score: calculate_score,
        raw_data: {
          cta_count: count_ctas(client),
          form_count: count_forms(client),
          primary_cta_above_fold: has_cta_above_fold?(client)
        }
      }
    end

    private

    def check_value_proposition(client)
      return unless client.document
      
      h1 = client.document.at_css('h1')
      
      if h1.nil? || h1.text.strip.length < 10
        add_issue(
          severity: 'high',
          title: 'Weak or Missing Value Proposition',
          description: 'Visitors cannot quickly understand what you offer and why they should care. You have 8 seconds to communicate value.',
          recommendation: 'Add clear H1 headline above the fold that answers: "What do you do? Who is it for? Why should I care?" Example: "Custom Website Design That Actually Converts - Guaranteed Results or Your Money Back"'
        )
      end
      
      # Check for subheadline
      has_subheadline = client.document.at_css('h2, .subtitle, .subheadline, p.lead')
      
      unless has_subheadline
        add_issue(
          severity: 'medium',
          title: 'No Supporting Subheadline',
          description: 'Missing subheadline to reinforce value proposition and elaborate on benefits.',
          recommendation: 'Add subheadline below H1 that expands on your unique selling points. Keep it benefit-focused, not feature-focused.'
        )
      end
    end

    def check_call_to_actions(client)
      return unless client.document
      
      cta_count = count_ctas(client)
      
      if cta_count == 0
        add_issue(
          severity: 'high',
          title: 'No Clear Call-to-Action Buttons',
          description: 'Visitors have no obvious next step. Missing CTAs kills conversion rates.',
          recommendation: 'Add prominent CTA buttons (e.g., "Get Started", "Shop Now", "Schedule Demo") above the fold and throughout page. Use action-oriented, benefit-driven copy.'
        )
      elsif cta_count > 5
        add_issue(
          severity: 'medium',
          title: 'Too Many Call-to-Action Buttons',
          description: "Found #{cta_count} CTA buttons. Too many choices causes decision paralysis and reduces conversions.",
          recommendation: 'Simplify to 1-2 primary CTAs per page section. Create clear visual hierarchy with one dominant CTA and secondary options.'
        )
      end
      
      # Check CTA copy quality
      buttons = client.document.css('button, a.btn, a.button, input[type="submit"]')
      generic_cta_count = buttons.count do |btn|
        text = btn.text.strip.downcase
        ['submit', 'click here', 'go', 'ok', 'send'].include?(text)
      end
      
      if generic_cta_count > 0
        add_issue(
          severity: 'medium',
          title: 'Generic CTA Button Copy',
          description: "Found #{generic_cta_count} buttons with generic text like 'Submit' or 'Click Here'. Specific copy converts better.",
          recommendation: 'Replace generic button text with benefit-driven copy. Bad: "Submit". Good: "Get My Free Quote", "Start Saving Money", "Download Guide Now"'
        )
      end
    end

    def check_above_the_fold(client)
      return unless client.document
      
      unless has_cta_above_fold?(client)
        add_issue(
          severity: 'high',
          title: 'No CTA Button Above the Fold',
          description: '80% of visitors never scroll below the fold. Missing CTA in hero section loses immediate conversion opportunities.',
          recommendation: 'Place primary CTA button in hero section, visible without scrolling. Pair with clear value proposition. Test contrasting colors for button.'
        )
      end
      
      # Check hero section height
      hero = client.document.at_css('header, .hero, #hero, section:first-of-type')
      if hero
        style = hero['style'].to_s
        # Check for excessive height
        if style.match?(/height:\s*100vh/) || style.match?(/min-height:\s*100vh/)
          add_issue(
            severity: 'medium',
            title: 'Hero Section Too Tall (100vh)',
            description: 'Full-screen hero sections push content below the fold and reduce engagement. Users want information, not artsy minimalism.',
            recommendation: 'Reduce hero height to 60-70vh or ~600px. Show preview of content below to encourage scrolling. Balance aesthetics with information delivery.'
          )
        end
      end
    end

    def check_form_friction(client)
      return unless client.document
      
      forms = client.document.css('form')
      
      forms.each do |form|
        inputs = form.css('input:not([type="hidden"]):not([type="submit"]), textarea, select')
        
        if inputs.count > 7
          add_issue(
            severity: 'high',
            title: 'Form Has Too Many Fields',
            description: "Found form with #{inputs.count} input fields. Each additional form field reduces conversions by ~11%.",
            recommendation: 'Remove non-essential fields. Ask only for what you need immediately. Use progressive profiling to collect more info later. Consider multi-step forms for long forms.'
          )
        end
        
        # Check for field labels
        inputs_without_labels = inputs.reject do |input|
          input_id = input['id']
          has_label = input_id && form.at_css("label[for='#{input_id}']")
          has_label || input['placeholder'] || input['aria-label']
        end
        
        if inputs_without_labels.any?
          add_issue(
            severity: 'medium',
            title: 'Form Fields Missing Labels',
            description: "#{inputs_without_labels.count} form fields lack proper labels. Reduces usability and accessibility.",
            recommendation: 'Add visible labels above each input field. Placeholders disappear when typing. Good labels improve form completion rates by 20%.'
          )
        end
        
        # Check for inline validation
        has_validation = form['novalidate'].nil?
        unless has_validation
          add_issue(
            severity: 'low',
            title: 'Form Lacks Inline Validation',
            description: 'Real-time form validation improves user experience and reduces errors.',
            recommendation: 'Add inline validation that checks fields as user types. Show green checkmarks for valid entries. Explain errors immediately, not after submission.'
          )
        end
      end
    end

    def check_navigation_clarity(client)
      return unless client.document
      
      nav = client.document.at_css('nav, .navigation, #navigation')
      
      if nav
        nav_links = nav.css('a')
        
        if nav_links.count > 8
          add_issue(
            severity: 'medium',
            title: 'Navigation Has Too Many Items',
            description: "Found #{nav_links.count} navigation links. Excessive options cause decision paralysis.",
            recommendation: 'Limit primary navigation to 5-7 items. Use dropdown menus for secondary pages. Prioritize pages that drive conversions.'
          )
        end
        
        # Check for descriptive link text
        vague_links = nav_links.count do |link|
          text = link.text.strip.downcase
          ['more', 'click here', 'learn more', 'info', 'other'].include?(text)
        end
        
        if vague_links > 0
          add_issue(
            severity: 'low',
            title: 'Navigation Links Have Vague Text',
            description: 'Non-descriptive link text hurts both UX and SEO.',
            recommendation: 'Use specific, descriptive navigation labels. Bad: "Services". Better: "Web Design Services". Best: "Custom Website Design"'
          )
        end
      end
    end

    def check_button_design(client)
      return unless client.document
      
      buttons = client.document.css('button, .button, .btn, input[type="submit"]')
      
      # Check for button contrast
      buttons_with_style = buttons.select { |btn| btn['style'] }
      
      if buttons_with_style.any?
        low_contrast = buttons_with_style.any? do |btn|
          style = btn['style'].downcase
          # Check for light colors that might have poor contrast
          style.include?('background') && (style.include?('#fff') || style.include?('white') || style.include?('transparent'))
        end
        
        if low_contrast
          add_issue(
            severity: 'medium',
            title: 'Buttons May Have Poor Contrast',
            description: 'Low-contrast buttons are harder to see and get fewer clicks.',
            recommendation: 'Use high-contrast colors for CTA buttons. Primary CTAs should pop off the page. Test with 3:1 contrast ratio minimum. Avoid white/light gray buttons.'
          )
        end
      end
      
      # Check button size
      small_buttons = buttons.select do |btn|
        style = btn['style'].to_s
        style.match?(/padding:\s*[0-5]px/) || style.match?(/font-size:\s*(10|11|12)px/)
      end
      
      if small_buttons.count > buttons.count * 0.3
        add_issue(
          severity: 'medium',
          title: 'Buttons May Be Too Small',
          description: 'Small buttons are harder to click, especially on mobile. Reduces conversion rates.',
          recommendation: 'Make buttons larger: minimum 44x44px for mobile (Apple), 48x48px recommended. Use padding: 12px 32px; font-size: 16px+ for desktop.'
        )
      end
    end

    def check_urgency_scarcity(client)
      return unless client.document
      
      html = client.html.downcase
      
      # Check for urgency/scarcity elements
      has_urgency = html.include?('limited time') || html.include?('expires') || 
                   html.include?('hurry') || html.include?('countdown') ||
                   html.include?('only') && html.include?('left') ||
                   html.include?('stock')
      
      unless has_urgency
        add_issue(
          severity: 'low',
          title: 'No Urgency or Scarcity Indicators',
          description: 'Adding urgency can increase conversions by 20-30% when used authentically.',
          recommendation: 'If applicable, add urgency elements: limited-time offers, countdown timers, low stock warnings, seasonal promotions. Must be genuine - fake scarcity damages trust.'
        )
      end
    end

    # Helper methods
    def count_ctas(client)
      return 0 unless client.document
      client.document.css('button, .button, .btn, a.cta, input[type="submit"]').count
    end

    def count_forms(client)
      return 0 unless client.document
      client.document.css('form').count
    end

    def has_cta_above_fold?(client)
      return false unless client.document
      
      # Check first section/header for CTA
      hero_section = client.document.at_css('header, .hero, #hero, section:first-of-type, .header')
      return false unless hero_section
      
      ctas = hero_section.css('button, .button, .btn, a.cta, input[type="submit"]')
      ctas.any?
    end
  end
end
