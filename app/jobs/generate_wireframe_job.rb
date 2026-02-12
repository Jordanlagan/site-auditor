class GenerateWireframeJob < ApplicationJob
  queue_as :default

  def perform(audit_id, inspiration_url, config_hash, index)
    audit = Audit.find(audit_id)

    # Handle both string and symbol keys after job serialization
    config_hash = config_hash.deep_symbolize_keys if config_hash.respond_to?(:deep_symbolize_keys)

    Rails.logger.info "Starting wireframe generation #{index + 1} for audit #{audit_id} with inspiration: #{inspiration_url}"

    # Use pre-extracted patterns if available, otherwise crawl the site
    if config_hash[:design_patterns]
      Rails.logger.info "Using pre-extracted design patterns"
      # Don't need to crawl or extract patterns - they're already in config
    else
      # Legacy path: crawl inspiration site if patterns not pre-extracted
      Rails.logger.info "Crawling inspiration site (no pre-extracted patterns)"
      inspiration_data = InspirationCrawler.new(inspiration_url).crawl!
      config_hash = config_hash.merge(inspiration_data: inspiration_data)
    end

    # Generate wireframe
    generator = WireframeGenerator.new(audit, config_hash.merge(
      variation_index: index
    ))

    wireframe = generator.generate_single!

    if wireframe
      Rails.logger.info "✓ Wireframe #{index + 1} generated successfully: #{wireframe.title}"

      # Check if all wireframes are done and clear generation flag
      audit.reload
      expected = audit.ai_config&.dig("wireframes_expected") || 0
      generated = audit.wireframes.where("created_at >= ?", audit.ai_config&.dig("wireframes_generated_at") || 1.hour.ago).count

      if generated >= expected
        Rails.logger.info "All #{expected} wireframes generated, clearing generation flag"
        audit.ai_config["wireframes_generating"] = false
        audit.save!
      end
    else
      Rails.logger.error "✗ Wireframe #{index + 1} generation returned nil"
    end
  rescue => e
    Rails.logger.error "Wireframe generation failed for #{inspiration_url}: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
  end
end
