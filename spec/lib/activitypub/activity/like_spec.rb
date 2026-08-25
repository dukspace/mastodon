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
      allow(Trends.statuses).to receive(:register)
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

      it 'does not register the reaction as a trending-status signal' do
        expect(Trends.statuses).to_not have_received(:register)
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

      it 'registers the plain Like as a trending-status signal' do
        expect(Trends.statuses).to have_received(:register).with(status)
      end
    end

    context 'when the original status is remote' do
      let(:recipient) { Fabricate(:account, domain: 'author.example', protocol: :activitypub) }

      context 'with a Misskey reaction' do
        let(:json) { super().merge(_misskey_reaction: '👍') }

        it 'stores only the reaction extension data' do
          reaction = StatusReaction.find_by(account: sender, status: status)

          expect(reaction).to have_attributes(name: '👍', activity_type: 'like', activity_uri: 'foo', favourite: nil)
          expect(status.favourites.where(account: sender)).to be_empty
          expect(Notification.where(from_account: sender)).to be_empty
          expect(Trends.statuses).to_not have_received(:register)
        end
      end

      context 'with a plain Like' do
        it 'does not mirror the third-party favourite' do
          expect(status.favourites.where(account: sender)).to be_empty
          expect(StatusReaction.where(account: sender, status: status)).to be_empty
          expect(Trends.statuses).to_not have_received(:register)
        end
      end

      context 'with invalid reaction content' do
        let(:json) { super().merge(content: '<b>not an emoji</b>') }

        it 'does not mirror the third-party activity' do
          expect(status.favourites.where(account: sender)).to be_empty
          expect(StatusReaction.where(account: sender, status: status)).to be_empty
        end
      end

      context 'when the status has restricted visibility' do
        let(:status) { Fabricate(:status, account: recipient, visibility: :direct) }
        let(:json) { super().merge(_misskey_reaction: '👍') }

        it 'ignores a reaction from an account outside the status audience' do
          expect(StatusReaction.where(account: sender, status: status)).to be_empty
        end

        context 'when the sender is explicitly mentioned' do
          before do
            Fabricate(:mention, status: status, account: sender)
            subject.perform
          end

          it 'accepts the reaction' do
            expect(StatusReaction.find_by(account: sender, status: status)).to have_attributes(name: '👍')
          end
        end
      end
    end
  end
end
