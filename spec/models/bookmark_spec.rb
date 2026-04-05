require "rails_helper"

RSpec.describe Bookmark, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user) }
    it { is_expected.to belong_to(:event) }
  end

  describe "validations" do
    subject { build(:bookmark) }

    it { is_expected.to validate_uniqueness_of(:user_id).scoped_to(:event_id) }
  end
end
