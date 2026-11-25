require 'rails_helper'

describe Whatsapp::TypingIndicatorListener do
  let(:listener) { described_class.instance }
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:conversation) { create(:conversation, inbox: inbox, account: inbox.account, status: :pending) }
  let(:typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot, account: inbox.account))
    stub_request(:post, typing_url).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  describe '#message_created' do
    let(:message) do
      create(:message, conversation: conversation, inbox: inbox, account: inbox.account, message_type: :incoming, source_id: 'wamid.customer')
    end
    let(:event) { Events::Base.new('message.created', Time.zone.now, message: message) }

    it 'notifies Meta and schedules a refresh while the bot owns the conversation' do
      expect do
        listener.message_created(event)
      end.to have_enqueued_job(Whatsapp::RefreshTypingIndicatorJob).with(conversation.id, message.id, kind_of(Time))

      expect(a_request(:post, typing_url).with(body: hash_including('message_id' => 'wamid.customer'))).to have_been_made
    end

    it 'does nothing when an advisor already owns the open conversation' do
      conversation.open!
      listener.message_created(event)

      expect(a_request(:post, typing_url)).not_to have_been_made
    end
  end

  describe '#conversation_typing_on' do
    let(:user) { create(:user, account: inbox.account) }
    let(:event) { Events::Base.new('conversation.typing_on', Time.zone.now, conversation: conversation, user: user, is_private: false) }

    before do
      create(:message, conversation: conversation, inbox: inbox, account: inbox.account, message_type: :incoming, source_id: 'wamid.customer')
    end

    it 'notifies Meta when an advisor starts typing' do
      listener.conversation_typing_on(event)

      expect(a_request(:post, typing_url).with(body: hash_including('message_id' => 'wamid.customer'))).to have_been_made
    end

    it 'does not notify Meta for a private note' do
      private_event = Events::Base.new('conversation.typing_on', Time.zone.now, conversation: conversation, user: user, is_private: true)

      listener.conversation_typing_on(private_event)

      expect(a_request(:post, typing_url)).not_to have_been_made
    end
  end
end
