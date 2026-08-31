# frozen_string_literal: true

require 'rails_helper'

RSpec.describe ActivityPub::Activity::Undo do
  let(:sender) { Fabricate(:account, domain: 'remote.example') }
  let(:status) { Fabricate(:status) }

  def perform_undo(object)
    described_class.new(
      {
        id: 'https://remote.example/undo/1',
        type: 'Undo',
        actor: sender.uri,
        object: object,
      }.with_indifferent_access,
      sender
    ).perform
  end

  it 'removes an EmojiReact only when its activity URI matches' do
    reaction = StatusReaction.create!(status: status, account: sender, name: '👍', activity_type: :emoji_react, activity_uri: 'https://remote.example/reactions/1')

    perform_undo({ id: reaction.activity_uri, type: 'EmojiReact', object: ActivityPub::TagManager.instance.uri_for(status) })

    expect(StatusReaction.exists?(reaction.id)).to be(false)
  end

  it 'ignores a delayed Undo for a superseded Like reaction' do
    StatusReaction.create!(status: status, account: sender, name: '👎', activity_type: :like, activity_uri: 'https://remote.example/reactions/new')

    perform_undo({ id: 'https://remote.example/reactions/old', type: 'Like', object: ActivityPub::TagManager.instance.uri_for(status) })

    expect(StatusReaction.find_by(account: sender, status: status)).to have_attributes(name: '👎')
  end

  context 'when the original status is remote' do
    let(:status) { Fabricate(:status, account: Fabricate(:account, domain: 'author.example', protocol: :activitypub)) }

    it 'removes an exact Like reaction without requiring a Favourite' do
      reaction = StatusReaction.create!(status: status, account: sender, name: '👍', activity_type: :like, activity_uri: 'https://remote.example/reactions/1')

      perform_undo({ id: reaction.activity_uri, type: 'Like', object: ActivityPub::TagManager.instance.uri_for(status), _misskey_reaction: '👍' })

      expect(StatusReaction.exists?(reaction.id)).to be(false)
      expect(status.favourites.where(account: sender)).to be_empty
    end

    it 'does not remove a replacement when an older Like Undo arrives' do
      replacement = StatusReaction.create!(status: status, account: sender, name: '👎', activity_type: :like, activity_uri: 'https://remote.example/reactions/new')

      perform_undo({ id: 'https://remote.example/reactions/old', type: 'Like', object: ActivityPub::TagManager.instance.uri_for(status), _misskey_reaction: '👍' })

      expect(replacement.reload).to have_attributes(name: '👎')
    end
  end
end
