require 'rack/test'
require 'doozque/server'

module Doozque
  module TestHelper
    class Test::Unit::TestCase
      include Rack::Test::Methods
      def app
        Doozque::Server.new
      end 

      def self.should_respond_with_success
        test "should respond with success" do
          assert last_response.ok?, last_response.errors
        end
      end
    end
  end
end
