module Tests
  module V1
    class SpeedNoBloatTest < BaseTest
      MAX_SCRIPTS = 30
      MAX_PAGE_WEIGHT_MB = 3

      def run!
        return not_applicable(summary: "No page data available") unless page_data

        script_count = page_data.scripts&.count || 0
        page_weight_mb = page_data.page_weight_mb || 0

        issues = []
        issues << "Too many scripts (#{script_count})" if script_count > MAX_SCRIPTS
        issues << "Page too large (#{page_weight_mb.round(1)}MB)" if page_weight_mb > MAX_PAGE_WEIGHT_MB

        if issues.empty?
          create_result(
            status: "passed",
            score: 100,
            summary: "Page is lean with #{script_count} scripts and #{page_weight_mb.round(1)}MB total weight.",
            details: { script_count: script_count, page_weight_mb: page_weight_mb },
            priority: 3
          )
        else
          create_result(
            status: "failed",
            score: 50,
            summary: "Page appears bloated: #{issues.join(', ')}.",
            details: { script_count: script_count, page_weight_mb: page_weight_mb, max_scripts: MAX_SCRIPTS, max_weight_mb: MAX_PAGE_WEIGHT_MB },
            recommendation: "Audit and remove unnecessary scripts/apps. Compress images and assets. Bloat hurts performance and conversion.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "SpeedNoBloatTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze page bloat")
      end

      protected

      def test_category
        "speed"
      end
    end
  end
end
