require_relative './test_helper'

class OnlineStudentsAppTest < Minitest::Test
  def test_get
    login
    get '/'
    assert_equal 200, last_response.status
  end

  def test_post
    params = {'user_email' => 'test@gmail.com'}
    Resque.expects(:enqueue).with(OnlineStudentsWorker, params)

    login
    post '/'

    assert_equal 302, last_response.status
    assert_equal 'https://example.org/', last_response.header['Location']
    follow_redirect!
    assert_equal 200, last_response.status
  end
end
