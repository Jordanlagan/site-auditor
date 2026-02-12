class WireframesController < ApplicationController
  before_action :set_audit, only: [ :index, :create ]
  before_action :set_wireframe, only: [ :show, :destroy ]

  # GET /audits/:audit_id/wireframes
  def index
    wireframes = @audit.wireframes.recent

    render json: {
      wireframes: wireframes.map do |wireframe|
        {
          id: wireframe.id,
          title: wireframe.title,
          url: wireframe.url,
          config_used: wireframe.config_used,
          created_at: wireframe.created_at
        }
      end,
      generating: @audit.ai_config&.dig("wireframes_generating") || false,
      expected_count: @audit.ai_config&.dig("wireframes_expected") || 0,
      generation_started_at: @audit.ai_config&.dig("wireframes_generated_at")
    }
  end

  # POST /audits/:audit_id/wireframes
  def create
    # Extract configuration from params and convert to plain Ruby structures
    config = {
      variations_count: params[:variations_count] || 1,
      primary_colors: (params[:primary_colors] || []).map { |c| c.to_unsafe_h.symbolize_keys },
      inspiration_urls: (params[:inspiration_urls] || []).map(&:to_s),
      custom_prompt: params[:custom_prompt]&.to_s,
      model: params[:model] || "claude-opus-4-6",
      temperature: params[:temperature] || 0.8
    }

    # Generate wireframes asynchronously
    generator = WireframeGenerator.new(@audit, config)
    result = generator.generate!

    if result[:error]
      render json: { error: result[:error] }, status: :unprocessable_entity
    else
      render json: {
        message: result[:message],
        queued: result[:queued]
      }, status: :accepted
    end
  rescue => e
    Rails.logger.error "Wireframe creation request failed: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    render json: { error: "Failed to start wireframe generation: #{e.message}" }, status: :internal_server_error
  end

  # GET /wireframes/:id
  def show
    render json: {
      id: @wireframe.id,
      title: @wireframe.title,
      url: @wireframe.url,
      html_content: @wireframe.html_content,
      config_used: @wireframe.config_used,
      created_at: @wireframe.created_at
    }
  end

  # DELETE /wireframes/:id
  def destroy
    @wireframe.destroy
    head :no_content
  rescue => e
    render json: { error: "Failed to delete wireframe: #{e.message}" }, status: :internal_server_error
  end

  private

  def set_audit
    @audit = Audit.find(params[:audit_id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Audit not found" }, status: :not_found
  end

  def set_wireframe
    @wireframe = Wireframe.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: "Wireframe not found" }, status: :not_found
  end
end
