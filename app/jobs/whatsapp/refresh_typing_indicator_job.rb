class Whatsapp::RefreshTypingIndicatorJob < ApplicationJob
  queue_as :low

  INTERVAL = 20.seconds
  MAX_DURATION = 2.minutes

  def perform(conversation_id, incoming_message_id, started_at)
    conversation = Conversation.find_by(id: conversation_id)
    incoming = Message.find_by(id: incoming_message_id)
    return if conversation.blank? || incoming.blank?
    return unless waiting_for_bot?(conversation, incoming)
    return if expired?(started_at)

    Whatsapp::Providers::WhatsappCloudService.new(whatsapp_channel: conversation.inbox.channel)
                                             .send_typing_indicator(incoming.source_id)

    return if started_at + MAX_DURATION <= Time.current + INTERVAL

    self.class.set(wait: INTERVAL).perform_later(conversation_id, incoming_message_id, started_at)
  end

  private

  def waiting_for_bot?(conversation, incoming)
    return false unless conversation.pending?
    return false unless conversation.inbox.active_bot?
    return false if conversation.messages.outgoing.where(account_id: conversation.account_id).exists?(['id > ?', incoming.id])

    channel = conversation.inbox.channel
    channel.is_a?(Channel::Whatsapp) && channel.provider == 'whatsapp_cloud'
  end

  def expired?(started_at)
    Time.current >= started_at + MAX_DURATION
  end
end
