module Tests
  module V1
    class ReviewsAggregateRatingVisibleTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        content = page_data.page_content&.downcase || ""

        # Look for rating indicators
        has_visible_rating = doc.css('[class*="rating"], [class*="star"], [class*="review-score"]').any? ||
                            content.match?(/\d+(\.\d+)?\s*(stars?|out of 5|\/5)/)

        if has_visible_rating
          create_result(
            status: "passed",
            score: 100,
            summary: "Aggregate rating appears to be visible on the page.",
            details: {},
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 60,
            summary: "No visible aggregate rating detected.",
            details: {},
            recommendation: "If you have reviews, display an aggregate star rating prominently. This builds trust and social proof.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "ReviewsAggregateRatingVisibleTest failed: #{e.message}"
        not_applicable(summary: "Could not check for visible ratings")
      end

      protected

      def test_category
        "reviews"
      end
    end
  end
end
