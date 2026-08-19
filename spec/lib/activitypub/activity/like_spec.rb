# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::Like do
  let(:sender)    { Fabricate(:account) }
  let(:recipient) { Fabricate(:account) }
  let(:status)    { Fabricate(:status, account: recipient) }

  let(:json) do
    {
      '@context': 'https://www.w3.org/ns/activitystreams',
      id: 'foo',
      type: 'Like',
      actor: ActivityPub::TagManager.instance.uri_for(sender),
      object: ActivityPub::TagManager.instance.uri_for(status),
    }.with_indifferent_access
  end

  describe '#perform' do
    subject { described_class.new(json, sender) }

    before do
      subject.perform
    end

    it 'creates a favourite from sender to status' do
      expect(sender.favourited?(status)).to be true
    end

    context 'with a Misskey reaction' do
      let(:sender) { Fabricate(:account, domain: 'misskey.example') }
      let(:json) { super().merge(_misskey_reaction: '👍', content: '👎') }

      it 'stores the preferred Misskey reaction and links it to the favourite' do
        reaction = StatusReaction.find_by(account: sender, status: status)

        expect(reaction).to have_attributes(name: '👍', activity_type: 'like', activity_uri: 'foo')
        expect(reaction.favourite).to eq(status.favourites.find_by(account: sender))
      end
    end

    context 'with a content fallback reaction' do
      let(:json) { super().merge(content: '👍') }

      it 'stores the reaction' do
        expect(StatusReaction.find_by(account: sender, status: status)).to have_attributes(name: '👍')
      end
    end

    context 'with invalid reaction content' do
      let(:json) { super().merge(content: '<b>not an emoji</b>') }

      it 'keeps plain Like behavior' do
        expect(sender.favourited?(status)).to be true
        expect(StatusReaction.find_by(account: sender, status: status)).to be_nil
      end
    end
  end
end
