module Tests
  module V1
    class SpeedDeferredScriptsTest < BaseTest
      def run!
        return not_applicable(summary: "No script data available") unless page_data&.scripts.present?

        scripts = page_data.scripts
        external_scripts = scripts.select { |s| s["src"].present? }
        deferred_scripts = scripts.count { |s| s["async"] || s["defer"] }

        return not_applicable(summary: "No external scripts found") if external_scripts.empty?

        percentage = (deferred_scripts.to_f / external_scripts.count * 100).round

        if percentage >= 70
          create_result(
            status: "passed",
            score: 100,
            summary: "#{percentage}% of external scripts are deferred/async.",
            details: { deferred_count: deferred_scripts, total_external: external_scripts.count, percentage: percentage },
            priority: 3
          )
        elsif percentage >= 40
          create_result(
            status: "warning",
            score: 65,
            summary: "Only #{percentage}% of external scripts are deferred/async.",
            details: { deferred_count: deferred_scripts, total_external: external_scripts.count, percentage: percentage },
            recommendation: "Add defer or async attributes to non-critical third-party scripts to improve page load performance.",
            priority: 3
          )
        else
          create_result(
            status: "failed",
            score: 35,
            summary: "Only #{percentage}% of external scripts are deferred/async.",
            details: { deferred_count: deferred_scripts, total_external: external_scripts.count, percentage: percentage },
            recommendation: "Defer or async load third-party scripts (analytics, ads, etc.) to prevent blocking page rendering.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "SpeedDeferredScriptsTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze script loading")
      end

      protected

      def test_category
        "speed"
      end
    end
  end
end
