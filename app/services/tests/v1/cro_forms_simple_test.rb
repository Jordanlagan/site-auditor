module Tests
  module V1
    class CroFormsSimpleTest < BaseTest
      def run!
        return not_applicable(summary: "No page data available") unless page_data&.html_content.present?

        doc = Nokogiri::HTML(page_data.html_content)
        forms = doc.css("form")

        if forms.empty?
          return not_applicable(summary: "No forms found on page")
        end

        form_data = forms.first(3).map do |form|
          inputs = form.css("input, select, textarea").reject { |i| i["type"] == "hidden" }
          {
            field_count: inputs.count,
            field_types: inputs.map { |i| i.name }.uniq
          }
        end

        max_fields = form_data.map { |f| f[:field_count] }.max

        if max_fields <= 5
          create_result(
            status: "passed",
            score: 100,
            summary: "Forms are simple with #{max_fields} fields or fewer.",
            details: { form_count: forms.count, max_fields: max_fields },
            priority: 2
          )
        elsif max_fields <= 10
          create_result(
            status: "warning",
            score: 70,
            summary: "Forms have #{max_fields} fields, which may be too many.",
            details: { form_count: forms.count, max_fields: max_fields },
            recommendation: "Consider reducing form fields to only essential information. Long forms decrease conversion rates.",
            priority: 2
          )
        else
          create_result(
            status: "failed",
            score: 40,
            summary: "Forms are too complex with #{max_fields} fields.",
            details: { form_count: forms.count, max_fields: max_fields },
            recommendation: "Simplify forms significantly. Consider multi-step forms or progressive disclosure. Ask only for essential information upfront.",
            priority: 2
          )
        end
      rescue => e
        Rails.logger.error "CroFormsSimpleTest failed: #{e.message}"
        not_applicable(summary: "Could not analyze forms")
      end

      protected

      def test_category
        "cro"
      end
    end
  end
end
