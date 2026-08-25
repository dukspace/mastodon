# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::EmojiReact do
  subject(:perform) { described_class.new(json, sender).perform }

  let(:sender) { Fabricate(:account, domain: 'akkoma.example') }
  let(:recipient) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account: recipient) }
  let(:json) do
    {
      '@context': ['https://www.w3.org/ns/activitystreams', 'http://litepub.social/litepub/context.jsonld'],
      id: 'https://akkoma.example/activities/reaction-1',
      type: 'EmojiReact',
      actor: sender.uri,
      object: ActivityPub::TagManager.instance.uri_for(status),
      content: '👍',
    }.with_indifferent_access
  end

  it 'creates one reaction and learns the domain capability' do
    expect { perform }.to change(StatusReaction, :count).by(1)

    expect(StatusReaction.last).to have_attributes(name: '👍', activity_type: 'emoji_react')
    expect(ReactionDomainCapability.find('akkoma.example')).to be_supports_emoji_react
  end

  it 'is idempotent when the activity is delivered twice' do
    perform

    expect { described_class.new(json, sender).perform }.to_not change(StatusReaction, :count)
  end

  it 'replaces a previous reaction from the same account' do
    perform
    replacement = json.merge(id: 'https://akkoma.example/activities/reaction-2', content: '👎')

    described_class.new(replacement, sender).perform

    expect(StatusReaction.where(account: sender, status: status).sole).to have_attributes(name: '👎', activity_uri: replacement[:id])
  end

  context 'when the original status is remote' do
    let(:recipient) { Fabricate(:account, domain: 'author.example', protocol: :activitypub) }

    it 'stores the reaction without creating a notification' do
      expect { perform }
        .to change(StatusReaction, :count).by(1)
        .and not_change(Notification, :count)

      expect(StatusReaction.last).to have_attributes(status: status, account: sender, activity_uri: json[:id])
    end

    context 'when the status has restricted visibility' do
      let(:status) { Fabricate(:status, account: recipient, visibility: :direct) }

      it 'ignores a reaction from an account outside the status audience before parsing it' do
        expect(ActivityPub::Parser::ReactionParser).to_not receive(:new)

        expect { perform }.to_not change(StatusReaction, :count)
      end

      it 'accepts a reaction from an explicitly mentioned account' do
        Fabricate(:mention, status: status, account: sender)

        expect { perform }.to change(StatusReaction, :count).by(1)
      end
    end
  end
end
