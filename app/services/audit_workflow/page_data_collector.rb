# frozen_string_literal: true

module AuditWorkflow
  class PageDataCollector
    attr_reader :page, :html_doc, :css_content

    def initialize(page, html_doc, css_content = nil)
      @page = page
      @html_doc = html_doc
      @css_content = css_content
    end

    def collect_all_metrics
      {
        content_metrics: collect_content_metrics,
        asset_metrics: collect_asset_metrics,
        link_metrics: collect_link_metrics,
        visual_metrics: collect_visual_metrics,
        technical_metrics: collect_technical_metrics,
        ux_metrics: collect_ux_metrics
      }
    end

    private

    def collect_content_metrics
      text_content = html_doc.css("body").text
      words = text_content.split(/\s+/).reject(&:empty?)

      {
        word_count: words.length,
        character_count: text_content.length,
        paragraph_count: html_doc.css("p").count,
        heading_counts: {
          h1: html_doc.css("h1").count,
          h2: html_doc.css("h2").count,
          h3: html_doc.css("h3").count,
          h4: html_doc.css("h4").count,
          h5: html_doc.css("h5").count,
          h6: html_doc.css("h6").count
        },
        list_count: html_doc.css("ul, ol").count,
        list_item_count: html_doc.css("li").count,
        reading_time_minutes: (words.length / 200.0).ceil
      }
    end

    def collect_asset_metrics
      images = html_doc.css("img")
      scripts = html_doc.css("script[src]")
      stylesheets = html_doc.css('link[rel="stylesheet"]')

      {
        image_count: images.count,
        images_without_alt: images.select { |img| img["alt"].nil? || img["alt"].empty? }.count,
        script_count: scripts.count,
        external_script_count: scripts.select { |s| s["src"]&.start_with?("http") }.count,
        stylesheet_count: stylesheets.count,
        video_count: html_doc.css('video, iframe[src*="youtube"], iframe[src*="vimeo"]').count,
        favicon_present: html_doc.css('link[rel="icon"], link[rel="shortcut icon"]').any?,
        svg_count: html_doc.css("svg").count,

        # Asset sources for weight calculation
        image_sources: images.map { |img| img["src"] }.compact,
        script_sources: scripts.map { |s| s["src"] }.compact,
        stylesheet_sources: stylesheets.map { |s| s["href"] }.compact
      }
    end

    def collect_link_metrics
      all_links = html_doc.css("a[href]")
      internal_links = []
      external_links = []

      all_links.each do |link|
        href = link["href"]
        next if href.nil? || href.start_with?("#", "javascript:", "mailto:", "tel:")

        if href.start_with?("http")
          # Check if it's same domain
          begin
            link_uri = URI.parse(href)
            page_uri = URI.parse(page.url)
            if link_uri.host == page_uri.host
              internal_links << href
            else
              external_links << href
            end
          rescue URI::InvalidURIError
            # Skip invalid URLs
          end
        else
          internal_links << href
        end
      end

      {
        total_links: all_links.count,
        internal_links: internal_links.count,
        external_links: external_links.count,
        broken_link_candidates: all_links.select { |l| l["href"]&.empty? }.count,
        links_without_text: all_links.select { |l| l.text.strip.empty? && !l.css("img").any? }.count,
        links_opening_new_tab: all_links.select { |l| l["target"] == "_blank" }.count,

        # For backlink calculation (to be filled by crawler)
        inbound_links_count: page.crawl_metadata&.dig("inbound_links_count") || 0
      }
    end

    def collect_visual_metrics
      colors = extract_colors_from_css

      {
        primary_colors: colors[:primary],
        text_colors: colors[:text],
        background_colors: colors[:background],
        font_families: extract_font_families,
        custom_fonts_count: html_doc.css('link[href*="fonts"], style:contains("@font-face")').count
      }
    end

    def collect_technical_metrics
      forms = html_doc.css("form")
      inputs = html_doc.css("input, textarea, select")

      {
        form_count: forms.count,
        input_count: inputs.count,
        button_count: html_doc.css('button, input[type="submit"], input[type="button"]').count,

        # Meta tags
        meta_description: html_doc.at_css('meta[name="description"]')&.[]("content"),
        meta_description_length: html_doc.at_css('meta[name="description"]')&.[]("content")&.length || 0,
        meta_keywords: html_doc.at_css('meta[name="keywords"]')&.[]("content"),
        og_tags_present: html_doc.css('meta[property^="og:"]').any?,
        twitter_card_present: html_doc.css('meta[name^="twitter:"]').any?,

        # Schema markup
        json_ld_count: html_doc.css('script[type="application/ld+json"]').count,
        microdata_present: html_doc.css("[itemtype]").any?,

        # Viewport
        viewport_meta: html_doc.at_css('meta[name="viewport"]')&.[]("content"),
        mobile_optimized: html_doc.at_css('meta[name="viewport"]')&.[]("content")&.include?("width=device-width") || false,

        # HTML validation basics
        doctype_present: html_doc.to_html.start_with?("<!DOCTYPE"),
        lang_attribute: html_doc.at_css("html")&.[]("lang"),

        # Performance hints
        dns_prefetch_count: html_doc.css('link[rel="dns-prefetch"]').count,
        preconnect_count: html_doc.css('link[rel="preconnect"]').count,
        preload_count: html_doc.css('link[rel="preload"]').count
      }
    end

    def collect_ux_metrics
      {
        # Navigation
        has_nav: html_doc.css("nav").any?,
        nav_links_count: html_doc.css("nav a").count,

        # CTAs
        cta_buttons: identify_cta_buttons,

        # Forms
        forms_with_labels: html_doc.css("form").count { |form| form.css("label").any? },
        required_fields: html_doc.css("input[required], textarea[required], select[required]").count,

        # Accessibility
        aria_labels_count: html_doc.css("[aria-label], [aria-labelledby]").count,
        skip_link_present: html_doc.css('a[href="#main"], a[href="#content"]').any?,

        # Content overlap detection (basic)
        fixed_elements: html_doc.css('[style*="position: fixed"], [style*="position: sticky"]').count,

        # Search
        search_present: html_doc.css('input[type="search"], [role="search"]').any?
      }
    end

    def extract_colors_from_css
      colors = { primary: [], text: [], background: [] }

      return colors unless css_content

      # Extract color values from CSS (basic pattern matching)
      css_colors = css_content.scan(/#[0-9A-Fa-f]{3,6}|rgb\([^)]+\)|rgba\([^)]+\)|hsl\([^)]+\)|hsla\([^)]+\)/)

      # Categorize by frequency (top 5 as primary)
      color_freq = css_colors.tally.sort_by { |_, count| -count }
      colors[:primary] = color_freq.first(5).map(&:first)

      colors
    rescue
      colors
    end

    def extract_font_families
      families = []

      # From inline styles
      html_doc.css('[style*="font-family"]').each do |elem|
        if elem["style"] =~ /font-family:\s*([^;]+)/
          families << $1.strip
        end
      end

      # From CSS
      if css_content
        css_content.scan(/font-family:\s*([^;]+)/).each do |match|
          families << match.first.strip
        end
      end

      families.uniq.first(10)
    rescue
      []
    end

    def identify_cta_buttons
      ctas = []

      # Look for buttons with common CTA keywords
      cta_keywords = [ "buy", "purchase", "sign up", "subscribe", "download", "get started",
                      "learn more", "contact", "book", "order", "shop", "try", "start" ]

      html_doc.css('button, a.button, a.btn, input[type="submit"]').each do |elem|
        text = elem.text.strip.downcase
        if cta_keywords.any? { |kw| text.include?(kw) }
          ctas << {
            text: elem.text.strip,
            type: elem.name,
            classes: elem["class"]
          }
        end
      end

      ctas
    end
  end
end
