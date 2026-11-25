class Whatsapp::TypingIndicator
  pattr_initialize [:whatsapp_channel!]

  def perform(message_id)
    return if message_id.blank?

    response = HTTParty.post(messages_url, headers: api_headers, body: request_body(message_id).to_json)
    return if response.success?

    Rails.logger.warn("[WHATSAPP] typing indicator failed: #{response.code}")
  rescue StandardError => e
    Rails.logger.warn("[WHATSAPP] typing indicator failed: #{e.message}")
  end

  def perform_before_send(message)
    perform(latest_incoming_source_id(message))
  end

  private

  def latest_incoming_source_id(message)
    message.conversation.messages.incoming
           .where(account_id: message.conversation.account_id)
           .where.not(source_id: [nil, ''])
           .order(id: :desc)
           .pick(:source_id)
  end

  def request_body(message_id)
    {
      messaging_product: 'whatsapp',
      status: 'read',
      message_id: message_id,
      typing_indicator: { type: 'text' }
    }
  end

  def messages_url
    version = GlobalConfigService.load('WHATSAPP_API_VERSION', 'v22.0')
    base_url = ENV.fetch('WHATSAPP_CLOUD_BASE_URL', 'https://graph.facebook.com')
    "#{base_url}/#{version}/#{whatsapp_channel.provider_config['phone_number_id']}/messages"
  end

  def api_headers
    {
      'Authorization' => "Bearer #{whatsapp_channel.provider_config['api_key']}",
      'Content-Type' => 'application/json'
    }
  end
end
