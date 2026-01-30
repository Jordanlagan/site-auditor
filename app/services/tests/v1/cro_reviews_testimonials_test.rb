module Tests
  module V1
    class CroReviewsTestimonialsTest < BaseTest
      def run!
        return not_applicable(summary: "No page content available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        content = page_data.page_content&.downcase || ""

        # Check for review/testimonial indicators
        has_reviews = doc.css('[class*="review"], [class*="testimonial"], [class*="rating"]').any? ||
                     content.include?("review") ||
                     content.include?("testimonial") ||
                     content.include?("customer said") ||
                     page_data.structured_data&.any? { |sd| sd["@type"] == "Review" || sd["@type"] == "AggregateRating" }

        if has_reviews
          create_result(
            status: "passed",
            score: 100,
            summary: "Customer reviews or testimonials found on the page.",
            details: {},
            priority: 2
          )
        else
          create_result(
            status: "failed",
            score: 50,
            summary: "No customer reviews or testimonials detected.",
            details: {},
            recommendation: "Add customer reviews and testimonials to build trust. Social proof significantly improves conversion rates.",
            priority: 2
          )
        end
      rescue => e
        Rails.logger.error "CroReviewsTestimonialsTest failed: #{e.message}"
        not_applicable(summary: "Could not check for reviews")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
