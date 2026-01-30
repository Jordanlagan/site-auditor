module Audits
  class BaseService
    attr_reader :url, :audit, :issues

    def initialize(url:, audit:)
      @url = url
      @audit = audit
      @issues = []
    end

    def perform
      raise NotImplementedError, "Subclasses must implement #perform"
    end

    def category
      raise NotImplementedError, "Subclasses must implement #category"
    end

    def calculate_score
      return 100 if issues.empty?
      
      # Scoring: start at 100, deduct points based on severity
      deductions = issues.sum do |issue|
        case issue[:severity]
        when 'high' then 20
        when 'medium' then 10
        when 'low' then 5
        else 0
        end
      end
      
      [100 - deductions, 0].max
    end

    def save_issues!
      issues.each do |issue_data|
        audit.audit_issues.create!(
          category: category,
          severity: issue_data[:severity],
          title: issue_data[:title],
          description: issue_data[:description],
          recommendation: issue_data[:recommendation]
        )
      end
    end

    private

    def add_issue(severity:, title:, description:, recommendation:)
      issues << {
        severity: severity,
        title: title,
        description: description,
        recommendation: recommendation
      }
    end
  end
end
