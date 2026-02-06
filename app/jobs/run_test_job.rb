class RunTestJob < ApplicationJob
  queue_as :default

  def perform(discovered_page_id, test_key)
    discovered_page = DiscoveredPage.find(discovered_page_id)

    # Use dynamic test runner
    runner = Tests::DynamicTestRunner.new(discovered_page)
    runner.run_test(test_key)
  rescue => e
    Rails.logger.error "  ✗ Test #{test_key} failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    # Create a not_applicable result for failed tests
    test = Test.find_by(test_key: test_key)
    test_category = test&.test_group&.name&.downcase&.gsub(/\s+/, "_") || "general"

    TestResult.create!(
      discovered_page: discovered_page,
      audit: discovered_page.audit,
      test_key: test_key,
      test_category: test_category,
      status: "not_applicable",
      summary: "Test failed: #{e.message}"
    )
  end
end
