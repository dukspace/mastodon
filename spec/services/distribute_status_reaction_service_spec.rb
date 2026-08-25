# frozen_string_literal: true

require 'rails_helper'

RSpec.describe DistributeStatusReactionService do
  subject(:distribute) { described_class.new.call(reaction, payload) }

  let(:reactor) { Fabricate(:account) }
  let(:author) { Fabricate(:account) }
  let(:status) { Fabricate(:status, account: author, visibility: visibility) }
  let(:reaction) { StatusReaction.create!(account: reactor, status: status, name: '👍') }
  let(:payload) { JSON.generate(type: 'Like', object: ActivityPub::TagManager.instance.uri_for(status)) }
  let(:visibility) { :public }

  def delivery_inboxes
    ActivityPub::DeliveryWorker.jobs.pluck('args').map { |args| args[2] }
  end

  context 'with a public status from a remote author' do
    let(:shared_inbox) { 'https://author.example/inbox' }
    let(:author) do
      Fabricate(
        :account,
        domain: 'author.example',
        protocol: :activitypub,
        inbox_url: 'https://author.example/users/author/inbox',
        shared_inbox_url: shared_inbox
      )
    end

    before do
      remote_follower = Fabricate(:account, domain: 'author.example', protocol: :activitypub, inbox_url: 'https://author.example/users/follower/inbox', shared_inbox_url: shared_inbox)
      Fabricate(:follow, account: remote_follower, target_account: reactor)
      distribute
    end

    it 'delivers directly to the author and fans out to reactor followers without duplicating the author inbox' do
      expect(delivery_inboxes).to contain_exactly(shared_inbox)
      expect(ActivityPub::RawDistributionWorker)
        .to have_enqueued_sidekiq_job(payload, reactor.id, [shared_inbox])
    end
  end

  context 'with a public status from a local author' do
    before { distribute }

    it 'only fans out to reactor followers' do
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job
      expect(ActivityPub::RawDistributionWorker)
        .to have_enqueued_sidekiq_job(payload, reactor.id, [])
    end
  end

  context 'with an unlisted status' do
    let(:visibility) { :unlisted }

    before { distribute }

    it 'uses reactor follower fan-out without relay-specific delivery' do
      expect(ActivityPub::RawDistributionWorker)
        .to have_enqueued_sidekiq_job(payload, reactor.id, [])
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job
    end
  end

  context 'with a private status from a local author' do
    let(:visibility) { :private }
    let(:shared_inbox) { 'https://audience.example/inbox' }
    let(:remote_follower) do
      Fabricate(:account, domain: 'audience.example', protocol: :activitypub, inbox_url: 'https://audience.example/users/follower/inbox', shared_inbox_url: shared_inbox)
    end
    let(:remote_mention) do
      Fabricate(:account, domain: 'audience.example', protocol: :activitypub, inbox_url: 'https://audience.example/users/mention/inbox', shared_inbox_url: shared_inbox)
    end
    let(:late_follower) do
      Fabricate(:account, domain: 'late.example', protocol: :activitypub, inbox_url: 'https://late.example/users/follower/inbox', shared_inbox_url: 'https://late.example/inbox')
    end

    before do
      Fabricate(:follow, account: remote_follower, target_account: author)
      Fabricate(:mention, account: remote_mention, status: status)
      Fabricate(:follow, account: late_follower, target_account: author, created_at: status.created_at + 1.second)
      distribute
    end

    it 'delivers to the audience that existed when the status was created with shared inbox de-duplication' do
      expect(delivery_inboxes).to contain_exactly(shared_inbox)
      expect(ActivityPub::RawDistributionWorker).to_not have_enqueued_sidekiq_job
    end
  end

  context 'with a private status from a remote author' do
    let(:visibility) { :private }
    let(:author) { Fabricate(:account, domain: 'author.example', protocol: :activitypub, inbox_url: 'https://author.example/inbox') }
    let(:mentioned_account) { Fabricate(:account, domain: 'mentioned.example', protocol: :activitypub, inbox_url: 'https://mentioned.example/inbox') }

    before do
      Fabricate(:mention, account: mentioned_account, status: status)
      distribute
    end

    it 'delivers only to the known status audience' do
      expect(delivery_inboxes).to contain_exactly(author.inbox_url, mentioned_account.inbox_url)
      expect(ActivityPub::RawDistributionWorker).to_not have_enqueued_sidekiq_job
    end
  end

  %i(direct limited).each do |restricted_visibility|
    context "with a #{restricted_visibility} status" do
      let(:visibility) { restricted_visibility }
      let(:author) { Fabricate(:account, domain: 'author.example', protocol: :activitypub, inbox_url: 'https://author.example/inbox') }
      let(:mentioned_account) { Fabricate(:account, domain: 'mentioned.example', protocol: :activitypub, inbox_url: 'https://mentioned.example/inbox') }

      before do
        Fabricate(:mention, account: mentioned_account, status: status)
        distribute
      end

      it 'delivers to the author and active mentions without follower fan-out' do
        expect(delivery_inboxes).to contain_exactly(author.inbox_url, mentioned_account.inbox_url)
        expect(ActivityPub::RawDistributionWorker).to_not have_enqueued_sidekiq_job
      end
    end
  end

  context 'when the reacting account is remote' do
    let(:reactor) { Fabricate(:account, domain: 'reactor.example', protocol: :activitypub) }

    before { distribute }

    it 'does not relay the incoming reaction' do
      expect(ActivityPub::DeliveryWorker).to_not have_enqueued_sidekiq_job
      expect(ActivityPub::RawDistributionWorker).to_not have_enqueued_sidekiq_job
    end
  end
end
