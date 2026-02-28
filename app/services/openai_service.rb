# frozen_string_literal: true

class OpenaiService
  class << self
    def client(provider: "claude")
      case provider
      when "claude"
        claude_client
      when "openai"
        openai_client
      else
        claude_client # Default to Claude
      end
    end

    def claude_client
      @claude_client ||= Anthropic::Client.new(
        api_key: ENV.fetch("ANTHROPIC_API_KEY", Rails.application.credentials.dig(:anthropic, :api_key))
      )
    end

    def openai_client
      @openai_client ||= OpenAI::Client.new(
        access_token: ENV.fetch("OPENAI_API_KEY", Rails.application.credentials.dig(:openai, :api_key)),
        log_errors: true
      )
    end

    # Use official model aliases from Anthropic docs: claude-opus-4-6, claude-sonnet-4-5
    def chat(messages:, model: "claude-opus-4-6", temperature: 0.7, max_tokens: 1500)
      provider = model.start_with?("claude") ? "claude" : "openai"

      if provider == "claude"
        # Extract system message if present (Claude requires it as a separate parameter)
        system_message = messages.find { |m| m[:role] == "system" || m["role"] == "system" }
        user_messages = messages.reject { |m| m[:role] == "system" || m["role"] == "system" }

        params = {
          model: model,
          messages: user_messages,
          temperature: temperature,
          max_tokens: max_tokens
        }
        params[:system] = system_message[:content] || system_message["content"] if system_message

        Rails.logger.info "📞 Calling Claude API with model: #{model}, max_tokens: #{max_tokens} at #{Time.current}"
        start_time = Time.current
        response = claude_client.messages.create(**params)
        elapsed = Time.current - start_time
        result = response.content[0].text
        Rails.logger.info "✅ Claude API returned #{result&.length || 0} characters in #{elapsed.round(2)}s"
        result
      else
        response = openai_client.chat(
          parameters: {
            model: model,
            messages: messages,
            temperature: temperature,
            max_tokens: max_tokens
          }
        )
        response.dig("choices", 0, "message", "content")
      end
    rescue StandardError => e
      Rails.logger.error("AI API Error: #{e.class.name} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
      nil
    end

    # Claude Vision API: send images (as base64 or URLs) alongside text for analysis
    # image_paths: array of local file paths (e.g. ["/screenshots/1_desktop_123.png"])
    # These are relative to Rails.root/public and will be base64-encoded for the API.
    def chat_with_images(messages:, image_paths:, model: "claude-opus-4-6", temperature: 0.3, max_tokens: 2000)
      # Extract system message
      system_message = messages.find { |m| m[:role] == "system" || m["role"] == "system" }
      user_messages = messages.reject { |m| m[:role] == "system" || m["role"] == "system" }

      # Build content blocks: text + images
      content_blocks = []

      # Add each image as a base64-encoded image block
      image_paths.each do |relative_path|
        filepath = Rails.root.join("public", relative_path.sub(%r{^/}, ""))
        unless File.exist?(filepath)
          Rails.logger.warn "Screenshot not found: #{filepath}"
          next
        end

        # Compress image if it exceeds Claude's 5MB base64 limit (~3.75MB raw file)
        compressed_path = compress_image_for_api(filepath)
        image_data = Base64.strict_encode64(File.binread(compressed_path))

        # Use JPEG for compressed images (always JPEG after compression)
        media_type = compressed_path.to_s.end_with?(".png") ? "image/png" : "image/jpeg"
        # If we compressed, it's always JPEG now
        media_type = "image/jpeg" if compressed_path != filepath

        content_blocks << {
          type: "image",
          source: {
            type: "base64",
            media_type: media_type,
            data: image_data
          }
        }

        raw_kb = (File.size(filepath) / 1024.0).round
        final_kb = (image_data.length * 0.75 / 1024).round
        Rails.logger.info "📸 Attached screenshot: #{relative_path} (#{raw_kb}KB raw → #{final_kb}KB base64#{compressed_path != filepath ? ', compressed' : ''})"

        # Clean up temp file
        File.delete(compressed_path) if compressed_path != filepath && File.exist?(compressed_path)
      end

      # Add text content from the last user message
      last_user_msg = user_messages.last
      text_content = last_user_msg[:content] || last_user_msg["content"]
      content_blocks << { type: "text", text: text_content }

      # Replace the last user message with the multi-modal content
      vision_messages = user_messages[0...-1] + [{ role: "user", content: content_blocks }]

      params = {
        model: model,
        messages: vision_messages,
        temperature: temperature,
        max_tokens: max_tokens
      }
      params[:system] = system_message[:content] || system_message["content"] if system_message

      Rails.logger.info "📞 Calling Claude Vision API with model: #{model}, #{image_paths.length} image(s), max_tokens: #{max_tokens}"
      start_time = Time.current
      response = claude_client.messages.create(**params)
      elapsed = Time.current - start_time
      result = response.content[0].text
      Rails.logger.info "✅ Claude Vision returned #{result&.length || 0} characters in #{elapsed.round(2)}s"
      result
    rescue StandardError => e
      Rails.logger.error("Claude Vision API Error: #{e.class.name} - #{e.message}")
      Rails.logger.error(e.backtrace.first(5).join("\n")) if e.backtrace
      nil
    end

    # Use official model aliases from Anthropic docs: claude-opus-4-6, claude-sonnet-4-5
    def analyze_with_json(system_prompt:, user_prompt:, model: "claude-opus-4-6")
      provider = model.start_with?("claude") ? "claude" : "openai"

      if provider == "claude"
        response = claude_client.messages.create(
          model: model,
          system: system_prompt,
          messages: [ { role: "user", content: user_prompt } ],
          temperature: 0.3
        )
        content = response.content[0].text
      else
        messages = [
          { role: "system", content: system_prompt },
          { role: "user", content: user_prompt }
        ]

        response = openai_client.chat(
          parameters: {
            model: model,
            messages: messages,
            temperature: 0.3,
            response_format: { type: "json_object" }
          }
        )
        content = response.dig("choices", 0, "message", "content")
      end

      JSON.parse(content) if content
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse AI JSON response: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("AI API Error: #{e.message}")
      nil
    end

    # Compress an image to fit within Claude's 5MB base64 limit.
    # Base64 inflates size by ~33%, so raw file must be under ~3.75MB.
    # Converts PNG→JPEG and progressively reduces quality/dimensions.
    MAX_API_FILE_BYTES = 3_500_000 # ~4.67MB base64, well under 5MB limit

    def compress_image_for_api(filepath)
      file_size = File.size(filepath)
      return filepath if file_size <= MAX_API_FILE_BYTES

      Rails.logger.info "🗜️ Compressing #{File.basename(filepath)} (#{(file_size / 1024.0 / 1024).round(2)}MB) for Vision API..."

      image = MiniMagick::Image.open(filepath.to_s)
      temp_path = Rails.root.join("tmp", "compressed_#{SecureRandom.hex(6)}.jpg")

      # Step 1: Convert to JPEG at quality 85 (PNG→JPEG often cuts size 3-5x)
      image.format "jpg"
      image.quality 85
      image.write temp_path.to_s

      # Step 2: If still too large, resize down progressively
      if File.size(temp_path) > MAX_API_FILE_BYTES
        image = MiniMagick::Image.open(temp_path.to_s)
        image.resize "1920x1920>"  # Cap at 1920px on longest side
        image.quality 80
        image.write temp_path.to_s
      end

      # Step 3: If STILL too large, go more aggressive
      if File.size(temp_path) > MAX_API_FILE_BYTES
        image = MiniMagick::Image.open(temp_path.to_s)
        image.resize "1280x1280>"
        image.quality 70
        image.write temp_path.to_s
      end

      final_size = File.size(temp_path)
      Rails.logger.info "🗜️ Compressed to #{(final_size / 1024.0 / 1024).round(2)}MB (#{((1 - final_size.to_f / file_size) * 100).round(1)}% reduction)"

      temp_path
    rescue => e
      Rails.logger.warn "Image compression failed: #{e.message}, using original"
      filepath
    end
  end
end
