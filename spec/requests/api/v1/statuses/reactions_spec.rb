# frozen_string_literal: true

require 'rails_helper'

RSpec.describe 'Status reactions' do
  let(:user) { Fabricate(:user) }
  let(:token) { Fabricate(:accessible_access_token, resource_owner_id: user.id, scopes: scopes) }
  let(:scopes) { 'write:favourites' }
  let(:headers) { { 'Authorization' => "Bearer #{token.token}" } }
  let(:status) { Fabricate(:status) }
  let(:encoded_name) { ERB::Util.url_encode('👍') }

  describe 'PUT /api/v1/statuses/:status_id/reactions/:name' do
    subject { put "/api/v1/statuses/#{status.id}/reactions/#{encoded_name}", headers: headers }

    it_behaves_like 'forbidden for wrong scope', 'read read:favourites'

    it 'adds a reaction and returns updated status JSON' do
      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body['reactions']).to contain_exactly(a_hash_including('name' => '👍', 'count' => 1, 'me' => true))
      expect(StatusReaction.find_by(account: user.account, status: status)).to have_attributes(name: '👍')
    end

    it 'atomically replaces the existing reaction' do
      CreateStatusReactionService.new.call(user.account, status, name: '👎')

      subject

      expect(StatusReaction.where(account: user.account, status: status).sole).to have_attributes(name: '👍')
    end
  end

  describe 'DELETE /api/v1/statuses/:status_id/reactions/:name' do
    subject { delete "/api/v1/statuses/#{status.id}/reactions/#{encoded_name}", headers: headers }

    before do
      CreateStatusReactionService.new.call(user.account, status, name: '👍')
    end

    it 'removes the matching reaction and returns updated status JSON' do
      subject

      expect(response).to have_http_status(200)
      expect(response.parsed_body['reactions']).to be_empty
      expect(StatusReaction.find_by(account: user.account, status: status)).to be_nil
    end
  end
end
