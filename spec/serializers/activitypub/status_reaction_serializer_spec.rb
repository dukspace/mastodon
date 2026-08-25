# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::StatusReactionSerializer do
  subject { serialized_record_json(reaction, described_class, adapter: ActivityPub::Adapter) }

  let(:account) { Fabricate(:account) }
  let(:status) { Fabricate(:status) }
  let(:activity_type) { :like }
  let(:reaction) { StatusReaction.create!(account: account, status: status, name: '👍', activity_type: activity_type) }

  it 'addresses a public reaction to the public collection, reactor followers, and status author' do
    expect(subject).to include(
      'to' => [ActivityPub::TagManager::COLLECTIONS[:public]],
      'cc' => contain_exactly(
        ActivityPub::TagManager.instance.followers_uri_for(account),
        ActivityPub::TagManager.instance.uri_for(status.account)
      )
    )
  end

  context 'with an unlisted status' do
    let(:status) { Fabricate(:status, visibility: :unlisted) }

    it 'addresses the reaction primarily to reactor followers and the status author' do
      expect(subject).to include(
        'to' => contain_exactly(
          ActivityPub::TagManager.instance.followers_uri_for(account),
          ActivityPub::TagManager.instance.uri_for(status.account)
        ),
        'cc' => [ActivityPub::TagManager::COLLECTIONS[:public]]
      )
    end
  end

  context 'with a direct status' do
    let(:mentioned_account) { Fabricate(:account, domain: 'mentioned.example', protocol: :activitypub) }
    let(:status) { Fabricate(:status, visibility: :direct).tap { |record| Fabricate(:mention, status: record, account: mentioned_account) } }

    it 'addresses the reaction only to the status author and explicit audience' do
      expect(subject).to include(
        'to' => contain_exactly(
          ActivityPub::TagManager.instance.uri_for(status.account),
          ActivityPub::TagManager.instance.uri_for(mentioned_account)
        ),
        'cc' => []
      )
    end
  end

  context 'with a private status from a local author' do
    let(:status) { Fabricate(:status, visibility: :private) }

    it 'includes the status author followers collection in the primary audience' do
      expect(subject.fetch('to')).to include(ActivityPub::TagManager.instance.followers_uri_for(status.account))
      expect(subject.fetch('cc')).to be_empty
    end
  end

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
