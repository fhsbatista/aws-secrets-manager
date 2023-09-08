class TestController < ApplicationController
    def get_value
        render json: { value: "hardcoded value" }
    end
end