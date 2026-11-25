require 'rails_helper'

describe Whatsapp::RefreshTypingIndicatorJob do
  let(:whatsapp_channel) do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
  end
  let(:inbox) { whatsapp_channel.inbox }
  let(:conversation) { create(:conversation, inbox: inbox, account: inbox.account, status: :pending) }
  let(:incoming) do
    create(:message, conversation: conversation, inbox: inbox, account: inbox.account, message_type: :incoming, source_id: 'wamid.customer')
  end
  let(:typing_url) { 'https://graph.facebook.com/v22.0/123456789/messages' }

  before do
    create(:agent_bot_inbox, inbox: inbox, agent_bot: create(:agent_bot, account: inbox.account))
    stub_request(:post, typing_url).to_return(status: 200, body: '{}', headers: { 'Content-Type' => 'application/json' })
  end

  it 'sends the indicator again and schedules another refresh while the bot is still waiting' do
    expect do
      described_class.perform_now(conversation.id, incoming.id, Time.current)
    end.to have_enqueued_job(described_class)

    expect(a_request(:post, typing_url).with(body: hash_including('message_id' => 'wamid.customer'))).to have_been_made
  end

  it 'stops after the AI has replied' do
    incoming
    create(:message, conversation: conversation, inbox: inbox, account: inbox.account, message_type: :outgoing, content: 'respuesta')

    expect do
      described_class.perform_now(conversation.id, incoming.id, Time.current)
    end.not_to have_enqueued_job(described_class)

    expect(a_request(:post, typing_url)).not_to have_been_made
  end

  it 'stops when the wait has lasted two minutes' do
    expect do
      described_class.perform_now(conversation.id, incoming.id, 3.minutes.ago)
    end.not_to have_enqueued_job(described_class)

    expect(a_request(:post, typing_url)).not_to have_been_made
  end
end
