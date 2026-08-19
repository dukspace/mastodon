# frozen_string_literal: true

require 'rails_helper'

RSpec.describe StatusReaction do
  describe '.summaries_for' do
    let(:status) { Fabricate(:status) }
    let(:viewer) { Fabricate(:account) }

    before do
      described_class.create!(status: status, account: viewer, name: '👍')
      described_class.create!(status: status, account: Fabricate(:account), name: '👍')
      described_class.create!(status: status, account: Fabricate(:account), name: '👎')
    end

    it 'groups by reaction and annotates the viewer selection' do
      summaries = described_class.summaries_for([status.id], viewer).fetch(status.id)

      expect(summaries.map { |reaction| [reaction.name, reaction.count.to_i, reaction.me] })
        .to eq([['👍', 2, true], ['👎', 1, false]])
    end
  end
end
