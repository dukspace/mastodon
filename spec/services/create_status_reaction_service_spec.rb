# frozen_string_literal: true

require 'rails_helper'

RSpec.describe CreateStatusReactionService do
  subject(:create_reaction) { described_class.new.call(reactor, status, name: '👍') }

  let(:reactor) { Fabricate(:account) }
  let(:status) { Fabricate(:status) }

  it 'creates a Like-compatible local reaction and fans it out' do
    reaction = create_reaction
    raw_job_payload = ActivityPub::RawDistributionWorker.jobs.sole['args'].first

    expect(reaction).to be_activity_type_like
    expect(JSON.parse(raw_job_payload)).to include(
      'type' => 'Like',
      'content' => '👍',
      '_misskey_reaction' => '👍'
    )
  end

  context 'when replacing an existing reaction' do
    before { described_class.new.call(reactor, status, name: '👎') }

    it 'fans out the old Undo before the new reaction' do
      create_reaction
      payload_types = ActivityPub::RawDistributionWorker.jobs.map { |job| JSON.parse(job['args'].first)['type'] }

      expect(payload_types.last(2)).to eq(%w(Undo Like))
      expect(StatusReaction.where(account: reactor, status: status).sole).to have_attributes(name: '👍')
    end
  end
end
