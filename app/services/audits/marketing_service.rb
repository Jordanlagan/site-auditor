module Audits
  class MarketingService < BaseService
    def category
      'marketing'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_google_analytics(client)
      check_google_tag_manager(client)
      check_meta_pixel(client)
      check_duplicate_tracking(client)
      
      {
        score: calculate_score,
        raw_data: {
          has_ga4: has_google_analytics?(client),
          has_gtm: has_google_tag_manager?(client),
          has_meta_pixel: has_meta_pixel?(client),
          tracking_scripts_count: count_tracking_scripts(client)
        }
      }
    end

    private

    def check_google_analytics(client)
      return unless client.document
      
      html = client.html
      
      # Check for GA4 (gtag.js or Google Tag)
      has_ga4 = html.match?(/gtag\(|googletagmanager\.com\/gtag\/js|G-[A-Z0-9]+/)
      
      # Check for Universal Analytics (analytics.js)
      has_ua = html.match?(/google-analytics\.com\/analytics\.js|UA-\d+-\d+/)
      
      unless has_ga4 || has_ua
        add_issue(
          severity: 'high',
          title: 'Google Analytics Not Detected',
          description: 'No Google Analytics tracking code found.',
          recommendation: 'Install Google Analytics 4 (GA4) to track website traffic and user behavior.'
        )
      end
      
      if has_ua && !has_ga4
        add_issue(
          severity: 'medium',
          title: 'Using Legacy Universal Analytics',
          description: 'Universal Analytics detected, but GA4 not found.',
          recommendation: 'Migrate to Google Analytics 4 (GA4) as Universal Analytics is deprecated.'
        )
      end
    end

    def check_google_tag_manager(client)
      return unless client.document
      
      html = client.html
      
      # Check for GTM
      has_gtm = html.match?(/googletagmanager\.com\/gtm\.js|GTM-[A-Z0-9]+/)
      
      unless has_gtm
        add_issue(
          severity: 'low',
          title: 'Google Tag Manager Not Detected',
          description: 'No Google Tag Manager found.',
          recommendation: 'Consider implementing Google Tag Manager for easier tag management and marketing tool integration.'
        )
      end
    end

    def check_meta_pixel(client)
      return unless client.document
      
      html = client.html
      
      # Check for Meta Pixel (Facebook Pixel)
      has_meta_pixel = html.match?(/connect\.facebook\.net\/en_US\/fbevents\.js|fbq\(/)
      
      unless has_meta_pixel
        add_issue(
          severity: 'low',
          title: 'Meta Pixel Not Detected',
          description: 'No Meta (Facebook) Pixel found.',
          recommendation: 'If running Meta ads, install Meta Pixel to track conversions and build audiences.'
        )
      end
    end

    def check_duplicate_tracking(client)
      return unless client.document
      
      html = client.html
      
      # Check for duplicate GA installations
      ga_matches = html.scan(/gtag\('config',\s*['"]([^'"]+)['"]/).flatten
      
      if ga_matches.uniq.length != ga_matches.length
        duplicates = ga_matches.group_by { |e| e }.select { |k, v| v.size > 1 }.keys
        add_issue(
          severity: 'medium',
          title: 'Duplicate Analytics Tracking',
          description: "Google Analytics ID(s) appear multiple times: #{duplicates.join(', ')}.",
          recommendation: 'Remove duplicate tracking codes to prevent inflated metrics and data accuracy issues.'
        )
      end
      
      # Check for duplicate Meta Pixel
      meta_pixel_matches = html.scan(/fbq\('init',\s*['"](\d+)['"]/).flatten
      
      if meta_pixel_matches.uniq.length != meta_pixel_matches.length
        add_issue(
          severity: 'medium',
          title: 'Duplicate Meta Pixel',
          description: 'Meta Pixel is installed multiple times.',
          recommendation: 'Remove duplicate Meta Pixel installations to ensure accurate event tracking.'
        )
      end
      
      # Check for excessive number of tracking scripts
      tracking_count = count_tracking_scripts(client)
      
      if tracking_count > 10
        add_issue(
          severity: 'low',
          title: 'Excessive Tracking Scripts',
          description: "Found #{tracking_count} tracking/analytics scripts.",
          recommendation: 'Consolidate tracking tools and remove unused scripts to improve page performance.'
        )
      end
    end

    # Helper methods for raw data
    def has_google_analytics?(client)
      return false unless client.document
      html = client.html
      html.match?(/gtag\(|googletagmanager\.com\/gtag\/js|google-analytics\.com\/analytics\.js/)
    end

    def has_google_tag_manager?(client)
      return false unless client.document
      html = client.html
      html.match?(/googletagmanager\.com\/gtm\.js/)
    end

    def has_meta_pixel?(client)
      return false unless client.document
      html = client.html
      html.match?(/connect\.facebook\.net\/en_US\/fbevents\.js|fbq\(/)
    end

    def count_tracking_scripts(client)
      return 0 unless client.document
      
      # Common tracking domains
      tracking_domains = [
        'google-analytics.com',
        'googletagmanager.com',
        'facebook.net',
        'doubleclick.net',
        'hotjar.com',
        'google.com/recaptcha',
        'analytics',
        'tracking',
        'tag',
        'pixel'
      ]
      
      scripts = client.document.css('script[src]')
      scripts.count do |script|
        src = script['src'].to_s.downcase
        tracking_domains.any? { |domain| src.include?(domain) }
      end
    end
  end
end
