module Tests
  module V1
    class SpeedPageSpeedScoreTest < BaseTest
      def run!
        return not_applicable(summary: "No performance data available") unless page_data&.performance_metrics.present?

        metrics = page_data.performance_metrics

        # Use available metrics as proxy for performance
        load_time = metrics["load_complete"] || metrics["dom_content_loaded"]

        if load_time.nil?
          return not_applicable(summary: "Could not measure page load time")
        end

        # Convert to seconds
        load_seconds = load_time / 1000.0

        if load_seconds < 2.5
          create_result(
            status: "passed",
            score: 100,
            summary: "Page loads quickly in #{load_seconds.round(2)}s.",
            details: { load_time_ms: load_time, metrics: metrics },
            priority: 2
          )
        elsif load_seconds < 4
          create_result(
            status: "warning",
            score: 70,
            summary: "Page load time is #{load_seconds.round(2)}s (acceptable but could be improved).",
            details: { load_time_ms: load_time, metrics: metrics },
            recommendation: "Optimize images, minify assets, and enable caching to improve load times.",
            priority: 2
          )
        else
          create_result(
            status: "failed",
            score: 40,
            summary: "Page load time is slow at #{load_seconds.round(2)}s.",
            details: { load_time_ms: load_time, metrics: metrics },
            recommendation: "Critical performance issues detected. Use PageSpeed Insights for detailed analysis and fix major bottlenecks.",
            priority: 2
          )
        end
      rescue => e
        Rails.logger.error "SpeedPageSpeedScoreTest failed: #{e.message}"
        not_applicable(summary: "Could not measure page speed")
      end

      protected

      def test_category
        "speed"
      end
    end
  end
end
