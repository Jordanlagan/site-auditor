module Tests
  module V1
    class DesignVisualConsistencyTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        analyze_with_ai(
          "Does the site feel visually consistent across all elements?",
          {
            colors: page_data.colors&.first(15),
            fonts: page_data.fonts&.first(10),
            screenshots: page_data.screenshots,
            analysis_points: [
              "Is there a consistent color palette?",
              "Are fonts used consistently?",
              "Do UI elements have consistent styling?",
              "Is there a cohesive design system?"
            ]
          }
        )
      rescue => e
        Rails.logger.error "DesignVisualConsistencyTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze visual consistency")
      end

      protected

      def test_category
        "design"
      end
    end
  end
end
