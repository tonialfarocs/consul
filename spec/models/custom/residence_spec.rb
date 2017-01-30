require 'rails_helper'

describe Verification::Residence do

  let(:residence) { build(:verification_residence, document_number: "12345678Z") }

  describe "verification" do

    describe "postal code" do
      it "should be valid with postal codes starting with 120" do
        residence.postal_code = "12012"
        residence.valid?
        expect(residence.errors[:postal_code].size).to eq(0)

        residence.postal_code = "12023"
        residence.valid?
        expect(residence.errors[:postal_code].size).to eq(0)
      end

      it "should not be valid with postal codes not starting with 120" do
        residence.postal_code = "22045"
        residence.valid?
        expect(residence.errors[:postal_code].size).to eq(1)

        residence.postal_code = "21080"
        residence.valid?
        expect(residence.errors[:postal_code].size).to eq(1)
        expect(residence.errors[:postal_code]).to include("In order to be verified, you must be registered.")
      end
    end

  end

end
