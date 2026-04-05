require "rails_helper"

RSpec.describe "Bookmarks API", type: :request do
  let(:organizer) { create(:user, :organizer) }
  let(:other_organizer) { create(:user, :organizer) }
  let(:attendee) { create(:user) }
  let(:other_attendee) { create(:user) }
  let(:event) { create(:event, user: organizer, status: "published", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours) }

  def auth_headers(user)
    token = user.generate_jwt
    { "Authorization" => "Bearer #{token}" }
  end

  describe "POST /api/v1/events/:event_id/bookmarks" do
    it "creates a bookmark for an attendee" do
      post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["event_id"]).to eq(event.id)
      expect(Bookmark.find_by(user: attendee, event: event)).to be_present
    end

    it "rejects a duplicate bookmark" do
      create(:bookmark, user: attendee, event: event)

      post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["errors"]).to be_present
    end

    it "rejects bookmark creation for an organizer" do
      post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(organizer)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to include("attendees")
    end

    it "rejects bookmark creation for an admin" do
      admin = create(:user, :admin)

      post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      post "/api/v1/events/#{event.id}/bookmarks"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 404 for a non-numeric event id" do
      post "/api/v1/events/not-a-number/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("Not found")
    end

    it "returns 404 for a missing event id" do
      post "/api/v1/events/999999999/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end

    it "allows two different attendees to bookmark the same event" do
      create(:bookmark, user: attendee, event: event)

      post "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(other_attendee)

      expect(response).to have_http_status(:created)
      expect(Bookmark.where(event: event).count).to eq(2)
    end
  end

  describe "DELETE /api/v1/events/:event_id/bookmarks" do
    it "removes the current user's bookmark" do
      create(:bookmark, user: attendee, event: event)

      delete "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:no_content)
      expect(Bookmark.find_by(user: attendee, event: event)).to be_nil
    end

    it "returns 404 when no bookmark exists for that event" do
      delete "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end

    it "does not remove another user's bookmark" do
      create(:bookmark, user: other_attendee, event: event)

      delete "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(Bookmark.find_by(user: other_attendee, event: event)).to be_present
    end

    it "returns 403 for an organizer" do
      create(:bookmark, user: attendee, event: event)

      delete "/api/v1/events/#{event.id}/bookmarks", headers: auth_headers(organizer)

      expect(response).to have_http_status(:forbidden)
      expect(Bookmark.find_by(user: attendee, event: event)).to be_present
    end

    it "returns 404 for a non-numeric event id" do
      delete "/api/v1/events/abc/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/bookmarks" do
    it "lists only the current user's bookmarks, newest first" do
      older_event = create(:event, user: organizer, status: "published", starts_at: 3.weeks.from_now, ends_at: 3.weeks.from_now + 3.hours)
      older = create(:bookmark, user: attendee, event: older_event, created_at: 2.days.ago)
      newer = create(:bookmark, user: attendee, event: event, created_at: 1.day.ago)
      create(:bookmark, user: other_attendee, event: event)

      get "/api/v1/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.length).to eq(2)
      expect(data.map { |b| b["id"] }).to eq([newer.id, older.id])
    end

    it "returns an empty array when there are no bookmarks" do
      get "/api/v1/bookmarks", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it "returns 403 for an organizer" do
      get "/api/v1/bookmarks", headers: auth_headers(organizer)

      expect(response).to have_http_status(:forbidden)
    end

    it "returns 401 without authentication" do
      get "/api/v1/bookmarks"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/events/:id bookmark_count" do
    it "includes bookmark_count for the owning organizer" do
      create(:bookmark, user: attendee, event: event)
      create(:bookmark, user: other_attendee, event: event)

      get "/api/v1/events/#{event.id}", headers: auth_headers(organizer)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["bookmark_count"]).to eq(2)
    end

    it "omits bookmark_count for an attendee" do
      create(:bookmark, user: attendee, event: event)

      get "/api/v1/events/#{event.id}", headers: auth_headers(attendee)

      body = JSON.parse(response.body)
      expect(body).not_to have_key("bookmark_count")
    end

    it "omits bookmark_count when unauthenticated" do
      create(:bookmark, user: attendee, event: event)

      get "/api/v1/events/#{event.id}"

      expect(JSON.parse(response.body)).not_to have_key("bookmark_count")
    end

    it "omits bookmark_count for another organizer viewing the event" do
      create(:bookmark, user: attendee, event: event)

      get "/api/v1/events/#{event.id}", headers: auth_headers(other_organizer)

      expect(JSON.parse(response.body)).not_to have_key("bookmark_count")
    end

    it "omits bookmark_count when the event owner is attendee role (not organizer role)" do
      owner = create(:user, role: "attendee")
      owned = create(:event, user: owner, status: "published", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours)
      create(:bookmark, user: attendee, event: owned)

      get "/api/v1/events/#{owned.id}", headers: auth_headers(owner)

      expect(JSON.parse(response.body)).not_to have_key("bookmark_count")
    end
  end
end
