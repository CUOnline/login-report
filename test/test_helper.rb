ENV['RACK_ENV'] ||= 'test'

require_relative '../online_students_app'
require 'minitest'
require 'minitest/autorun'
require 'minitest/rg'
require 'mocha/mini_test'
require 'rack/test'
require 'webmock/minitest'

# Turn on SSL for all requests
class Rack::Test::Session
  def default_env
    { 'rack.test' => true,
      'REMOTE_ADDR' => '127.0.0.1',
      'HTTPS' => 'on'
    }.merge(@env).merge(headers_for_env)
  end
end

class Minitest::Test

  include Rack::Test::Methods

  def app
    OnlineStudentsApp
  end

  def setup
    WebMock.enable!
    WebMock.disable_net_connect!(allow_localhost: true)
    WebMock.reset!

    Mail::Message.any_instance.stubs(:deliver!)
    app.settings.stubs(:api_cache).returns(false)
    app.stubs(:enrollment_terms).returns({
      '75' => 'Spring 2015',
      '76' => 'Summer 2015',
      '77' => 'Fall 2016'
    })
  end

  def login(session_params = {})
    defaults = {
      'user_id' => '123',
      'user_roles' => ['AccountAdmin'],
      'user_email' => 'test@gmail.com'
    }

    env 'rack.session', defaults.merge(session_params)
  end
end
