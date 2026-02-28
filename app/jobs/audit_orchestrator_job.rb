class AuditOrchestratorJob < ApplicationJob
  queue_as :default

  def perform(audit_id)
    audit = Audit.find(audit_id)

    Rails.logger.info "Starting audit orchestration for: #{audit.url} (mode: #{audit.audit_mode})"

    begin
      if audit.single_page_mode?
        run_single_page_audit(audit)
      else
        run_full_crawl_audit(audit)
      end

      audit.update(status: "complete")

      Rails.logger.info "✓ Audit complete: #{audit.url}"
    rescue => e
      Rails.logger.error "✗ Audit failed for #{audit.url}: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      audit.update(status: "failed")
      raise
    end
  end

  private

  def run_single_page_audit(audit)
    Rails.logger.info "Running single page audit for: #{audit.url}"

    # Create a single discovered page for the URL
    page = audit.discovered_pages.find_or_create_by(url: audit.url) do |p|
      p.page_type = "other"
      p.is_priority_page = true
      p.data_collection_status = "pending"
      p.testing_status = "pending"
    end

    # Phase 1: Collect comprehensive data
    audit.update(status: "collecting")
    collect_page_data(page)

    # Phase 2: Run all tests (queued as async jobs)
    audit.update(status: "testing")
    queued_count = run_page_tests(page)

    # Phase 3: Wait for all tests to complete
    wait_for_tests_completion(page, audit, queued_count)

    # Phase 4: Generate AI summary of results
    if queued_count > 0
      audit.update(current_phase: "synthesizing")
      generate_single_page_summary(audit, page)
    end
  end

  def run_full_crawl_audit(audit)
    Rails.logger.info "Running full crawl audit for: #{audit.url}"

    # Phase 1: Crawl website
    audit.update(status: "crawling", current_phase: "crawling")
    crawl_website(audit)

    # Phase 2: Prioritize pages with AI
    audit.update(current_phase: "prioritizing")
    prioritize_pages(audit)

    # Phase 3: Collect data for priority pages
    audit.update(status: "collecting", current_phase: "collecting")
    collect_priority_pages_data(audit)

    # Phase 4: Run tests on all pages
    audit.update(status: "testing", current_phase: "testing")
    test_priority_pages(audit)

    # Phase 5: Synthesize results
    audit.update(current_phase: "synthesizing")
    synthesize_results(audit)
  end

  def collect_page_data(page)
    Rails.logger.info "Collecting data for: #{page.url}"

    collector = PageDataCollector.new(page)
    collector.collect!
  rescue => e
    Rails.logger.error "✗ Data collection failed for #{page.url}: #{e.message}"
    page.update(data_collection_status: "failed")
    raise
  end

  def run_page_tests(page)
    Rails.logger.info "Running tests for: #{page.url}"

    runner = Tests::DynamicTestRunner.new(page)
    result = runner.run_all_tests!

    # Jobs are queued asynchronously, so we'll poll for completion
    # Wait briefly to let jobs start, then mark as complete
    # The actual completion will be checked by polling from frontend
    Rails.logger.info "✓ Test jobs queued for: #{page.url}"

    result[:queued] # Return the actual number of tests queued
  rescue => e
    Rails.logger.error "✗ Tests failed for #{page.url}: #{e.message}"
    page.update(testing_status: "failed")
    raise
  end

  def crawl_website(audit)
    Rails.logger.info "Crawling website: #{audit.url}"

    # Use existing crawler service
    crawler = AuditWorkflow::Crawler.new(audit)
    sitemap = crawler.crawl

    # Save discovered pages
    sitemap.each do |page_url|
      audit.discovered_pages.find_or_create_by(url: page_url) do |p|
        p.page_type = "other"
        p.is_priority_page = false
        p.data_collection_status = "pending"
        p.testing_status = "pending"
      end
    end

    audit.update(discovered_pages_count: audit.discovered_pages.count)
    Rails.logger.info "✓ Discovered #{audit.discovered_pages.count} pages"
  rescue => e
    Rails.logger.error "✗ Crawl failed: #{e.message}"
    raise
  end

  def prioritize_pages(audit)
    Rails.logger.info "Prioritizing pages with AI..."

    prioritizer = AuditWorkflow::AiPrioritizer.new(audit)
    priority_pages = prioritizer.identify_priority_pages

    # Mark priority pages
    priority_pages.each do |page_info|
      page = audit.discovered_pages.find_by(url: page_info[:url])
      next unless page

      page.update(
        is_priority_page: true,
        page_type: page_info[:page_type],
        priority_score: page_info[:priority_score]
      )
    end

    audit.update(priority_pages_count: audit.discovered_pages.where(is_priority_page: true).count)
    Rails.logger.info "✓ Identified #{audit.priority_pages_count} priority pages"
  rescue => e
    Rails.logger.error "✗ Prioritization failed: #{e.message}"
    raise
  end

  def collect_priority_pages_data(audit)
    priority_pages = audit.discovered_pages.where(is_priority_page: true)

    Rails.logger.info "Collecting data for #{priority_pages.count} priority pages..."

    priority_pages.each do |page|
      collect_page_data(page)
    end

    Rails.logger.info "✓ Data collection complete for all priority pages"
  end

  def test_priority_pages(audit)
    priority_pages = audit.discovered_pages.where(is_priority_page: true, data_collection_status: "complete")

    Rails.logger.info "Running tests on #{priority_pages.count} priority pages..."

    priority_pages.each do |page|
      run_page_tests(page)
    end

    Rails.logger.info "✓ Testing complete for all priority pages"
  end

  def synthesize_results(audit)
    Rails.logger.info "Synthesizing audit results..."

    # Calculate scores by category
    audit.calculate_overall_score!

    Rails.logger.info "✓ Results synthesized"
  end

  def wait_for_tests_completion(page, audit, expected_count)
    max_attempts = 120 # Wait up to 2 minutes
    attempts = 0
    last_count = 0

    loop do
      page.reload
      current_count = page.test_results.count

      # Log progress when count changes
      if current_count != last_count
        Rails.logger.info "Test progress: #{current_count}/#{expected_count} completed"
        last_count = current_count
      end

      if current_count >= expected_count
        Rails.logger.info "✓ All #{current_count} tests completed for #{page.url}"
        page.update(testing_status: "complete")
        audit.update(status: "complete", current_phase: "complete")
        break
      end

      attempts += 1
      if attempts >= max_attempts
        Rails.logger.warn "⚠ Timeout waiting for tests (#{current_count}/#{expected_count} completed)"
        page.update(testing_status: "complete")
        audit.update(status: "complete", current_phase: "complete")
        break
      end

      # Check more frequently when tests are running
      sleep(current_count > 0 ? 0.5 : 1)
    end
  end

  def generate_single_page_summary(audit, page)
    Rails.logger.info "Generating AI summary for audit..."

    test_results = page.test_results.includes(:test)
    passed_count = test_results.where(status: "passed").count
    failed_count = test_results.where(status: "failed").count
    warning_count = test_results.where(status: "warning").count

    # Build context for AI
    key_findings = []

    test_results.where(status: [ "failed", "warning" ]).each do |result|
      key_findings << "- #{result.test&.name || result.human_test_name}: #{result.summary&.truncate(150)}"
    end

    user_prompt = <<~PROMPT
      Generate a concise 2-3 sentence executive summary of this website audit.

      Results: #{passed_count} passed, #{warning_count} warnings, #{failed_count} failed

      Key issues found:
      #{key_findings.first(5).join("\n")}

      Focus on the most critical findings and actionable improvements.
    PROMPT

    messages = [
      { role: "system", content: "You are a concise website audit expert. Generate brief executive summaries." },
      { role: "user", content: user_prompt }
    ]

    summary = OpenaiService.chat(
      messages: messages,
      model: audit.ai_config["model"] || "claude-opus-4-6",
      temperature: audit.ai_config["temperature"] || 0.3,
      max_tokens: 500
    )

    if summary
      audit.update(ai_summary: summary)
      Rails.logger.info "✓ Generated AI summary"
    end
  rescue => e
    Rails.logger.error "Failed to generate summary: #{e.message}"
    # Non-critical, continue without summary
  end
end
