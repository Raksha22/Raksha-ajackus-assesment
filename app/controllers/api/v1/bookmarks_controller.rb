module Api
  module V1
    class BookmarksController < ApplicationController
      before_action :ensure_attendee!, only: [:index, :create, :destroy]
      before_action :set_event, only: [:create, :destroy]

      def index
        bookmarks = current_user.bookmarks.includes(:event).order(created_at: :desc)

        render json: bookmarks.map { |bookmark|
          {
            id: bookmark.id,
            created_at: bookmark.created_at,
            event: {
              id: bookmark.event.id,
              title: bookmark.event.title,
              starts_at: bookmark.event.starts_at,
              city: bookmark.event.city
            }
          }
        }
      end

      def create
        bookmark = Bookmark.new(user: current_user, event: @event)
        bookmark.save!

        render json: {
          id: bookmark.id,
          event_id: bookmark.event_id,
          created_at: bookmark.created_at
        }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
      rescue ActiveRecord::RecordNotUnique
        render json: { errors: ["Bookmark already exists for this event"] }, status: :unprocessable_entity
      end

      def destroy
        bookmark = current_user.bookmarks.find_by(event_id: @event.id)
        unless bookmark
          render json: { error: "Not found" }, status: :not_found
          return
        end

        bookmark.destroy!
        head :no_content
      end

      private

      def ensure_attendee!
        return if current_user.attendee?

        render json: { error: "Only attendees may manage bookmarks" }, status: :forbidden
      end

      def set_event
        eid = Integer(params[:event_id], exception: false)
        unless eid
          render json: { error: "Not found" }, status: :not_found
          return
        end

        @event = Event.find_by(id: eid)
        unless @event
          render json: { error: "Not found" }, status: :not_found
          return
        end
      end
    end
  end
end
