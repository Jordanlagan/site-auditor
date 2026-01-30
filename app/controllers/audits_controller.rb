class AuditsController < ApplicationController
  # DELETE /audits/:id
  def destroy
    audit = Audit.find(params[:id])
    audit.destroy

    head :no_content
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Audit not found" }, status: :not_found
  end

  # POST /audits
  def create
    audit = Audit.new(audit_params)

    if audit.save
      # Queue the new orchestrator job
      AuditOrchestratorJob.perform_later(audit.id)

      render json: {
        id: audit.id,
        url: audit.url,
        status: audit.status,
        audit_mode: audit.audit_mode,
        message: "Audit queued successfully"
      }, status: :created
    else
      render json: {
        errors: audit.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # GET /audits/:id/status
  def status
    audit = Audit.find(params[:id])

    render json: {
      id: audit.id,
      url: audit.url,
      status: audit.status,
      audit_mode: audit.audit_mode,
      current_phase: audit.current_phase,
      discovered_pages_count: audit.discovered_pages_count,
      priority_pages_count: audit.priority_pages_count,
      overall_score: audit.overall_score,
      tests_passed: audit.passed_tests_count,
      tests_failed: audit.failed_tests_count,
      tests_warning: audit.warning_tests_count,
      created_at: audit.created_at,
      updated_at: audit.updated_at
    }
  end

  # GET /audits/:id
  def show
    audit = Audit.find(params[:id])

    render json: format_audit_response(audit)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Audit not found" }, status: :not_found
  end

  # GET /audits
  def index
    audits = Audit.recent.limit(50)

    render json: {
      audits: audits.map do |audit|
        {
          id: audit.id,
          url: audit.url,
          status: audit.status,
          overall_score: audit.overall_score,
          created_at: audit.created_at,
          updated_at: audit.updated_at
        }
      end
    }
  end

  # GET /audits/:id/pages/:page_id
  def page_details
    audit = Audit.find(params[:id])
    page = audit.discovered_pages.find(params[:page_id])

    render json: format_page_response(page)
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Page not found" }, status: :not_found
  end

  private

  def audit_params
    params.require(:audit).permit(:url, :audit_mode, ai_config: [ :systemPrompt, :temperature, :model ])
  end

  def format_audit_response(audit)
    response = {
      id: audit.id,
      url: audit.url,
      status: audit.status,
      audit_mode: audit.audit_mode,
      current_phase: audit.current_phase,
      overall_score: audit.overall_score,
      category_scores: audit.category_scores,
      created_at: audit.created_at,
      updated_at: audit.updated_at,
      discovered_pages_count: audit.discovered_pages_count,
      priority_pages_count: audit.priority_pages_count
    }

    # For full_crawl mode, include all discovered pages
    if audit.full_crawl_mode?
      response[:all_pages] = audit.discovered_pages.includes(:page_data).map do |page|
        {
          id: page.id,
          url: page.url,
          page_type: page.page_type,
          is_priority_page: page.is_priority_page,
          data_collection_status: page.data_collection_status,
          testing_status: page.testing_status,
          priority_score: page.priority_score
        }
      end
    end

    # Include test results if complete
    if audit.complete?
      primary_page = audit.discovered_pages.first
      if primary_page
        response[:test_results] = format_test_results(primary_page)
        response[:pages] = [ {
          id: primary_page.id,
          url: primary_page.url,
          page_data: primary_page.page_data,
          screenshots: primary_page.page_data&.screenshots || {}
        } ]
      end
    end

    response
  end

  def format_page_response(page)
    {
      id: page.id,
      url: page.url,
      page_type: page.page_type,
      is_priority_page: page.is_priority_page,
      data_collection_status: page.data_collection_status,
      testing_status: page.testing_status,
      test_results: format_test_results(page),
      screenshots: page.page_data&.screenshots || {},
      page_data_summary: {
        images_count: page.page_data&.images&.size || 0,
        scripts_count: page.page_data&.scripts&.size || 0,
        page_weight_mb: page.page_data&.page_weight_mb || 0,
        meta_title: page.page_data&.meta_title,
        meta_description: page.page_data&.meta_description
      }
    }
  end

  def format_test_results(page)
    return {} unless page.test_results.any?

    results_by_category = {}

    Audit::CATEGORIES.each do |category|
      category_tests = page.test_results.where(test_category: category)
      next if category_tests.empty?

      results_by_category[category] = {
        tests: category_tests.map do |test|
          {
            test_key: test.test_key,
            test_name: test.human_test_name,
            status: test.status,
            score: test.score,
            summary: test.summary,
            details: test.details,
            recommendation: test.recommendation,
            priority: test.priority
          }
        end,
        passed: category_tests.passed.count,
        failed: category_tests.failed.count,
        warning: category_tests.warning.count
      }
    end

    results_by_category
  end
end
