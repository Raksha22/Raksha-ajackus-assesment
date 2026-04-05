require "rails_helper"

RSpec.describe Api::V1::OrdersController, type: :request do
  let(:organizer) { create(:user, :organizer) }
  let(:attendee) { create(:user) }
  let(:event) { create(:event, user: organizer, status: "published", starts_at: 2.weeks.from_now, ends_at: 2.weeks.from_now + 3.hours) }
  let(:tier) { create(:ticket_tier, event: event, quantity: 100, sold_count: 0) }

  def auth_headers(user)
    token = user.generate_jwt
    { "Authorization" => "Bearer #{token}" }
  end

  describe "GET /api/v1/orders" do
    it "returns only the current user's orders" do
      other = create(:user)
      mine = create(:order, user: attendee, event: event)
      create(:order, user: other, event: event)

      get "/api/v1/orders", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      expect(data.length).to eq(1)
      expect(data.first["id"]).to eq(mine.id)
    end

    it "returns an empty array when the user has no orders" do
      get "/api/v1/orders", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it "returns multiple orders for the same user, newest first" do
      older = create(:order, user: attendee, event: event, created_at: 2.days.ago)
      newer = create(:order, user: attendee, event: event, created_at: 1.day.ago)

      get "/api/v1/orders", headers: auth_headers(attendee)

      ids = JSON.parse(response.body).map { |o| o["id"] }
      expect(ids).to eq([newer.id, older.id])
    end

    it "returns 401 without a valid Authorization header" do
      get "/api/v1/orders"

      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with a malformed token" do
      get "/api/v1/orders", headers: { "Authorization" => "Bearer not-a-jwt" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/orders/:id" do
    it "returns order details for the owner's order" do
      order = create(:order, user: attendee, event: event)

      get "/api/v1/orders/#{order.id}", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(order.id)
      expect(body["confirmation_number"]).to eq(order.confirmation_number)
      expect(body["event"]["title"]).to eq(event.title)
    end

    it "does not expose another user's order" do
      other = create(:user)
      other_order = create(:order, user: other, event: event)

      get "/api/v1/orders/#{other_order.id}", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("Not found")
    end

    it "returns 404 for a non-existent order id" do
      get "/api/v1/orders/999999999", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("Not found")
    end

    it "returns 404 for a non-numeric id (avoids DB cast errors)" do
      get "/api/v1/orders/not-a-number", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(JSON.parse(response.body)["error"]).to eq("Not found")
    end

    it "returns 401 without authentication" do
      order = create(:order, user: attendee, event: event)

      get "/api/v1/orders/#{order.id}"

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/orders/:id/cancel" do
    it "cancels a pending order" do
      order = create(:order, user: attendee, event: event, status: "pending")

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("cancelled")
    end

    it "cancels a confirmed order" do
      order = create(:order, user: attendee, event: event, status: "confirmed")

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:ok)
      expect(order.reload.status).to eq("cancelled")
    end

    it "returns 422 when the order is already cancelled" do
      order = create(:order, user: attendee, event: event, status: "cancelled")

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("cancelled")
      expect(order.reload.status).to eq("cancelled")
    end

    it "returns 422 when the order is refunded" do
      order = create(:order, user: attendee, event: event, status: "refunded")

      post "/api/v1/orders/#{order.id}/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("refunded")
      expect(order.reload.status).to eq("refunded")
    end

    it "does not cancel another user's order" do
      other = create(:user)
      other_order = create(:order, user: other, event: event, status: "pending")

      post "/api/v1/orders/#{other_order.id}/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
      expect(other_order.reload.status).to eq("pending")
    end

    it "returns 404 for a non-existent order id" do
      post "/api/v1/orders/999999999/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 404 for a non-numeric id" do
      post "/api/v1/orders/abc/cancel", headers: auth_headers(attendee)

      expect(response).to have_http_status(:not_found)
    end

    it "returns 401 without authentication" do
      order = create(:order, user: attendee, event: event, status: "pending")

      post "/api/v1/orders/#{order.id}/cancel"

      expect(response).to have_http_status(:unauthorized)
      expect(order.reload.status).to eq("pending")
    end
  end
end
