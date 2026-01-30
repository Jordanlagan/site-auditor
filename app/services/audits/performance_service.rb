module Audits
  class PerformanceService < BaseService
    def category
      'performance'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_page_weight(client)
      check_resource_count(client)
      check_render_blocking(client)
      check_image_optimization(client)
      
      {
        score: calculate_score,
        raw_data: {
          page_weight: client.page_weight,
          resource_count: client.resource_urls.count,
          response_time_ms: measure_response_time
        }
      }
    end

    private

    def check_page_weight(client)
      weight_kb = client.page_weight / 1024.0
      
      if weight_kb > 3000
        add_issue(
          severity: 'high',
          title: 'Excessive Page Weight',
          description: "Page size is #{weight_kb.round(2)} KB, which is very large.",
          recommendation: 'Optimize images, minify CSS/JS, and enable compression. Target under 1.5 MB.'
        )
      elsif weight_kb > 1500
        add_issue(
          severity: 'medium',
          title: 'Large Page Weight',
          description: "Page size is #{weight_kb.round(2)} KB.",
          recommendation: 'Consider optimizing images and enabling compression. Target under 1 MB.'
        )
      end
    end

    def check_resource_count(client)
      count = client.resource_urls.count
      
      if count > 100
        add_issue(
          severity: 'high',
          title: 'Too Many HTTP Requests',
          description: "Page makes #{count} resource requests.",
          recommendation: 'Combine files, use sprites, and implement lazy loading. Target under 50 requests.'
        )
      elsif count > 50
        add_issue(
          severity: 'medium',
          title: 'High Number of HTTP Requests',
          description: "Page makes #{count} resource requests.",
          recommendation: 'Consider combining resources and implementing lazy loading.'
        )
      end
    end

    def check_render_blocking(client)
      return unless client.document
      
      # Check for synchronous scripts in head
      blocking_scripts = client.document.css('head script:not([async]):not([defer])')
      
      if blocking_scripts.count > 3
        add_issue(
          severity: 'medium',
          title: 'Render-Blocking JavaScript',
          description: "Found #{blocking_scripts.count} synchronous scripts in the head.",
          recommendation: 'Add async or defer attributes to non-critical scripts, or move them to the footer.'
        )
      end
      
      # Check for stylesheets
      stylesheets = client.document.css('link[rel="stylesheet"]')
      
      if stylesheets.count > 5
        add_issue(
          severity: 'low',
          title: 'Multiple Stylesheets',
          description: "Found #{stylesheets.count} separate stylesheet files.",
          recommendation: 'Combine stylesheets to reduce HTTP requests and render blocking.'
        )
      end
    end

    def check_image_optimization(client)
      return unless client.document
      
      images = client.document.css('img[src]')
      images_without_dimensions = images.reject { |img| img['width'] || img['height'] }
      
      if images_without_dimensions.count > images.count * 0.5
        add_issue(
          severity: 'medium',
          title: 'Images Missing Dimensions',
          description: "#{images_without_dimensions.count} of #{images.count} images lack width/height attributes.",
          recommendation: 'Add explicit width and height attributes to prevent layout shifts.'
        )
      end
      
      # Check for modern image formats
      webp_images = images.select { |img| img['src']&.match?(/\.webp$/i) }
      
      if images.count > 5 && webp_images.empty?
        add_issue(
          severity: 'low',
          title: 'No Modern Image Formats Detected',
          description: 'No WebP images detected on the page.',
          recommendation: 'Consider using WebP format for better compression and faster loading.'
        )
      end
    end

    def measure_response_time
      start_time = Time.now
      uri = URI.parse(url)
      
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.open_timeout = 5
      http.read_timeout = 10
      
      request = Net::HTTP::Get.new(uri.request_uri)
      http.request(request)
      
      ((Time.now - start_time) * 1000).round
    rescue StandardError
      nil
    end
  end
end
