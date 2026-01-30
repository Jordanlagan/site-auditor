module Tests
  module V1
    class ReviewsThirdPartyBadgesTest < BaseTest
      TRUST_BADGES = [ "bbb", "trustpilot", "verisign", "mcafee", "norton", "google", "yelp", "verified" ]

      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        images = page_data.images || []
        content = page_data.page_content&.downcase || ""

        found_badges = TRUST_BADGES.select do |badge|
          images.any? { |img| img["src"]&.downcase&.include?(badge) || img["alt"]&.downcase&.include?(badge) } ||
          content.include?(badge)
        end

        if found_badges.any?
          create_result(
            status: "passed",
            score: 100,
            summary: "Third-party trust badges found: #{found_badges.join(', ')}.",
            details: { badges: found_badges },
            priority: 3
          )
        else
          create_result(
            status: "warning",
            score: 65,
            summary: "No third-party trust badges detected.",
            details: {},
            recommendation: "Consider displaying trust badges from BBB, Trustpilot, or other review platforms to build credibility.",
            priority: 3
          )
        end
      rescue => e
        Rails.logger.error "ReviewsThirdPartyBadgesTest failed: #{e.message}"
        not_applicable(summary: "Could not check for trust badges")
      end

      protected

      def test_category
        "reviews"
      end
    end
  end
end
