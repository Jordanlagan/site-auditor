module Audits
  class SeoService < BaseService
    def category
      'seo'
    end

    def perform
      client = HttpClient.new(url).fetch
      return unless client&.success?

      check_title_tag(client)
      check_meta_description(client)
      check_h1_tags(client)
      check_canonical_tag(client)
      check_robots_txt
      check_sitemap_xml
      check_image_alt_attributes(client)
      check_open_graph(client)
      
      {
        score: calculate_score,
        raw_data: {
          title_length: get_title_length(client),
          meta_description_length: get_meta_description_length(client),
          h1_count: count_h1_tags(client),
          images_without_alt: count_images_without_alt(client)
        }
      }
    end

    private

    def check_title_tag(client)
      return unless client.document
      
      title = client.document.at_css('title')
      
      if title.nil? || title.text.strip.empty?
        add_issue(
          severity: 'high',
          title: 'Missing Title Tag',
          description: 'No title tag found on the page.',
          recommendation: 'Add a descriptive title tag (50-60 characters) that includes target keywords.'
        )
        return
      end
      
      title_length = title.text.strip.length
      
      if title_length < 30
        add_issue(
          severity: 'medium',
          title: 'Title Tag Too Short',
          description: "Title tag is only #{title_length} characters.",
          recommendation: 'Expand title to 50-60 characters for better SEO impact.'
        )
      elsif title_length > 60
        add_issue(
          severity: 'low',
          title: 'Title Tag Too Long',
          description: "Title tag is #{title_length} characters (may be truncated in search results).",
          recommendation: 'Shorten title to 50-60 characters to prevent truncation.'
        )
      end
    end

    def check_meta_description(client)
      return unless client.document
      
      meta_desc = client.document.at_css('meta[name="description"]')
      
      if meta_desc.nil? || meta_desc['content'].to_s.strip.empty?
        add_issue(
          severity: 'high',
          title: 'Missing Meta Description',
          description: 'No meta description found.',
          recommendation: 'Add a compelling meta description (150-160 characters) to improve click-through rates.'
        )
        return
      end
      
      desc_length = meta_desc['content'].strip.length
      
      if desc_length < 120
        add_issue(
          severity: 'medium',
          title: 'Meta Description Too Short',
          description: "Meta description is only #{desc_length} characters.",
          recommendation: 'Expand to 150-160 characters to maximize search result snippet.'
        )
      elsif desc_length > 160
        add_issue(
          severity: 'low',
          title: 'Meta Description Too Long',
          description: "Meta description is #{desc_length} characters (may be truncated).",
          recommendation: 'Shorten to 150-160 characters to prevent truncation in search results.'
        )
      end
    end

    def check_h1_tags(client)
      return unless client.document
      
      h1_tags = client.document.css('h1')
      
      if h1_tags.empty?
        add_issue(
          severity: 'high',
          title: 'Missing H1 Tag',
          description: 'No H1 heading found on the page.',
          recommendation: 'Add a single H1 tag that clearly describes the page content.'
        )
      elsif h1_tags.count > 1
        add_issue(
          severity: 'medium',
          title: 'Multiple H1 Tags',
          description: "Found #{h1_tags.count} H1 tags on the page.",
          recommendation: 'Use only one H1 tag per page for better SEO structure.'
        )
      end
    end

    def check_canonical_tag(client)
      return unless client.document
      
      canonical = client.document.at_css('link[rel="canonical"]')
      
      if canonical.nil?
        add_issue(
          severity: 'low',
          title: 'Missing Canonical Tag',
          description: 'No canonical tag found.',
          recommendation: 'Add a canonical tag to prevent duplicate content issues.'
        )
      end
    end

    def check_robots_txt
      uri = URI.parse(url)
      robots_url = "#{uri.scheme}://#{uri.host}/robots.txt"
      
      response = Net::HTTP.get_response(URI.parse(robots_url))
      
      unless response.is_a?(Net::HTTPSuccess)
        add_issue(
          severity: 'low',
          title: 'Missing robots.txt',
          description: 'No robots.txt file found.',
          recommendation: 'Create a robots.txt file to guide search engine crawlers.'
        )
      end
    rescue StandardError
      # Ignore network errors for robots.txt check
    end

    def check_sitemap_xml
      uri = URI.parse(url)
      sitemap_url = "#{uri.scheme}://#{uri.host}/sitemap.xml"
      
      response = Net::HTTP.get_response(URI.parse(sitemap_url))
      
      unless response.is_a?(Net::HTTPSuccess)
        add_issue(
          severity: 'medium',
          title: 'Missing sitemap.xml',
          description: 'No sitemap.xml file found.',
          recommendation: 'Create and submit an XML sitemap to help search engines discover your content.'
        )
      end
    rescue StandardError
      # Ignore network errors for sitemap check
    end

    def check_image_alt_attributes(client)
      return unless client.document
      
      images = client.document.css('img')
      images_without_alt = images.reject { |img| img['alt'] }
      
      if images.any? && images_without_alt.count > images.count * 0.3
        add_issue(
          severity: 'medium',
          title: 'Images Missing Alt Attributes',
          description: "#{images_without_alt.count} of #{images.count} images lack alt attributes.",
          recommendation: 'Add descriptive alt text to all images for accessibility and SEO.'
        )
      end
    end

    def check_open_graph(client)
      return unless client.document
      
      og_title = client.document.at_css('meta[property="og:title"]')
      og_description = client.document.at_css('meta[property="og:description"]')
      og_image = client.document.at_css('meta[property="og:image"]')
      
      missing = []
      missing << 'og:title' unless og_title
      missing << 'og:description' unless og_description
      missing << 'og:image' unless og_image
      
      if missing.any?
        add_issue(
          severity: 'low',
          title: 'Incomplete Open Graph Tags',
          description: "Missing Open Graph tags: #{missing.join(', ')}.",
          recommendation: 'Add complete Open Graph tags for better social media sharing.'
        )
      end
    end

    # Helper methods for raw data
    def get_title_length(client)
      return 0 unless client.document
      title = client.document.at_css('title')
      title ? title.text.strip.length : 0
    end

    def get_meta_description_length(client)
      return 0 unless client.document
      meta_desc = client.document.at_css('meta[name="description"]')
      meta_desc ? meta_desc['content'].to_s.strip.length : 0
    end

    def count_h1_tags(client)
      return 0 unless client.document
      client.document.css('h1').count
    end

    def count_images_without_alt(client)
      return 0 unless client.document
      images = client.document.css('img')
      images.reject { |img| img['alt'] }.count
    end
  end
end
