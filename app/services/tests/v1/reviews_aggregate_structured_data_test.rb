module Tests
  module V1
    class ReviewsAggregateStructuredDataTest < BaseTest
      def run!
        return not_applicable(summary: "No structured data available") unless page_data&.structured_data.present?

        has_review_schema = page_data.structured_data.any? do |sd|
          sd["@type"] == "Review" ||
          sd["@type"] == "AggregateRating" ||
          sd.dig("aggregateRating", "@type") == "AggregateRating"
        end

        if has_review_schema
          create_result(
            status: "passed",
            score: 100,
            summary: "AggregateRating or Review structured data found.",
            details: { structured_data_types: page_data.structured_data.map { |sd| sd["@type"] }.uniq },
            priority: 3
          )
        else
          create_result(
            status: "failed",
            score: 40,
            summary: "No review structured data detected.",
            details: {},
            recommendation: "Add Review or AggregateRating schema markup to show star ratings in search results. This increases click-through rates.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "ReviewsAggregateStructuredDataTest failed: #{e.message}"
        not_applicable(summary: "Could not check structured data")
      end

      protected

      def test_category
        "reviews"
      end
    end
  end
end
