# frozen_string_literal: true

class OpenaiService
  class << self
    def client
      @client ||= OpenAI::Client.new(
        access_token: ENV.fetch("OPENAI_API_KEY", Rails.application.credentials.dig(:openai, :api_key)),
        log_errors: true
      )
    end

    def chat(messages:, model: "gpt-4o-mini", temperature: 0.7, max_tokens: 1500)
      response = client.chat(
        parameters: {
          model: model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        }
      )

      response.dig("choices", 0, "message", "content")
    rescue StandardError => e
      Rails.logger.error("OpenAI API Error: #{e.message}")
      nil
    end

    def analyze_with_json(system_prompt:, user_prompt:, model: "gpt-4o-mini")
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt }
      ]

      response = client.chat(
        parameters: {
          model: model,
          messages: messages,
          temperature: 0.3, # Lower for more consistent JSON
          response_format: { type: "json_object" }
        }
      )

      content = response.dig("choices", 0, "message", "content")
      JSON.parse(content) if content
    rescue JSON::ParserError => e
      Rails.logger.error("Failed to parse OpenAI JSON response: #{e.message}")
      nil
    rescue StandardError => e
      Rails.logger.error("OpenAI API Error: #{e.message}")
      nil
    end
  end
end
