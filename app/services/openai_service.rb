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
  end
end
