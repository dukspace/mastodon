# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ReactionDomainCapability do
  it 'defaults unknown domains to Like reactions' do
    expect(described_class.preferred_for('unknown.example')).to eq(:like)
  end

  it 'prefers EmojiReact after observing it without forgetting Like support' do
    described_class.observe!('Mixed.Example', :like)
    described_class.observe!('mixed.example', :emoji_react)

    capability = described_class.find('mixed.example')
    expect(capability).to be_supports_like_reactions
    expect(capability).to be_supports_emoji_react
    expect(described_class.preferred_for('mixed.example')).to eq(:emoji_react)
  end
end
