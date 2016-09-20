require_relative './test_helper'

class OnlineStudentsAppTest < Minitest::Test
  def test_get
    login
    get '/'
    assert_equal 200, last_response.status
  end

  def test_get_unauthenticated
    get '/'
    assert_equal 302, last_response.status
    follow_redirect!
    assert_equal '/canvas-auth-login', last_request.path
  end

  def test_get_unauthorized
    login({'user_roles' => ['StudentEnrollment']})
    get '/'
    assert_equal 302, last_response.status
    follow_redirect!
    assert_equal '/unauthorized', last_request.path
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

  def test_post_unauthenticated
    post '/'
    assert_equal 302, last_response.status
    follow_redirect!
    assert_equal '/canvas-auth-login', last_request.path
  end

  def test_post_unauthorized
    login({'user_roles' => ['StudentEnrollment']})
    post '/'
    assert_equal 302, last_response.status
    follow_redirect!
    assert_equal '/unauthorized', last_request.path
  end

end
