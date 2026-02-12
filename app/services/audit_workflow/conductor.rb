# frozen_string_literal: true

module AuditWorkflow
  class Conductor
    attr_reader :audit

    def initialize(audit)
      @audit = audit
    end

    def start
      audit.update!(
        workflow_state: "running",
        current_phase: "crawling"
      )

      # Phase 1: Light crawl
      crawl_and_discover

      # Phase 2: AI prioritization
      prioritize_pages

      # Phase 3: Begin guided analysis
      next_action
    end

    def next_action
      case audit.current_phase
      when "crawling"
        prioritize_pages
      when "prioritizing"
        generate_questions
      when "questioning"
        handle_questions_complete if all_questions_answered?
      when "analyzing"
        analyze_priority_pages
      when "synthesizing"
        synthesize_findings
      end
    end

    private

    def crawl_and_discover
      crawler = Crawler.new(audit.url, audit)
      pages = crawler.discover_pages(max_depth: 2, max_pages: 20)

      pages.each do |page_data|
        DiscoveredPage.create!(
          audit: audit,
          url: page_data[:url],
          page_type: page_data[:type],
          crawl_metadata: page_data[:metadata]
        )
      end

      # Calculate backlinks for prioritization
      crawler.calculate_backlinks

      audit.update!(
        discovered_pages_count: pages.size,
        current_phase: "prioritizing"
      )
    end

    def prioritize_pages
      prioritizer = AiPrioritizer.new(audit)
      prioritizer.score_pages

      priority_pages = audit.discovered_pages.high_priority

      audit.update!(
        priority_pages_count: priority_pages.count,
        current_phase: "questioning",
        ai_decisions: {
          prioritization_reasoning: prioritizer.reasoning,
          focus_pages: priority_pages.pluck(:url, :page_type, :priority_score)
        }
      )
    end

    def generate_questions
      generator = QuestionGenerator.new(audit)
      generator.create_contextual_questions

      audit.update!(current_phase: "questioning")
    end

    def all_questions_answered?
      audit.audit_questions.pending.none?
    end

    def handle_questions_complete
      audit.update!(
        questions_answered: audit.audit_questions.answered.count,
        current_phase: "analyzing"
      )

      analyze_priority_pages
    end

    def analyze_priority_pages
      # Always include homepage first, then top 4 by backlinks
      homepage = audit.discovered_pages.find_by(page_type: "homepage")
      other_pages = audit.discovered_pages.where.not(page_type: "homepage").top_by_backlinks(4)

      pages_to_analyze = [ homepage, *other_pages ].compact.uniq

      pages_to_analyze.each do |page|
        # Screenshots are captured by PageDataCollector during data collection phase

        # Run adaptive tests based on page context and user responses
        analyzer = AdaptiveAnalyzer.new(page)
        analyzer.run_contextual_tests

        page.update!(status: "complete")
      end

      audit.update!(current_phase: "synthesizing")
      synthesize_findings
    end

    def synthesize_findings
      synthesizer = ResultsSynthesizer.new(audit)
      synthesis = synthesizer.generate_report

      # Store insights in raw_results for easy access
      audit.update!(
        status: "complete",
        workflow_state: "complete",
        summary: synthesis[:summary],
        overall_score: synthesis[:score],
        raw_results: { page_insights: synthesis[:page_insights] }
      )
    end
  end
end
