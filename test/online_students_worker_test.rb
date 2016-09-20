require_relative './test_helper'

class OnlineStudentsWorkerTest < Minitest::Test
  def setup
    super

    @query_response = [
      {'canvas_id' => '123'},
      {'canvas_id' => '124'},
      {'canvas_id' => '125'}
    ]
    @api_response = [
      {'primary_email' => 'test1@example.com'},
      {'primary_email' => 'test2@example.com'},
      {'primary_email' => 'test3@example.com'}
    ]
    @emails = @api_response.map{ |row| row['primary_email'] }

    @query_response.each_with_index do |qr, i|
      stub_request(:get, /users\/#{qr['canvas_id']}\/profile/)
        .to_return(:body => @api_response[i].to_json,
                   :headers => {'Content-Type' => 'application/json'})
    end

    OnlineStudentsApp.stubs(:canvas_data).returns(@query_response)
  end

  def test_perform
    result_count = @query_response.count
    Redis.any_instance.expects(:exists).times(result_count).returns(false)
    Redis.any_instance.expects(:set).times(result_count)
    Redis.any_instance.expects(:get).times(result_count).returns(*@emails)
    mail = mock()
    mail.expects(:deliver!)
    OnlineStudentsWorker.expects(:compose_mail).with(@emails, anything).returns(mail)

    OnlineStudentsWorker.perform({
      'enrollment-term' => '75',
      'course-type' => 'online',
      'user_email' => 'test@example.com'})

    @query_response.each do |qr|
      assert_requested :get, /users\/#{qr['canvas_id']}\/profile/
    end
  end

  def test_perform_with_cached_data
    mail = mock()
    mail.expects(:deliver!)
    Redis.any_instance.expects(:exists).times(@emails.count).returns(true)
    Redis.any_instance.stubs(:get).returns(*@emails)
    OnlineStudentsWorker.expects(:compose_mail).with(@emails, anything).returns(mail)

    OnlineStudentsWorker.perform({
      'enrollment-term' => '75',
      'course-type' => 'online',
      'user_email' => 'test@example.com'
    })

    assert_not_requested :get, /.*/
  end

  def test_perform_with_force_refresh
    result_count = @query_response.count
    Redis.any_instance.expects(:exists).times(result_count).returns(true)
    Redis.any_instance.expects(:set).times(result_count)
    Redis.any_instance.expects(:get).times(result_count).returns(*@emails)
    mail = mock()
    mail.expects(:deliver!)
    OnlineStudentsWorker.expects(:compose_mail).with(@emails, anything).returns(mail)

    OnlineStudentsWorker.perform({
      'enrollment-term' => '75',
      'course-type' => 'online',
      'user_email' => 'test@example.com',
      'refresh-data' => 'true'
    })

    @query_response.each do |qr|
      assert_requested :get, /users\/#{qr['canvas_id']}\/profile/
    end
  end

  def test_compose_mail
    attachment_content = "test1@example.com\ntest2@example.com\ntest3@example.com\n"
    File.stubs(:read).returns(attachment_content)

    mail = OnlineStudentsWorker.compose_mail(@emails, {
      'enrollment-term' => '123',
      'course-type' => 'online',
      'user_email' => 'test@example.com'
    })

    assert_equal ['donotreply@ucdenver.edu'], mail.from
    assert_equal ['test@example.com'], mail.to
    assert_equal 'Canvas Data Report', mail.subject
    assert mail.has_attachments?
    assert_equal 'emails.csv', mail.attachments.first.filename
    assert_equal attachment_content, mail.attachments.first.body.raw_source
  end

  def test_compose_mail_with_empty_data
    @emails = [
      'test3@example.com',
      'test4@example.com',
      '', nil, 'n/a'
    ]

    attachment_content = "test3@example.com\ntest4@example.com\n"
    File.stubs(:read).returns(attachment_content)

    mail = OnlineStudentsWorker.compose_mail(@emails, {
      'enrollment-term' => '75',
      'course-type' => 'online',
      'user_email' => 'test@example.com'
    })

    assert_equal ['donotreply@ucdenver.edu'], mail.from
    assert_equal ['test@example.com'], mail.to
    assert_equal 'Canvas Data Report', mail.subject
    assert mail.has_attachments?
    assert_equal 'emails.csv', mail.attachments.first.filename
    assert_equal attachment_content, mail.attachments.first.body.raw_source
  end

  def test_query_string_online
    expected = "SELECT DISTINCT user_dim.canvas_id FROM course_dim "\
               "JOIN enrollment_dim ON enrollment_dim.course_id = course_dim.id "\
               "JOIN user_dim ON enrollment_dim.user_id = user_dim.id "\
               "WHERE course_dim.code ~ 'E0[0-9]' "\
               "AND course_dim.enrollment_term_id = ? "\
               "AND enrollment_dim.workflow_state = 'active' "\
               "AND enrollment_dim.type = 'StudentEnrollment'"

    assert_equal expected, OnlineStudentsWorker.query_string('online', nil)
  end

  def test_query_string_hybrid
    expected = "SELECT DISTINCT user_dim.canvas_id FROM course_dim "\
               "JOIN enrollment_dim ON enrollment_dim.course_id = course_dim.id "\
               "JOIN user_dim ON enrollment_dim.user_id = user_dim.id "\
               "WHERE course_dim.code ~ 'H0[0-9]' "\
               "AND course_dim.enrollment_term_id = ? "\
               "AND enrollment_dim.workflow_state = 'active' "\
               "AND enrollment_dim.type = 'StudentEnrollment'"

    assert_equal expected, OnlineStudentsWorker.query_string('hybrid', nil)
  end

  def test_query_string_both
    expected = "SELECT DISTINCT user_dim.canvas_id FROM course_dim "\
               "JOIN enrollment_dim ON enrollment_dim.course_id = course_dim.id "\
               "JOIN user_dim ON enrollment_dim.user_id = user_dim.id "\
               "WHERE course_dim.code ~ '(E|H)0[0-9]' "\
               "AND course_dim.enrollment_term_id = ? "\
               "AND enrollment_dim.workflow_state = 'active' "\
               "AND enrollment_dim.type = 'StudentEnrollment'"

    assert_equal expected, OnlineStudentsWorker.query_string('both', nil)
  end

  def test_query_string_online_login_filter
    expected = "SELECT DISTINCT user_dim.canvas_id FROM course_dim "\
               "JOIN enrollment_dim ON enrollment_dim.course_id = course_dim.id "\
               "JOIN user_dim ON enrollment_dim.user_id = user_dim.id "\
               "LEFT JOIN requests ON requests.user_id = user_dim.id "\
               "AND requests.course_id = course_dim.id "\
               "WHERE course_dim.code ~ 'E0[0-9]' "\
               "AND course_dim.enrollment_term_id = ? "\
               "AND enrollment_dim.workflow_state = 'active' "\
               "AND enrollment_dim.type = 'StudentEnrollment' "\
               "GROUP BY user_dim.canvas_id HAVING COUNT(requests.user_id) = 0;"

    assert_equal expected, OnlineStudentsWorker.query_string('online', true)
  end

  def test_query_string_hybrid_login_filter
    expected = "SELECT DISTINCT user_dim.canvas_id FROM course_dim "\
               "JOIN enrollment_dim ON enrollment_dim.course_id = course_dim.id "\
               "JOIN user_dim ON enrollment_dim.user_id = user_dim.id "\
               "LEFT JOIN requests ON requests.user_id = user_dim.id "\
               "AND requests.course_id = course_dim.id "\
               "WHERE course_dim.code ~ 'H0[0-9]' "\
               "AND course_dim.enrollment_term_id = ? "\
               "AND enrollment_dim.workflow_state = 'active' "\
               "AND enrollment_dim.type = 'StudentEnrollment' "\
               "GROUP BY user_dim.canvas_id HAVING COUNT(requests.user_id) = 0;"

    assert_equal expected, OnlineStudentsWorker.query_string('hybrid', true)
  end

  def test_query_string_both_login_filter
    expected = "SELECT DISTINCT user_dim.canvas_id FROM course_dim "\
               "JOIN enrollment_dim ON enrollment_dim.course_id = course_dim.id "\
               "JOIN user_dim ON enrollment_dim.user_id = user_dim.id "\
               "LEFT JOIN requests ON requests.user_id = user_dim.id "\
               "AND requests.course_id = course_dim.id "\
               "WHERE course_dim.code ~ '(E|H)0[0-9]' "\
               "AND course_dim.enrollment_term_id = ? "\
               "AND enrollment_dim.workflow_state = 'active' "\
               "AND enrollment_dim.type = 'StudentEnrollment' "\
               "GROUP BY user_dim.canvas_id HAVING COUNT(requests.user_id) = 0;"

    assert_equal expected, OnlineStudentsWorker.query_string('both', true)
  end
end
