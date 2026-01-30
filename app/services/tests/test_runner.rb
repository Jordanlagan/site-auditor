module Tests
  class TestRunner
    attr_reader :discovered_page

    def initialize(discovered_page)
      @discovered_page = discovered_page
    end

    def run_all_tests!
      Rails.logger.info "Running all tests for page: #{discovered_page.url}"

      discovered_page.update(testing_status: "testing")

      # Queue all tests as individual jobs to run asynchronously
      Tests::TestRegistry.all_v1_tests.each do |test_key|
        RunTestJob.perform_later(discovered_page.id, test_key)
      end

      Rails.logger.info "✓ Queued #{Tests::TestRegistry.all_v1_tests.size} test jobs for page: #{discovered_page.url}"

      # Note: The orchestrator job will need to check for completion separately
      # since jobs run asynchronously
      {
        queued: Tests::TestRegistry.all_v1_tests.size
      }
    end

    def run_test(test_key)
      test_class = Tests::TestRegistry.get_test_class(test_key)
      return nil unless test_class

      Rails.logger.info "  Running test: #{test_key}"

      test_instance = test_class.new(discovered_page)
      test_instance.run!
    rescue => e
      Rails.logger.error "  ✗ Test #{test_key} failed: #{e.message}"
      raise
    end

    def run_category_tests(category)
      Rails.logger.info "Running #{category} tests for page: #{discovered_page.url}"

      test_keys = Tests::TestRegistry.tests_by_category(category)
      results = []

      test_keys.each do |test_key|
        begin
          result = run_test(test_key)
          results << result if result
        rescue => e
          Rails.logger.error "Test #{test_key} failed: #{e.message}"
        end
      end

      results
    end
  end
end
