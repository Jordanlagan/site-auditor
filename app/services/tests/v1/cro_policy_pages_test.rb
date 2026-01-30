module Tests
  module V1
    class CroPolicyPagesTest < BaseTest
      POLICY_PAGES = [ "return", "shipping", "terms", "privacy", "refund" ]

      def run!
        return not_applicable(summary: "No page data available") unless page_data&.links.present?

        links = page_data.links.map { |l| l["href"]&.downcase || "" }
        content = page_data.page_content&.downcase || ""

        found_policies = POLICY_PAGES.select do |policy|
          links.any? { |link| link.include?(policy) } || content.include?(policy)
        end

        score = (found_policies.count.to_f / POLICY_PAGES.count * 100).round

        if found_policies.count >= 4
          create_result(
            status: "passed",
            score: 100,
            summary: "Most key policy pages found (#{found_policies.join(', ')}).",
            details: { found: found_policies, missing: POLICY_PAGES - found_policies },
            priority: 2
          )
        elsif found_policies.count >= 2
          create_result(
            status: "warning",
            score: score,
            summary: "Some policy pages found, but #{POLICY_PAGES.count - found_policies.count} are missing.",
            details: { found: found_policies, missing: POLICY_PAGES - found_policies },
            recommendation: "Add missing policy pages: #{(POLICY_PAGES - found_policies).join(', ')}. These build customer trust.",
            priority: 2
          )
        else
          create_result(
            status: "failed",
            score: score,
            summary: "Most policy pages are missing.",
            details: { found: found_policies, missing: POLICY_PAGES - found_policies },
            recommendation: "Add essential policy pages (return, shipping, terms, privacy). These are critical for customer trust and legal compliance.",
            priority: 2
          )
        end
      rescue => e
        Rails.logger.error "CroPolicyPagesTest failed: #{e.message}"
        not_applicable(summary: "Could not check for policy pages")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
