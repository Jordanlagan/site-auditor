class WireframesController < ApplicationController
  before_action :set_audit, only: [ :index, :create, :stream ]
  before_action :set_wireframe, only: [ :show, :destroy, :regenerate ]
  
  include ActionController::Live

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
      generation_started_at: @audit.ai_config&.dig("wireframes_generated_at"),
      default_color_profile: @audit.ai_config&.dig("default_color_profile")
    }
  end

  # POST /audits/:audit_id/wireframes
  def create
    # Extract configuration from params and convert to plain Ruby structures
    config = {
      variations_count: params[:variations_count] || 1,
      primary_colors: (params[:primary_colors] || []).map { |c| c.to_unsafe_h.symbolize_keys },
      selected_images: (params[:selected_images] || []).map { |img| img.to_unsafe_h.symbolize_keys },
      inspiration_urls: (params[:inspiration_urls] || []).map(&:to_s),
      custom_prompt: params[:custom_prompt]&.to_s,
      model: params[:model] || "claude-opus-4-6",
      temperature: params[:temperature] || 0.8
    }

    # Save default color profile if requested
    if params[:save_as_default_colors] == true && config[:primary_colors].present?
      @audit.ai_config ||= {}
      @audit.ai_config["default_color_profile"] = config[:primary_colors]
      @audit.save!
    end

    # Save default image selection if requested
    if params[:save_as_default_images] == true && config[:selected_images].present?
      @audit.ai_config ||= {}
      @audit.ai_config["default_image_profile"] = config[:selected_images]
      @audit.save!
    end

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

  # POST /wireframes/:id/regenerate
  def regenerate
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    begin
      audit = @wireframe.audit

      config = {
        custom_prompt: params[:custom_prompt]&.to_s,
        css_selector: params[:css_selector]&.to_s.presence,
        primary_colors: (@wireframe.config_used&.dig("primary_colors") || []).map { |c| c.is_a?(Hash) ? c.symbolize_keys : c },
        selected_images: (@wireframe.config_used&.dig("selected_images") || []).map { |img| img.is_a?(Hash) ? img.symbolize_keys : img },
        model: params[:model] || @wireframe.config_used&.dig("model") || "claude-opus-4-6",
        temperature: params[:temperature] || @wireframe.config_used&.dig("temperature") || 0.8
      }

      generator = WireframeGenerator.new(audit, config)

      generator.regenerate_with_streaming!(@wireframe) do |chunk|
        begin
          response.stream.write("data: #{chunk.to_json}\n\n")
        rescue IOError, ActionController::Live::ClientDisconnected => e
          Rails.logger.warn "Client disconnected, stopping stream: #{e.message}"
          raise
        end
      end

      response.stream.write("data: {\"done\":true}\n\n")
    rescue ActionController::Live::ClientDisconnected => e
      Rails.logger.info "Client disconnected: #{e.message}"
    rescue IOError => e
      Rails.logger.warn "Stream IO error: #{e.message}"
    rescue => e
      Rails.logger.error "Regeneration streaming failed: #{e.message}"
      begin
        response.stream.write("data: #{({ error: e.message }).to_json}\n\n")
      rescue IOError, ActionController::Live::ClientDisconnected
      end
    ensure
      begin
        response.stream.close
      rescue IOError, ActionController::Live::ClientDisconnected
      end
    end
  end

  # POST /audits/:audit_id/wireframes/stream
  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"

    begin
      # Extract configuration from params
      config = {
        variations_count: 1, # Only support single wireframe for streaming
        primary_colors: (params[:primary_colors] || []).map { |c| c.to_unsafe_h.symbolize_keys },
        selected_images: (params[:selected_images] || []).map { |img| img.to_unsafe_h.symbolize_keys },
        inspiration_urls: (params[:inspiration_urls] || []).map(&:to_s).first(1),
        custom_prompt: params[:custom_prompt]&.to_s,
        model: params[:model] || "claude-opus-4-6",
        temperature: params[:temperature] || 0.8
      }

      # Save default color profile if requested
      if params[:save_as_default_colors] == true && config[:primary_colors].present?
        @audit.ai_config ||= {}
        @audit.ai_config["default_color_profile"] = config[:primary_colors]
        @audit.save!
      end

      # Save default image selection if requested
      if params[:save_as_default_images] == true && config[:selected_images].present?
        @audit.ai_config ||= {}
        @audit.ai_config["default_image_profile"] = config[:selected_images]
        @audit.save!
      end

      # Generate wireframe with streaming
      generator = WireframeGenerator.new(@audit, config)
      
      generator.generate_with_streaming! do |chunk|
        begin
          response.stream.write("data: #{chunk.to_json}\n\n")
        rescue IOError, ActionController::Live::ClientDisconnected => e
          Rails.logger.warn "Client disconnected, stopping stream: #{e.message}"
          raise # Re-raise to exit the generator block
        end
      end

      response.stream.write("data: {\"done\":true}\n\n")
    rescue ActionController::Live::ClientDisconnected => e
      Rails.logger.info "Client disconnected: #{e.message}"
      # Don't write to stream if client is gone
    rescue IOError => e
      Rails.logger.warn "Stream IO error: #{e.message}"
      # Don't write to stream if there's an IO error
    rescue => e
      Rails.logger.error "Streaming generation failed: #{e.message}"
      begin
        response.stream.write("data: #{({ error: e.message }).to_json}\n\n")
      rescue IOError, ActionController::Live::ClientDisconnected
        # Client already gone, can't send error
      end
    ensure
      begin
        response.stream.close
      rescue IOError, ActionController::Live::ClientDisconnected
        # Stream already closed
      end
    end
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
