module Tests
  class DynamicTestRunner
    attr_reader :discovered_page, :audit

    def initialize(discovered_page)
      @discovered_page = discovered_page
      @audit = discovered_page.audit
    end

    # Run all active tests
    def run_all_tests!
      Rails.logger.info "Running all dynamic tests for page: #{discovered_page.url}"

      discovered_page.update(testing_status: "testing")

      # Check if audit has specific test_ids selected
      if audit.test_ids.present? && audit.test_ids.any?
        tests_to_run = Test.active.where(id: audit.test_ids).ordered
        Rails.logger.info "  Running #{tests_to_run.count} selected tests (from audit.test_ids)"
      elsif audit.test_ids == []
        # Empty array means: don't run any tests
        tests_to_run = Test.none
        Rails.logger.info "  Skipping all tests (test_ids is empty)"
      else
        tests_to_run = Test.active.ordered
        Rails.logger.info "  Running all #{tests_to_run.count} active tests"
      end

      # Queue all tests as individual jobs to run asynchronously
      tests_to_run.each do |test|
        RunTestJob.perform_later(discovered_page.id, test.test_key)
      end

      Rails.logger.info "✓ Queued #{tests_to_run.count} dynamic test jobs for page: #{discovered_page.url}"

      {
        queued: tests_to_run.count,
        test_keys: tests_to_run.pluck(:test_key)
      }
    end

    # Run a specific test by test_key
    def run_test(test_key)
      test = Test.active.find_by(test_key: test_key)

      unless test
        Rails.logger.error "Test not found: #{test_key}"
        return nil
      end

      Rails.logger.info "  Running dynamic test: #{test_key}"

      executor = DynamicTestExecutor.new(discovered_page, test)
      executor.execute!
    rescue => e
      Rails.logger.error "  ✗ Dynamic test #{test_key} failed: #{e.message}"
      raise
    end

    # Run tests for a specific group
    def run_group_tests(group_name)
      group = TestGroup.active.find_by(name: group_name)

      unless group
        Rails.logger.error "Test group not found: #{group_name}"
        return []
      end

      Rails.logger.info "Running #{group_name} tests for page: #{discovered_page.url}"

      tests = group.tests.active.ordered
      results = []

      tests.each do |test|
        begin
          result = run_test(test.test_key)
          results << result if result
        rescue => e
          Rails.logger.error "Test #{test.test_key} failed: #{e.message}"
        end
      end

      results
    end
  end
end
