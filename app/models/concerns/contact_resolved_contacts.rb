module ContactResolvedContacts
  extend ActiveSupport::Concern

  # Messaging channels identify a person even when the provider does not
  # give an email, phone number, or external identifier. Widget and API
  # visitors stay out of the directory until they have one of those.
  MESSAGING_CHANNEL_TYPES = %w[
    Channel::FacebookPage
    Channel::Instagram
    Channel::Whatsapp
    Channel::Telegram
    Channel::Tiktok
    Channel::Line
    Channel::Sms
    Channel::TwilioSms
    Channel::TwitterProfile
  ].freeze

  class_methods do
    def resolved_contacts(use_crm_v2: false)
      return where(contact_type: 'lead') if use_crm_v2

      identified = where("contacts.email <> '' OR contacts.phone_number <> '' OR contacts.identifier <> ''")
      with_messaging_inbox = where(id: messaging_contact_ids)
      identified.or(with_messaging_inbox)
    end

    private

    def messaging_contact_ids
      ContactInbox.joins(:inbox).where(inboxes: { channel_type: MESSAGING_CHANNEL_TYPES }).select(:contact_id)
    end
  end
end
