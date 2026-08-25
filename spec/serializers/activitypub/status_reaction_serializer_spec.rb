# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::StatusReactionSerializer do
  subject { serialized_record_json(reaction, described_class, adapter: ActivityPub::Adapter) }

  let(:account) { Fabricate(:account) }
  let(:status) { Fabricate(:status) }
  let(:reaction) { StatusReaction.create!(account: account, status: status, name: '👍', activity_type: activity_type) }

  context 'with the Misskey-compatible Like protocol' do
    let(:activity_type) { :like }

    it 'includes both interoperable content forms' do
      expect(subject).to include(
        'type' => 'Like',
        'content' => '👍',
        '_misskey_reaction' => '👍',
        'object' => ActivityPub::TagManager.instance.uri_for(status)
      )
    end
  end

  context 'with EmojiReact' do
    let(:activity_type) { :emoji_react }

    it 'uses the learned EmojiReact protocol without the Misskey property' do
      expect(subject).to include('type' => 'EmojiReact', 'content' => '👍')
      expect(subject).to_not have_key('_misskey_reaction')
    end
  end

  context 'with a legacy local activity type' do
    let(:activity_type) { :local }

    it 'uses the Like-compatible Misskey fallback when federated' do
      expect(subject).to include('type' => 'Like', 'content' => '👍', '_misskey_reaction' => '👍')
    end
  end

  context 'with a custom emoji' do
    let(:activity_type) { :like }
    let(:custom_emoji) { Fabricate(:custom_emoji) }
    let(:reaction) do
      StatusReaction.create!(
        account: account,
        status: status,
        name: custom_emoji.shortcode,
        custom_emoji: custom_emoji,
        activity_type: activity_type
      )
    end

    it 'includes both reaction fallbacks and the Emoji tag' do
      expect(subject).to include(
        'type' => 'Like',
        'content' => ":#{custom_emoji.shortcode}:",
        '_misskey_reaction' => ":#{custom_emoji.shortcode}:"
      )
      expect(subject.fetch('tag')).to contain_exactly(include('type' => 'Emoji', 'name' => ":#{custom_emoji.shortcode}:"))
    end
  end
end
