# frozen_string_literal: true

require 'rails_helper'

RSpec.describe RemoveStatusReactionService do
  subject(:remove_reaction) { described_class.new.call(reactor, status, reaction: reaction) }

  let(:reactor) { Fabricate(:account) }
  let(:status) { Fabricate(:status) }
  let!(:reaction) { StatusReaction.create!(account: reactor, status: status, name: '👍', activity_type: :like) }

  it 'fans out the Undo and removes the reaction' do
    remove_reaction
    payload = JSON.parse(ActivityPub::RawDistributionWorker.jobs.sole['args'].first)

    expect(payload['type']).to eq('Undo')
    expect(payload).to include(
      'to' => [ActivityPub::TagManager::COLLECTIONS[:public]],
      'cc' => contain_exactly(
        ActivityPub::TagManager.instance.followers_uri_for(reactor),
        ActivityPub::TagManager.instance.uri_for(status.account)
      )
    )
    expect(StatusReaction.exists?(reaction.id)).to be(false)
  end

  context 'with a remote status and a preserved favourite' do
    let(:author) { Fabricate(:account, domain: 'author.example', protocol: :activitypub, inbox_url: 'https://author.example/inbox') }
    let(:status) { Fabricate(:status, account: author) }
    let!(:favourite) { Fabricate(:favourite, account: reactor, status: status) }

    it 'restores the ordinary Favourite only to the remote author' do
      remove_reaction
      direct_payloads = ActivityPub::DeliveryWorker.jobs.pluck('args').map { |args| JSON.parse(args[0]) }

      expect(direct_payloads.pluck('type')).to contain_exactly('Undo', 'Like')
      expect(ActivityPub::DeliveryWorker.jobs.pluck('args').pluck(2)).to all(eq(author.inbox_url))
      expect(favourite.reload).to be_persisted
    end
  end
end
