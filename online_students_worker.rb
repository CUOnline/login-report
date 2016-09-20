require 'csv'
require 'tempfile'
require './online_students_app'

class OnlineStudentsWorker
  @queue = 'online-students'

  def self.query_string(course_type, login_filter)
    course_code_pattern = case course_type
      when 'online'
        'E0[0-9]'
      when 'hybrid'
        'H0[0-9]'
      else
        '(E|H)0[0-9]'
    end

    q =
    "SELECT DISTINCT user_dim.canvas_id "\
    "FROM course_dim "\
    "JOIN enrollment_dim "\
      "ON enrollment_dim.course_id = course_dim.id "\
    "JOIN user_dim "\
      "ON enrollment_dim.user_id = user_dim.id "

    q +=
    "LEFT JOIN requests "\
    "ON requests.user_id = user_dim.id "\
    "AND requests.course_id = course_dim.id " if login_filter

    q +=
    "WHERE course_dim.code ~ '#{course_code_pattern}' "\
    "AND course_dim.enrollment_term_id = ? "\
    "AND enrollment_dim.workflow_state = 'active' "\
    "AND enrollment_dim.type = 'StudentEnrollment'"

    q +=
    " GROUP BY user_dim.canvas_id HAVING COUNT(requests.user_id) = 0;" if login_filter

    q
  end

  def self.perform(params)
    data = OnlineStudentsApp.canvas_data(
      query_string(params['course-type'], params['login-filter']),
      OnlineStudentsApp.shard_id(params['enrollment-term'])
    )

    results = []
    data.each do |row|
      begin
        set_value = nil
        # Check redis first (user:[user id]:email => email)
        if !OnlineStudentsApp.redis.exists("user:#{row['canvas_id']}:email") ||
           params['refresh-data']

          # Get email from API if not in redis
          profile = OnlineStudentsApp.canvas_api.get("users/#{row['canvas_id']}/profile")

          # If no email set in Canvas, cache a value anyway to avoid API next time
          set_value = (profile['primary_email'] || 'n/a').downcase
        end
      rescue RestClient::Unauthorized, RestClient::ResourceNotFound
        set_value = 'n/a'
      end

      if set_value
        # Expire randomly between 1 and 3 weeks
        # Keeps up to date but prevents rebuilding cache all at once
        expire_seconds = 60 * 60 * 24 * (7..21).to_a.sample
        OnlineStudentsApp.redis.set("user:#{row['canvas_id']}:email", set_value, :ex => expire_seconds)
      end

      results << OnlineStudentsApp.redis.get("user:#{row['canvas_id']}:email")
    end

    mail = compose_mail(results, params)
    mail.deliver!
  end

  def self.compose_mail(results, params)
    results = results.reject{ |r| r == 'n/a' || r.nil? || r.empty? }
    body_str = %{
      Online Student Report
      =====================
      #{Time.now}
      Course type: #{params['course-type'].capitalize}
      Term: #{OnlineStudentsApp.enrollment_terms[params['enrollment-term']]}
      Login filter: #{(!(params['login-filter'].nil?)).to_s.capitalize}
      Total Students #{results.count}
    }
    mail = Mail.new
    mail.from = OnlineStudentsApp.from_email
    mail.to = params['user_email']
    mail.subject = OnlineStudentsApp.email_subject
    mail.body = body_str
    mail.attachments['emails.csv'] = results.join("\n") + "\n"
    mail
  end
end
