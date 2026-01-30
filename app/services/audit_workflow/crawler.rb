# frozen_string_literal: true

module AuditWorkflow
  class Crawler
    attr_reader :homepage_url, :visited_urls, :discovered_pages
    attr_accessor :audit

    def initialize(homepage_url, audit = nil)
      @homepage_url = normalize_url(homepage_url)
      @visited_urls = Set.new
      @discovered_pages = []
      @domain = URI.parse(@homepage_url).host
      @audit = audit
    end

    def discover_pages(max_depth: 2, max_pages: 20)
      crawl_page(@homepage_url, depth: 0, max_depth: max_depth, max_pages: max_pages)
      discovered_pages
    end

    def calculate_backlinks
      # After crawling, calculate how many internal pages link to each page
      all_pages = audit.discovered_pages.to_a
      backlink_counts = Hash.new(0)

      all_pages.each do |page|
        # Parse the page to find its internal links
        client = Audits::HttpClient.new(page.url).fetch
        next unless client&.success? && client.document

        client.document.css("a[href]").each do |link|
          href = link["href"]
          next if href.nil? || href.empty?
          next if href.start_with?("#", "javascript:", "mailto:", "tel:")

          # Normalize and find the target page
          begin
            target_url = URI.join(page.url, href).to_s
            target_page = all_pages.find { |p| p.url == target_url }
            backlink_counts[target_page.id] += 1 if target_page
          rescue URI::InvalidURIError
            # Skip invalid URLs
          end
        end
      end

      # Update all pages with their backlink counts
      backlink_counts.each do |page_id, count|
        page = all_pages.find { |p| p.id == page_id }
        if page
          metadata = page.crawl_metadata || {}
          metadata["inbound_links_count"] = count
          page.update!(crawl_metadata: metadata)
        end
      end

      Rails.logger.info "Calculated backlinks for #{backlink_counts.size} pages"
    end

    private

    def crawl_page(url, depth:, max_depth:, max_pages:)
      return if visited_urls.size >= max_pages
      return if depth > max_depth
      return if visited_urls.include?(url)

      visited_urls.add(url)

      client = Audits::HttpClient.new(url).fetch
      return unless client&.success?

      doc = client.document

      # Classify page type
      page_type = classify_page(url, doc)

      # Extract metadata
      metadata = extract_metadata(url, doc, depth)

      discovered_pages << {
        url: url,
        type: page_type,
        metadata: metadata
      }

      # Find links to crawl next
      if depth < max_depth
        links = extract_links(doc)
        links.each do |link|
          next if visited_urls.size >= max_pages
          crawl_page(link, depth: depth + 1, max_depth: max_depth, max_pages: max_pages)
        end
      end

    rescue StandardError => e
      Rails.logger.error("Crawl error for #{url}: #{e.message}")
    end

    def classify_page(url, doc)
      path = URI.parse(url).path.downcase
      title = doc.css("title").text.downcase
      h1 = doc.css("h1").first&.text&.downcase || ""

      return "homepage" if path == "/" || path.empty?
      return "pricing" if path.include?("pricing") || title.include?("pricing")
      return "product" if path.include?("product") || path.include?("shop")
      return "checkout" if path.include?("checkout") || path.include?("cart")
      return "contact" if path.include?("contact") || title.include?("contact")
      return "about" if path.include?("about")
      return "blog" if path.include?("blog") || path.include?("article")

      # Check for landing page patterns
      if doc.css("form").any? && (h1.include?("get") || h1.include?("start"))
        return "landing"
      end

      "other"
    end

    def extract_metadata(url, doc, depth)
      {
        depth: depth,
        title: doc.css("title").text,
        h1_count: doc.css("h1").count,
        form_count: doc.css("form").count,
        button_count: doc.css('button, input[type="submit"]').count,
        external_links: count_external_links(doc),
        internal_links: count_internal_links(doc),
        has_nav: doc.css('nav, [role="navigation"]').any?,
        word_count: doc.css("body").text.split.size,
        inbound_links_count: 0 # Will be calculated after all pages are crawled
      }
    end

    def extract_links(doc)
      links = []

      doc.css("a[href]").each do |link|
        href = link["href"]
        next if href.nil? || href.empty?
        next if href.start_with?("#", "javascript:", "mailto:", "tel:")

        absolute_url = to_absolute_url(href)
        next unless absolute_url
        next unless same_domain?(absolute_url)

        links << absolute_url
        break if links.size >= 50 # Limit per page
      end

      links.uniq
    end

    def to_absolute_url(href)
      uri = URI.parse(href)

      if uri.relative?
        base_uri = URI.parse(homepage_url)
        uri = base_uri + href
      end

      uri.to_s
    rescue URI::InvalidURIError
      nil
    end

    def same_domain?(url)
      URI.parse(url).host == @domain
    rescue URI::InvalidURIError
      false
    end

    def count_external_links(doc)
      doc.css("a[href]").count { |link| !same_domain?(link["href"].to_s) }
    end

    def count_internal_links(doc)
      doc.css("a[href]").count { |link| same_domain?(link["href"].to_s) }
    end

    def normalize_url(url)
      uri = URI.parse(url)
      uri.scheme ||= "https"
      uri.path = "/" if uri.path.empty?
      uri.to_s
    end
  end
end
