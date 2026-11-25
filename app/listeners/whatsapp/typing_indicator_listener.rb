class Whatsapp::TypingIndicatorListener < BaseListener
  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless bot_should_type?(message)

    channel = message.inbox.channel
    Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel).send_typing_indicator(message.source_id)
    Whatsapp::RefreshTypingIndicatorJob.set(wait: Whatsapp::RefreshTypingIndicatorJob::INTERVAL)
                                       .perform_later(message.conversation_id, message.id, Time.current)
  end

  def conversation_typing_on(event)
    return if event.data[:is_private]

    conversation = event.data[:conversation]
    channel = whatsapp_cloud_channel(conversation.inbox)
    return if channel.blank?

    source_id = latest_incoming_source_id(conversation)
    return if source_id.blank?

    Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: channel).send_typing_indicator(source_id)
  end

  private

  def bot_should_type?(message)
    return false unless message.incoming?
    return false if message.source_id.blank?
    return false unless message.conversation.pending?
    return false unless message.inbox.active_bot?

    whatsapp_cloud_channel(message.inbox).present?
  end

  def whatsapp_cloud_channel(inbox)
    channel = inbox.channel
    return unless channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'

    channel
  end

  def latest_incoming_source_id(conversation)
    conversation.messages.incoming
                .where(account_id: conversation.account_id)
                .where.not(source_id: [nil, ''])
                .order(id: :desc)
                .pick(:source_id)
  end
end
