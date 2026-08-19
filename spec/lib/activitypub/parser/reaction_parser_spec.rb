# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Parser::ReactionParser do
  let(:account) { Fabricate(:account, domain: 'remote.example') }

  def parse(json)
    described_class.new(json.with_indifferent_access, account).parse
  end

  it 'prefers _misskey_reaction over content' do
    expect(parse(_misskey_reaction: '👍', content: '👎')).to have_attributes(name: '👍', custom_emoji: nil)
  end

  it 'accepts a previously stored custom emoji' do
    emoji = Fabricate(:custom_emoji, shortcode: 'blobcat', domain: account.domain)

    expect(parse(content: ':blobcat:')).to have_attributes(name: 'blobcat', custom_emoji: emoji)
  end

  it 'rejects arbitrary strings and HTML' do
    expect(parse(content: '<img src=x onerror=alert(1)>')).to be_nil
    expect(parse(content: 'not-an-emoji')).to be_nil
  end
end
