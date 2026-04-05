module Api
  module V1
    class EventsController < ApplicationController
      skip_before_action :authenticate_user!, only: [:index, :show]
      before_action :authenticate_user_optional, only: [:show]

      def index
        events = Event.published.upcoming

        if params[:search].present?
          events = events.where("title LIKE '%#{params[:search]}%' OR description LIKE '%#{params[:search]}%'")
        end

        if params[:category].present?
          events = events.where(category: params[:category])
        end

        if params[:city].present?
          events = events.where(city: params[:city])
        end

        events = events.order(params[:sort_by] || "starts_at ASC")

        render json: events.map { |event|
          {
            id: event.id,
            title: event.title,
            description: event.description,
            venue: event.venue,
            city: event.city,
            starts_at: event.starts_at,
            ends_at: event.ends_at,
            category: event.category,
            organizer: event.user.name,
            total_tickets: event.total_tickets,
            tickets_sold: event.total_sold,
            ticket_tiers: event.ticket_tiers.map { |t|
              {
                id: t.id,
                name: t.name,
                price: t.price.to_f,
                available: t.available_quantity
              }
            }
          }
        }
      end

      def show
        event = Event.find(params[:id])

        payload = {
          id: event.id,
          title: event.title,
          description: event.description,
          venue: event.venue,
          city: event.city,
          starts_at: event.starts_at,
          ends_at: event.ends_at,
          status: event.status,
          category: event.category,
          organizer: {
            id: event.user.id,
            name: event.user.name
          },
          ticket_tiers: event.ticket_tiers.map { |t|
            {
              id: t.id,
              name: t.name,
              price: t.price.to_f,
              quantity: t.quantity,
              sold: t.sold_count,
              available: t.available_quantity
            }
          }
        }
        payload[:bookmark_count] = event.bookmarks.count if show_bookmark_count?(event)

        render json: payload
      end

      def create
        event = Event.new(event_params)
        event.user = current_user

        if event.save
          render json: event, status: :created
        else
          render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def update
        event = Event.find(params[:id])

        if event.update(event_params)
          render json: event
        else
          render json: { errors: event.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def destroy
        event = Event.find(params[:id])
        event.destroy
        head :no_content
      end

      private

      def event_params
        params.require(:event).permit(:title, :description, :venue, :city,
          :starts_at, :ends_at, :category, :max_capacity, :status)
      end

      def authenticate_user_optional
        @current_user = nil
        header = request.headers["Authorization"]
        token = header&.split(" ")&.last
        return if token.blank?

        begin
          decoded = JWT.decode(token, Rails.application.secret_key_base, true, algorithm: "HS256")
          @current_user = User.find(decoded[0]["user_id"])
        rescue JWT::DecodeError, ActiveRecord::RecordNotFound
          @current_user = nil
        end
      end

      def show_bookmark_count?(event)
        current_user.present? &&
          current_user.organizer? &&
          event.user_id == current_user.id
      end
    end
  end
end
