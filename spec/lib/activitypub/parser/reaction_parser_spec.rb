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

  it 'rejects oversized custom emoji shortcodes before parsing their remote image' do
    shortcode = 'a' * (CustomEmoji::MAX_SHORTCODE_SIZE + 1)
    tag = { type: 'Emoji', name: ":#{shortcode}:", icon: { url: 'https://remote.example/emoji.png' } }

    expect(ActivityPub::Parser::CustomEmojiParser).to_not receive(:new)
    expect(parse(content: ":#{shortcode}:", tag: [tag])).to be_nil
  end

  it 'does not create or download a new custom emoji after the remote domain limit is reached' do
    rate_limiter = instance_double(RateLimiter)
    tag = { id: 'https://remote.example/emojis/blobcat', type: 'Emoji', name: ':blobcat:', icon: { url: 'https://remote.example/emoji.png' } }

    allow(RateLimiter).to receive(:new)
      .with(have_attributes(id: 'remote-reaction-emoji:remote.example'), family: :remote_reaction_emoji_downloads)
      .and_return(rate_limiter)
    allow(rate_limiter).to receive(:record!).and_raise(Mastodon::RateLimitExceededError)

    expect { parse(content: ':blobcat:', tag: [tag]) }.to_not change(CustomEmoji, :count)
  end
end
