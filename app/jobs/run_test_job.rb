class RunTestJob < ApplicationJob
  queue_as :default

  def perform(discovered_page_id, test_key)
    discovered_page = DiscoveredPage.find(discovered_page_id)

    test_class = Tests::TestRegistry.get_test_class(test_key)
    return unless test_class

    Rails.logger.info "  Running test: #{test_key}"

    test_instance = test_class.new(discovered_page)
    test_instance.run!
  rescue => e
    Rails.logger.error "  ✗ Test #{test_key} failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Create a not_applicable result for failed tests
    TestResult.create!(
      discovered_page: discovered_page,
      audit: discovered_page.audit,
      test_key: test_key,
      test_category: "general",
      status: "not_applicable",
      summary: "Test failed: #{e.message}",
      details: { error: e.message }
    )
  end
end
