module Audits
  class SecurityService < BaseService
    def category
      'security'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_https(client)
      check_mixed_content(client)
      check_security_headers(client)
      check_cms_detection(client)
      
      {
        score: calculate_score,
        raw_data: {
          is_https: is_https?(client),
          has_hsts: has_hsts?(client),
          has_csp: has_csp?(client),
          has_x_frame_options: has_x_frame_options?(client),
          detected_cms: detect_cms(client)
        }
      }
    end

    private

    def check_https(client)
      uri = URI.parse(url)
      
      unless uri.scheme == 'https'
        add_issue(
          severity: 'high',
          title: 'Not Using HTTPS',
          description: 'Website is not served over HTTPS.',
          recommendation: 'Install an SSL certificate and enforce HTTPS to protect user data and improve SEO.'
        )
        return
      end
      
      # Check if HTTP redirects to HTTPS
      begin
        http_uri = URI.parse(url.sub('https://', 'http://'))
        http_response = Net::HTTP.get_response(http_uri)
        
        if http_response.is_a?(Net::HTTPRedirection)
          location = http_response['location']
          unless location&.start_with?('https://')
            add_issue(
              severity: 'medium',
              title: 'HTTP Does Not Redirect to HTTPS',
              description: 'HTTP version does not properly redirect to HTTPS.',
              recommendation: 'Configure server to redirect all HTTP traffic to HTTPS.'
            )
          end
        elsif http_response.is_a?(Net::HTTPSuccess)
          add_issue(
            severity: 'high',
            title: 'HTTP Version Still Accessible',
            description: 'Website is accessible over both HTTP and HTTPS without redirect.',
            recommendation: 'Enforce HTTPS by redirecting all HTTP requests to HTTPS.'
          )
        end
      rescue StandardError
        # Ignore errors in HTTP check
      end
    end

    def check_mixed_content(client)
      return unless client.document
      return unless is_https?(client)
      
      html = client.html
      
      # Check for HTTP resources in HTTPS page
      http_resources = []
      
      # Check scripts
      http_scripts = client.document.css('script[src^="http://"]')
      http_resources << "#{http_scripts.count} scripts" if http_scripts.any?
      
      # Check stylesheets
      http_styles = client.document.css('link[rel="stylesheet"][href^="http://"]')
      http_resources << "#{http_styles.count} stylesheets" if http_styles.any?
      
      # Check images
      http_images = client.document.css('img[src^="http://"]')
      http_resources << "#{http_images.count} images" if http_images.any?
      
      if http_resources.any?
        add_issue(
          severity: 'high',
          title: 'Mixed Content Detected',
          description: "Found insecure HTTP resources: #{http_resources.join(', ')}.",
          recommendation: 'Update all resource URLs to use HTTPS or relative paths to prevent security warnings.'
        )
      end
    end

    def check_security_headers(client)
      headers = client.headers
      
      # Check for HSTS
      unless headers['strict-transport-security']
        add_issue(
          severity: 'medium',
          title: 'Missing HSTS Header',
          description: 'Strict-Transport-Security header not found.',
          recommendation: 'Add HSTS header to force browsers to use HTTPS: Strict-Transport-Security: max-age=31536000; includeSubDomains'
        )
      end
      
      # Check for CSP
      unless headers['content-security-policy'] || headers['content-security-policy-report-only']
        add_issue(
          severity: 'medium',
          title: 'Missing Content Security Policy',
          description: 'Content-Security-Policy header not found.',
          recommendation: 'Implement CSP header to prevent XSS attacks and unauthorized resource loading.'
        )
      end
      
      # Check for X-Frame-Options
      unless headers['x-frame-options']
        add_issue(
          severity: 'medium',
          title: 'Missing X-Frame-Options Header',
          description: 'X-Frame-Options header not found.',
          recommendation: 'Add X-Frame-Options header to prevent clickjacking: X-Frame-Options: SAMEORIGIN'
        )
      end
      
      # Check for X-Content-Type-Options
      unless headers['x-content-type-options']
        add_issue(
          severity: 'low',
          title: 'Missing X-Content-Type-Options Header',
          description: 'X-Content-Type-Options header not found.',
          recommendation: 'Add X-Content-Type-Options: nosniff to prevent MIME type sniffing.'
        )
      end
      
      # Check for X-XSS-Protection (legacy but still useful)
      unless headers['x-xss-protection']
        add_issue(
          severity: 'low',
          title: 'Missing X-XSS-Protection Header',
          description: 'X-XSS-Protection header not found.',
          recommendation: 'Add X-XSS-Protection: 1; mode=block for legacy browser protection.'
        )
      end
    end

    def check_cms_detection(client)
      return unless client.document
      
      cms = detect_cms(client)
      
      if cms
        html = client.html.downcase
        
        # Check for version exposure
        version_exposed = false
        
        case cms
        when 'WordPress'
          version_match = html.match(/wordpress\s+(\d+\.\d+\.\d+)/i)
          version_exposed = version_match.present?
          
          # Check for common WordPress security issues
          if html.include?('/wp-content/') || html.include?('/wp-includes/')
            add_issue(
              severity: 'low',
              title: 'WordPress Paths Exposed',
              description: 'WordPress directory structure is visible.',
              recommendation: 'Consider obscuring WordPress paths and remove version information for security.'
            )
          end
          
        when 'Shopify'
          # Shopify is generally secure by default
          
        when 'Wix'
          # Wix is generally secure by default
          
        when 'Squarespace'
          # Squarespace is generally secure by default
        end
        
        if version_exposed
          add_issue(
            severity: 'low',
            title: 'CMS Version Exposed',
            description: "#{cms} version information is publicly visible.",
            recommendation: 'Remove version information from HTML to reduce attack surface.'
          )
        end
      end
    end

    # Helper methods for raw data
    def is_https?(client)
      uri = URI.parse(client.redirected_url || url)
      uri.scheme == 'https'
    end

    def has_hsts?(client)
      client.headers['strict-transport-security'].present?
    end

    def has_csp?(client)
      client.headers['content-security-policy'].present? || 
        client.headers['content-security-policy-report-only'].present?
    end

    def has_x_frame_options?(client)
      client.headers['x-frame-options'].present?
    end

    def detect_cms(client)
      return nil unless client.document
      
      html = client.html.downcase
      
      # WordPress
      return 'WordPress' if html.include?('wp-content') || html.include?('wp-includes')
      
      # Shopify
      return 'Shopify' if html.include?('cdn.shopify.com') || html.include?('shopify')
      
      # Wix
      return 'Wix' if html.include?('wix.com') || html.include?('static.wixstatic.com')
      
      # Squarespace
      return 'Squarespace' if html.include?('squarespace') || html.include?('sqsp')
      
      # Webflow
      return 'Webflow' if html.include?('webflow')
      
      # Drupal
      return 'Drupal' if html.include?('drupal') || html.include?('/sites/default/')
      
      # Joomla
      return 'Joomla' if html.include?('joomla') || html.include?('/components/com_')
      
      nil
    end
  end
end
