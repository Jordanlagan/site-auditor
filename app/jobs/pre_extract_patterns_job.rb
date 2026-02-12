class PreExtractPatternsJob < ApplicationJob
  queue_as :default

  def perform(audit_id, inspiration_urls, config_hash)
    audit = Audit.find(audit_id)

    # Handle both string and symbol keys after job serialization
    config_hash = config_hash.deep_symbolize_keys if config_hash.respond_to?(:deep_symbolize_keys)

    Rails.logger.info "Pre-extracting design patterns for #{inspiration_urls.length} URLs"

    # Pre-extract design patterns for each unique inspiration URL (Phase 1)
    # This way we only call the AI once per URL instead of once per variation
    patterns_cache = {}
    inspiration_urls.uniq.each do |url|
      Rails.logger.info "Pre-extracting patterns from #{url}"

      # Crawl inspiration site
      crawler = InspirationCrawler.new(url)
      inspiration_data = crawler.crawl!

      if inspiration_data[:error]
        Rails.logger.error "Failed to crawl #{url}: #{inspiration_data[:error]}"
        next
      end

      # Extract patterns using cheaper Sonnet model
      generator = WireframeGenerator.new(audit, config_hash)
      patterns = generator.send(:extract_design_patterns, inspiration_data, use_sonnet: true)
      patterns_cache[url] = patterns if patterns
    end

    if patterns_cache.empty?
      Rails.logger.error "Failed to extract any design patterns"
      return
    end

    # Queue async jobs for each variation with pre-extracted patterns
    inspiration_urls.each_with_index do |url, index|
      next unless patterns_cache[url] # Skip if pattern extraction failed

      # Pass pre-extracted patterns in config
      job_config = config_hash.merge(
        inspiration_url: url,
        design_patterns: patterns_cache[url]
      )

      GenerateWireframeJob.perform_later(audit_id, url, job_config, index)
    end

    Rails.logger.info "✓ Queued #{patterns_cache.keys.length} wireframe generation jobs"
  rescue => e
    Rails.logger.error "Pattern pre-extraction failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
